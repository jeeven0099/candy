import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
type VaultBody = {
    request_id?: string;
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
    if (Array.isArray(scopes))
        return scopes.filter((scope) => typeof scope === 'string' && Boolean(scope));
    if (typeof scopes === 'string') {
        return scopes.split(/[,\s]+/).map((s) => s.trim()).filter(Boolean);
    }
    return [];
}
Deno.serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }
    let requestId: string = crypto.randomUUID();
    let stage = 'request';
    const secrets: string[] = [];
    function safe(value: string): string {
        for (const secret of secrets) {
            if (secret)
                value = value.split(secret).join('[redacted]');
        }
        return value
            .replace(/https?:\/\/[^\s<>]+/gi, '[URL redacted]')
            .replace(/Bearer\s+[^\s,;]+/gi, 'Bearer [redacted]')
            .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[JWT redacted]')
            .replace(/\b(?:ya29\.|1\/\/)[A-Za-z0-9._/-]+/g, '[Google token redacted]')
            .slice(0, 1500);
    }
    function mark(nextStage: string): void {
        stage = nextStage;
        console.info(JSON.stringify({ event: 'gmail_connection_stage', request_id: requestId, stage }));
    }
    function fail(error: string, status: number, details: Record<string, string | number> = {}): Response {
        const sanitized = Object.fromEntries(Object.entries(details)
            .map(([key, value]) => [key, typeof value === 'string' ? safe(value) : value]));
        const body = { error, stage, request_id: requestId, ...sanitized };
        console.error(JSON.stringify({ event: 'gmail_connection_failed', status, ...body }));
        return jsonResponse(body, status);
    }
    try {
        if (req.method !== 'POST')
            return fail('method_not_allowed', 405);
        const authHeader = req.headers.get('Authorization') ?? '';
        secrets.push(authHeader, authHeader.replace(/^Bearer\s+/i, ''));
        if (!authHeader) {
            return fail('missing_authorization', 401);
        }
        let body: VaultBody;
        try {
            body = await req.json();
            if (!body || typeof body !== 'object' || Array.isArray(body)) {
                return fail('invalid_json', 400);
            }
        }
        catch {
            return fail('invalid_json', 400);
        }
        if (typeof body.request_id === 'string' && /^[A-Za-z0-9-]{8,80}$/.test(body.request_id)) {
            requestId = body.request_id;
        }
        mark('validate_tokens');
        const accessToken = typeof body.access_token === 'string' ? body.access_token.trim() : '';
        let refreshToken = typeof body.refresh_token === 'string' ? body.refresh_token.trim() || null : null;
        secrets.push(accessToken, refreshToken ?? '');
        if (!accessToken) {
            return fail('missing_provider_token', 400);
        }
        const supabaseUrl = Deno.env.get('SUPABASE_URL');
        const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
        const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
        secrets.push(anonKey ?? '', serviceRoleKey ?? '');
        if (!supabaseUrl || !anonKey || !serviceRoleKey) {
            return fail('missing_supabase_secret', 500);
        }
        mark('authenticate');
        const userClient = createClient(supabaseUrl, anonKey, {
            global: { headers: { Authorization: authHeader } },
        });
        const { data: userData, error: userError } = await userClient.auth.getUser();
        if (userError || !userData.user) {
            return fail('invalid_user', 401, { error_description: userError?.message ?? 'No signed-in Candy user' });
        }
        const admin = createClient(supabaseUrl, serviceRoleKey);
        mark('load_user');
        const { data: profile, error: profileError } = await admin
            .from('users')
            .select('id, email')
            .eq('auth_id', userData.user.id)
            .maybeSingle();
        if (profileError) {
            return fail('profile_lookup_failed', 500, { code: profileError.code, error_description: profileError.message });
        }
        if (!profile?.id) {
            return fail('missing_user_row', 404);
        }
        let googleEmail: string;
        mark('gmail_profile');
        try {
            const mailboxResponse = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
                headers: { Authorization: `Bearer ${accessToken}` },
                signal: AbortSignal.timeout(15000),
            });
            const mailbox = await mailboxResponse.json();
            if (!mailboxResponse.ok) {
                const googleError = mailbox?.error;
                const reasons = Array.isArray(googleError?.errors) ? googleError.errors : [];
                const reason = reasons.find((item: {
                    reason?: unknown;
                } | null) => typeof item?.reason === 'string')?.reason;
                return fail('gmail_access_not_granted', 400, {
                    provider_status: mailboxResponse.status,
                    provider_reason: typeof reason === 'string' ? reason : 'unknown',
                    error_description: typeof googleError?.message === 'string' ? googleError.message : 'Google rejected Gmail access',
                });
            }
            googleEmail = typeof mailbox.emailAddress === 'string' ? mailbox.emailAddress.toLowerCase() : '';
            if (!googleEmail)
                return fail('missing_gmail_address', 400);
        }
        catch (error) {
            return fail('gmail_verification_failed', 502, {
                error_description: error instanceof Error ? error.message : 'Unable to verify Gmail access',
            });
        }
        if (!refreshToken) {
            mark('read_refresh_token');
            const { data: connection, error: connectionError } = await admin.from('gmail_connections')
                .select('google_email').eq('user_id', profile.id).maybeSingle();
            if (connectionError)
                return fail('connection_lookup_failed', 500, {
                    code: connectionError.code, error_description: connectionError.message,
                });
            const { data: existing, error: existingError } = await admin
                .from('gmail_connection_tokens')
                .select('refresh_token')
                .eq('user_id', profile.id)
                .maybeSingle();
            if (existingError)
                return fail('token_lookup_failed', 500, {
                    code: existingError.code, error_description: existingError.message,
                });
            refreshToken = connection?.google_email?.toLowerCase() === googleEmail.toLowerCase()
                ? existing?.refresh_token ?? null : null;
            secrets.push(refreshToken ?? '');
        }
        const scopes = normalizeScopes(body.scopes);
        const expiresAt = new Date(Date.now() + 55 * 60 * 1000).toISOString();
        mark('save_tokens');
        const { error: tokenError } = await admin.from('gmail_connection_tokens').upsert({
            user_id: profile.id,
            access_token: accessToken,
            refresh_token: refreshToken,
            access_token_expires_at: expiresAt,
            token_type: body.token_type ?? 'Bearer',
            updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id' });
        if (tokenError) {
            return fail('token_storage_failed', 500, { code: tokenError.code, error_description: tokenError.message });
        }
        mark('save_connection');
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
        if (connError)
            return fail('connection_storage_failed', 500, { code: connError.code, error_description: connError.message });
        mark('connected');
        return jsonResponse({
            ok: true,
            request_id: requestId,
            user_id: profile.id,
            google_email: googleEmail,
            has_refresh_token: Boolean(refreshToken),
        });
    }
    catch (error) {
        return fail('unexpected_error', 500, {
            error_description: error instanceof Error ? error.message : 'Unexpected Gmail connection failure',
        });
    }
});
