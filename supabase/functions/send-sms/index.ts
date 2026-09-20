import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function normalizePhilippinePhone(value: string): string | null {
  let digits = value.replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = `63${digits.slice(1)}`;
  if (digits.startsWith('9') && digits.length === 10) digits = `63${digits}`;
  return /^639\d{9}$/.test(digits) ? `+${digits}` : null;
}

serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return new Response('Unauthorized', { status: 401, headers: corsHeaders });

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return new Response('Unauthorized', { status: 401, headers: corsHeaders });

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('role, disabled')
      .eq('id', user.id)
      .single();
    if (profileError || profile?.disabled || !['owner', 'superadmin'].includes(profile?.role)) {
      return new Response('Forbidden', { status: 403, headers: corsHeaders });
    }

    const payload = await request.json();
    const recipient = normalizePhilippinePhone(String(payload.to ?? ''));
    const message = String(payload.message ?? '').trim();
    if (!recipient || !message || message.length > 918) {
      return new Response('Valid Philippine recipient and message required', { status: 400, headers: corsHeaders });
    }

    const apiKey = Deno.env.get('UNISMS_API_KEY');
    if (!apiKey) return new Response('SMS provider is not configured', { status: 503, headers: corsHeaders });

    const providerResponse = await fetch('https://unismsapi.com/api/sms', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${btoa(`${apiKey}:`)}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ sender: 'Neithans', recipient, content: message }),
    });
    if (!providerResponse.ok) return new Response('SMS provider rejected the request', { status: 502, headers: corsHeaders });

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('send-sms failed', error);
    return new Response('Internal server error', { status: 500, headers: corsHeaders });
  }
});
