/**
 * send-push — Supabase Edge Function
 *
 * Called by the nightly pipeline after notification_candidates.json is generated.
 * Reads the candidates, scores them per-user against their saved preferences,
 * and sends a single personalized FCM push to each user's device.
 *
 * Required Supabase secrets:
 *   FCM_SERVICE_ACCOUNT  — full Firebase service account JSON (stringified)
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Candidate {
  promo_id: string;
  brand: string;
  category: string;
  notify_score: number;
  notification_title: string;
  notification_body: string;
}

interface UserRow {
  user_id: string;
  token: string;
  favorite_brands: string[];
  favorite_categories: string[];
}

// ── Scoring constants (mirror notification_service.dart) ──────────────────────

const MIN_GLOBAL_QUALITY  = 60;
const PERSONAL_THRESHOLD  = 95;
const UNKNOWN_THRESHOLD   = 105;
const BRAND_BONUS         = 40;
const CATEGORY_BONUS      = 25;

// ── FCM helper ────────────────────────────────────────────────────────────────

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const binary = atob(b64);
  const buf = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i);
  return buf.buffer;
}

function b64url(data: string | ArrayBuffer): string {
  const str = typeof data === 'string'
    ? btoa(data)
    : btoa(String.fromCharCode(...new Uint8Array(data)));
  return str.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header  = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({
    iss: sa.client_email,
    sub: sa.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }));

  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${b64url(sig)}`;

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const json = await resp.json() as { access_token?: string; error?: string; error_description?: string };
  if (!json.access_token) {
    throw new Error(`OAuth token exchange failed (${resp.status}): ${json.error} — ${json.error_description}`);
  }
  return json.access_token;
}

async function sendFcm(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  promoId: string,
): Promise<{ ok: boolean; error?: string }> {
  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: { promo_id: promoId },
          apns: {
            payload: { aps: { sound: 'default', badge: 1 } },
          },
          android: {
            priority: 'high',
            notification: { sound: 'default' },
          },
        },
      }),
    },
  );
  if (resp.ok) return { ok: true };
  const errBody = await resp.text().catch(() => '(no body)');
  return { ok: false, error: `HTTP ${resp.status}: ${errBody}` };
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // Parse candidates from request body
  let candidates: Candidate[] = [];
  try {
    const body = await req.json() as { candidates?: Candidate[] };
    candidates = body.candidates ?? [];
  } catch {
    return new Response('Invalid JSON body', { status: 400 });
  }

  if (candidates.length === 0) {
    return new Response(JSON.stringify({ sent: 0, reason: 'no candidates' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Load FCM service account
  const saRaw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!saRaw) {
    return new Response('FCM_SERVICE_ACCOUNT secret not set', { status: 500 });
  }
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(saRaw);
  } catch (e) {
    return new Response(`FCM_SERVICE_ACCOUNT is not valid JSON: ${e}`, { status: 500 });
  }

  // Supabase admin client to query users
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Query from users so both device_tokens and user_preferences can be
  // joined via their user_id FKs (device_tokens has no FK to user_preferences).
  const { data: rows, error } = await supabase
    .from('users')
    .select(`
      id,
      device_tokens!inner(token),
      user_preferences!inner(favorite_brands, favorite_categories)
    `);

  if (error) {
    return new Response(`DB error: ${error.message}`, { status: 500 });
  }

  // Flatten: one UserRow per device token (a user may have multiple devices).
  const users: UserRow[] = [];
  for (const row of (rows ?? [])) {
    const prefsArr: any[] = Array.isArray(row.user_preferences)
      ? row.user_preferences : [row.user_preferences];
    const prefs = prefsArr[0];
    if (!prefs) continue;
    for (const dt of (row.device_tokens ?? [])) {
      if (!dt?.token) continue;
      users.push({
        user_id:             row.id,
        token:               dt.token,
        favorite_brands:     prefs.favorite_brands     ?? [],
        favorite_categories: prefs.favorite_categories ?? [],
      });
    }
  }

  // Filter candidates below quality floor
  const qualified = candidates.filter(c => c.notify_score >= MIN_GLOBAL_QUALITY);

  // Fetch promo_ids sent to each user in the last 7 days
  const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const { data: recentLogs } = await supabase
    .from('notification_log')
    .select('user_id, promo_id')
    .gte('sent_at', cutoff);

  const recentSent = new Set<string>(
    (recentLogs ?? []).map((r: any) => `${r.user_id}:${r.promo_id}`)
  );

  let accessToken: string | null = null;
  let sent = 0;
  const fcmErrors: string[] = [];

  for (const user of users) {
    const favBrands = new Set(user.favorite_brands.map(b => b.toLowerCase()));
    const favCats   = new Set(user.favorite_categories.map(c => c.toLowerCase()));

    // Score all qualified candidates for this user, skipping recently sent ones
    const scored = qualified
      .filter(c => !recentSent.has(`${user.user_id}:${c.promo_id}`))
      .map(c => {
        let score = c.notify_score;
        const isFavBrand = favBrands.has(c.brand.toLowerCase());
        const isFavCat   = favCats.has(c.category.toLowerCase());
        if (isFavBrand) score += BRAND_BONUS;
        if (isFavCat)   score += CATEGORY_BONUS;
        const threshold = (isFavBrand || isFavCat) ? PERSONAL_THRESHOLD : UNKNOWN_THRESHOLD;
        return { c, score, threshold };
      }).filter(e => e.score >= e.threshold);

    if (scored.length === 0) continue;

    // Best candidate for this user
    scored.sort((a, b) => b.score - a.score);
    const best = scored[0];
    const { c } = best;

    const dealLine = favBrands.has(c.brand.toLowerCase())
      ? `${c.notification_title}: ${c.notification_body} — from a brand you love`
      : favCats.has(c.category.toLowerCase())
        ? `${c.notification_title}: ${c.notification_body} — in a category you follow`
        : `${c.notification_title}: ${c.notification_body}`;

    // Lazy-init access token (shared across all users in this batch)
    if (!accessToken) {
      accessToken = await getAccessToken(sa);
    }

    const result = await sendFcm(
      accessToken,
      sa.project_id,
      user.token,
      'Deal of the Day for You',
      dealLine,
      c.promo_id,
    );
    if (result.ok) {
      sent++;
      // Log so this deal isn't sent to this user again for 7 days
      await supabase.from('notification_log').insert({
        user_id:  user.user_id,
        promo_id: c.promo_id,
      });
    } else if (result.error) {
      fcmErrors.push(`user ${user.user_id}: ${result.error}`);
    }
  }

  return new Response(
    JSON.stringify({ sent, users: users.length, candidates: qualified.length, fcm_errors: fcmErrors }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
