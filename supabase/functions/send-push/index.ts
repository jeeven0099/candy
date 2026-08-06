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

// Per-user activity derived from recent in-app behaviour (last 7 days).
interface UserActivity {
  // Brands the user explicitly searched for (highest intent signal)
  searchedBrands: Set<string>;
  // Categories the user searched for
  searchedCats: Set<string>;
  // Brands the user opened / clicked deals from
  clickedBrands: Set<string>;
  // Categories the user engaged with
  clickedCats: Set<string>;
}

// ── Scoring constants ─────────────────────────────────────────────────────────

const MIN_GLOBAL_QUALITY   = 65;   // matches raised pipeline threshold
const PERSONAL_THRESHOLD   = 90;   // bar when there's any known affinity
const UNKNOWN_THRESHOLD    = 110;  // bar when user has zero relationship to deal

// Onboarding prefs (lower weight — stated intent, may be stale)
const FAV_BRAND_BONUS      = 35;
const FAV_CAT_BONUS        = 20;

// Recent in-app behaviour (higher weight — demonstrated, current intent)
const SEARCH_BRAND_BONUS   = 55;  // user searched for this brand by name
const SEARCH_CAT_BONUS     = 30;  // user searched a term matching this category
const CLICKED_BRAND_BONUS  = 45;  // user opened / clicked a deal from this brand
const CLICKED_CAT_BONUS    = 20;  // user engaged with this category

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

  // Query users with device tokens and onboarding prefs
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

  // Flatten: one UserRow per device token (a user may have multiple devices)
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

  // ── Batch-fetch all recent signals in 3 parallel queries ─────────────────────
  const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  const [recentLogsRes, interactionsRes, searchesRes] = await Promise.all([
    // Notifications already sent — prevent repeats within 7 days
    supabase.from('notification_log')
      .select('user_id, promo_id')
      .gte('sent_at', cutoff),

    // Recent deal opens and clicks — strongest intent signal
    supabase.from('user_interactions')
      .select('user_id, brand, category')
      .in('event_type', ['deal_card_opened', 'deal_card_clicked', 'redeem_clicked', 'fast_redeem_clicked'])
      .gte('created_at', cutoff)
      .not('user_id', 'is', null),

    // Recent searches — explicit interest the user typed
    supabase.from('search_events')
      .select('user_id, query, normalized_query')
      .gte('created_at', cutoff)
      .not('user_id', 'is', null),
  ]);

  const recentSent = new Set<string>(
    (recentLogsRes.data ?? []).map((r: any) => `${r.user_id}:${r.promo_id}`)
  );

  // Build per-user activity maps from interactions
  const activityMap = new Map<string, UserActivity>();
  const ensureActivity = (uid: string): UserActivity => {
    if (!activityMap.has(uid)) {
      activityMap.set(uid, {
        searchedBrands: new Set(),
        searchedCats:   new Set(),
        clickedBrands:  new Set(),
        clickedCats:    new Set(),
      });
    }
    return activityMap.get(uid)!;
  };

  for (const row of (interactionsRes.data ?? [])) {
    if (!row.user_id) continue;
    const a = ensureActivity(row.user_id);
    if (row.brand)    a.clickedBrands.add(row.brand.toLowerCase());
    if (row.category) a.clickedCats.add(row.category.toLowerCase());
  }

  // Build a set of all unique candidate brands/categories for fast search matching
  const candidateBrands = new Set(qualified.map(c => c.brand.toLowerCase()));
  const candidateCats   = new Set(qualified.map(c => c.category.toLowerCase()));

  for (const row of (searchesRes.data ?? [])) {
    if (!row.user_id) continue;
    const q = (row.normalized_query || row.query || '').toLowerCase();
    if (!q) continue;
    const a = ensureActivity(row.user_id);
    // Match query against candidate brands (substring in either direction)
    for (const brand of candidateBrands) {
      if (brand.includes(q) || q.includes(brand)) a.searchedBrands.add(brand);
    }
    // Match query against candidate categories
    for (const cat of candidateCats) {
      if (cat.includes(q) || q.includes(cat)) a.searchedCats.add(cat);
    }
  }

  // ── Per-user scoring and send ─────────────────────────────────────────────────
  let accessToken: string | null = null;
  let sent = 0;
  const fcmErrors: string[] = [];

  for (const user of users) {
    const favBrands = new Set(user.favorite_brands.map(b => b.toLowerCase()));
    const favCats   = new Set(user.favorite_categories.map(c => c.toLowerCase()));
    const activity  = activityMap.get(user.user_id);

    const scored = qualified
      .filter(c => !recentSent.has(`${user.user_id}:${c.promo_id}`))
      .map(c => {
        const brand = c.brand.toLowerCase();
        const cat   = c.category.toLowerCase();

        // Determine which signals fire for this candidate
        const isFavBrand      = favBrands.has(brand);
        const isFavCat        = favCats.has(cat);
        const isSearchedBrand = activity?.searchedBrands.has(brand) ?? false;
        const isSearchedCat   = activity?.searchedCats.has(cat)     ?? false;
        const isClickedBrand  = activity?.clickedBrands.has(brand)  ?? false;
        const isClickedCat    = activity?.clickedCats.has(cat)      ?? false;

        const hasAnySignal = isFavBrand || isFavCat || isSearchedBrand ||
                             isSearchedCat || isClickedBrand || isClickedCat;

        let score = c.notify_score;
        if (isFavBrand)      score += FAV_BRAND_BONUS;
        if (isFavCat)        score += FAV_CAT_BONUS;
        if (isSearchedBrand) score += SEARCH_BRAND_BONUS;
        if (isSearchedCat)   score += SEARCH_CAT_BONUS;
        if (isClickedBrand)  score += CLICKED_BRAND_BONUS;
        if (isClickedCat)    score += CLICKED_CAT_BONUS;

        const threshold = hasAnySignal ? PERSONAL_THRESHOLD : UNKNOWN_THRESHOLD;

        // Pick the most specific reason for the notification copy
        const reason = isSearchedBrand ? 'searched_brand'
          : isClickedBrand             ? 'clicked_brand'
          : isFavBrand                 ? 'fav_brand'
          : isSearchedCat              ? 'searched_cat'
          : isClickedCat               ? 'clicked_cat'
          : isFavCat                   ? 'fav_cat'
          : 'none';

        return { c, score, threshold, reason };
      })
      .filter(e => e.score >= e.threshold);

    if (scored.length === 0) continue;

    scored.sort((a, b) => b.score - a.score);
    const { c, reason } = scored[0];

    // Build a notification body that explains why the user is seeing this deal
    const body = (() => {
      switch (reason) {
        case 'searched_brand':
          return `${c.notification_body} — you searched for ${c.brand}`;
        case 'clicked_brand':
          return `${c.notification_body} — based on your recent browsing`;
        case 'fav_brand':
          return `${c.notification_body} — from a brand you love`;
        case 'searched_cat':
          return `${c.notification_body} — matches your recent search`;
        case 'clicked_cat':
          return `${c.notification_body} — in a category you've been browsing`;
        case 'fav_cat':
          return `${c.notification_body} — in ${c.category}`;
        default:
          return c.notification_body;
      }
    })();

    if (!accessToken) {
      accessToken = await getAccessToken(sa);
    }

    const result = await sendFcm(
      accessToken,
      sa.project_id,
      user.token,
      c.notification_title,
      body,
      c.promo_id,
    );
    if (result.ok) {
      sent++;
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
