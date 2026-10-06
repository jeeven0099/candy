import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type VaultBody = {
  access_token?: string;
  refresh_token?: string;
  token_type?: string;
  google_subject?: string;
  scopes?: string[] | string;
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function normalizeScopes(scopes: string[] | string | undefined): string[] {
  if (Array.isArray(scopes)) return scopes.filter(Boolean);
  if (typeof scopes === 'string') {
    return scopes.split(/[,\s]+/).map((s) => s.trim()).filter(Boolean);
  }
  return [];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method_not_allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) {
    return jsonResponse({ error: 'missing_authorization' }, 401);
  }

  let body: VaultBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  const accessToken = body.access_token?.trim() || null;
  let refreshToken = body.refresh_token?.trim() || null;
  if (!accessToken) {
    return jsonResponse({ error: 'missing_provider_token' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: 'missing_supabase_secret' }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: 'invalid_user' }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: profile, error: profileError } = await admin
    .from('users')
    .select('id, email')
    .eq('auth_id', userData.user.id)
    .maybeSingle();

  if (profileError) {
    return jsonResponse({ error: profileError.message }, 500);
  }
  if (!profile?.id) {
    return jsonResponse({ error: 'missing_user_row' }, 404);
  }

  let googleEmail: string;
  try {
    const mailboxResponse = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(15000),
    });
    if (!mailboxResponse.ok) return jsonResponse({ error: 'gmail_access_not_granted' }, 400);
    const mailbox = await mailboxResponse.json();
    googleEmail = typeof mailbox.emailAddress === 'string' ? mailbox.emailAddress.toLowerCase() : '';
    if (!googleEmail) return jsonResponse({ error: 'missing_gmail_address' }, 400);
  } catch {
    return jsonResponse({ error: 'gmail_verification_failed' }, 502);
  }

  if (!refreshToken) {
    const { data: connection } = await admin.from('gmail_connections')
      .select('google_email').eq('user_id', profile.id).maybeSingle();
    const { data: existing } = await admin
      .from('gmail_connection_tokens')
      .select('refresh_token')
      .eq('user_id', profile.id)
      .maybeSingle();
    refreshToken = connection?.google_email?.toLowerCase() === googleEmail.toLowerCase()
      ? existing?.refresh_token ?? null : null;
  }

  const scopes = normalizeScopes(body.scopes);
  const expiresAt = new Date(Date.now() + 55 * 60 * 1000).toISOString();

  const { error: tokenError } = await admin.from('gmail_connection_tokens').upsert({
    user_id: profile.id,
    access_token: accessToken,
    refresh_token: refreshToken,
    access_token_expires_at: expiresAt,
    token_type: body.token_type ?? 'Bearer',
    updated_at: new Date().toISOString(),
  }, { onConflict: 'user_id' });

  if (tokenError) {
    return jsonResponse({ error: tokenError.message }, 500);
  }

  const { error: connError } = await admin.from('gmail_connections').upsert({
    user_id: profile.id,
    google_email: googleEmail,
    google_subject: body.google_subject ?? null,
    scopes,
    status: 'connected',
    connected_at: new Date().toISOString(),
    disconnected_at: null,
    sync_error: null,
    updated_at: new Date().toISOString(),
  }, { onConflict: 'user_id' });

  if (connError) return jsonResponse({ error: connError.message }, 500);

  return jsonResponse({
    ok: true,
    user_id: profile.id,
    google_email: googleEmail,
    has_refresh_token: Boolean(refreshToken),
  });
});
