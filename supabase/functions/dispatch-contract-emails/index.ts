import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { LOGO_CONTENT_ID, LOGO_JPEG_BASE64 } from "./logo.ts";
import { renderContractCodeEmail } from "./templates.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function errorMessage(value: unknown) {
  if (typeof value === "string") return value.slice(0, 1000);
  if (value && typeof value === "object" && "message" in value && typeof value.message === "string") return value.message.slice(0, 1000);
  return "Falha desconhecida do provedor de e-mail";
}

type QueueItem = { recipient: string; subject: string; html_body: string; template: string | null; template_data: Record<string, unknown> | null };

// Itens com template conhecido ganham o layout da marca com a logo inline;
// os demais seguem com o html_body gravado pelo banco.
function buildMessage(from: string, item: QueueItem) {
  const base = { from, to: [item.recipient], subject: item.subject };
  if (item.template === "contract_code" && typeof item.template_data?.code === "string") {
    const { html, text } = renderContractCodeEmail(item.template_data as { code: string; expires_minutes?: number });
    return {
      ...base,
      html,
      text,
      attachments: [{ filename: "logo-cec-matriculas.jpg", content: LOGO_JPEG_BASE64, content_id: LOGO_CONTENT_ID }],
    };
  }
  return { ...base, html: item.html_body };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Método não suportado" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const emailFrom = Deno.env.get("EMAIL_FROM");
  if (!supabaseUrl || !serviceRole || !resendKey || !emailFrom) {
    return json({ error: "O envio de e-mail ainda não foi configurado pela escola." }, 503);
  }

  try {
    const { token } = await request.json();
    if (typeof token !== "string" || token.length < 20) return json({ error: "Link de contrato inválido" }, 404);

    // O token individual do contrato só permite despachar a própria fila e já
    // é limitado pelo banco a um novo código por minuto. Não há segredo exposto
    // no navegador nem acesso à fila de outras famílias.
    const supabase = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });
    const { data: session, error: sessionError } = await supabase
      .from("contract_sessions")
      .select("id")
      .eq("token", token.trim())
      .not("status", "in", "(assinada,cancelada,expirada)")
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (sessionError) throw sessionError;
    if (!session) return json({ error: "Link de contrato inválido ou expirado" }, 404);

    const { data: item, error: queueError } = await supabase
      .from("email_queue")
      .select("id, recipient, subject, html_body, template, template_data, attempts")
      .eq("contract_session_id", session.id)
      .eq("status", "pendente")
      .lte("scheduled_for", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (queueError) throw queueError;
    if (!item) return json({ ok: true, status: "sem_email_pendente" });

    const { data: claimed, error: claimError } = await supabase
      .from("email_queue")
      .update({ status: "processando", attempts: item.attempts + 1, last_error: null })
      .eq("id", item.id)
      .eq("status", "pendente")
      .select("id")
      .maybeSingle();
    if (claimError) throw claimError;
    if (!claimed) return json({ ok: true, status: "em_processamento" }, 202);

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(buildMessage(emailFrom, item)),
    });
    const resendBody = await resendResponse.json().catch(() => null);
    if (!resendResponse.ok) {
      const detail = errorMessage(resendBody);
      await supabase.from("email_queue").update({ status: "falhou", provider: "resend", last_error: detail }).eq("id", item.id);
      return json({ error: "O provedor recusou o envio. A escola deve conferir o remetente configurado." }, 502);
    }

    const { error: sentError } = await supabase.from("email_queue").update({
      status: "enviado",
      provider: "resend",
      provider_message_id: typeof resendBody?.id === "string" ? resendBody.id : null,
      sent_at: new Date().toISOString(),
      last_error: null,
    }).eq("id", item.id);
    if (sentError) throw sentError;
    return json({ ok: true, status: "enviado" });
  } catch (error) {
    console.error(error);
    return json({ error: "Não foi possível processar o e-mail de confirmação." }, 500);
  }
});
