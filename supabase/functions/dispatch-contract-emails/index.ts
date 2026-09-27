import { createClient } from 'npm:@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const resendApiKey = Deno.env.get('RESEND_API_KEY');
const emailFrom = Deno.env.get('EMAIL_FROM');
const dispatchSecret = Deno.env.get('CONTRACT_EMAIL_DISPATCH_SECRET');

Deno.serve(async (request) => {
  if (!dispatchSecret || request.headers.get('x-dispatch-secret') !== dispatchSecret) {
    return new Response('Unauthorized', { status: 401 });
  }
  if (!resendApiKey || !emailFrom) {
    return Response.json({ error: 'RESEND_API_KEY e EMAIL_FROM são obrigatórios.' }, { status: 500 });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { data: pending, error } = await supabase
    .from('email_queue')
    .select('id,recipient,subject,html_body,attempts')
    .eq('status', 'pendente')
    .lte('scheduled_for', new Date().toISOString())
    .order('created_at', { ascending: true })
    .limit(20);
  if (error) return Response.json({ error: error.message }, { status: 500 });

  let sent = 0;
  let failed = 0;
  for (const email of pending || []) {
    const { error: claimError } = await supabase
      .from('email_queue')
      .update({ status: 'processando', attempts: email.attempts + 1 })
      .eq('id', email.id)
      .eq('status', 'pendente');
    if (claimError) continue;

    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: emailFrom, to: [email.recipient], subject: email.subject, html: email.html_body })
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok) throw new Error(payload?.message || `Provedor respondeu ${response.status}`);
      await supabase.from('email_queue').update({
        status: 'enviado', provider: 'resend', provider_message_id: payload?.id || null, sent_at: new Date().toISOString(), last_error: null
      }).eq('id', email.id);
      sent += 1;
    } catch (sendError) {
      await supabase.from('email_queue').update({
        status: 'falhou', last_error: sendError instanceof Error ? sendError.message : 'Falha desconhecida ao enviar e-mail'
      }).eq('id', email.id);
      failed += 1;
    }
  }
  return Response.json({ sent, failed });
});
