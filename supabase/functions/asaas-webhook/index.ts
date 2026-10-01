import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

type AsaasPayment = {
  id?: unknown;
  value?: unknown;
};

type AsaasEvent = {
  id?: unknown;
  event?: unknown;
  payment?: AsaasPayment;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function tokenMatches(received: string | null, expected: string) {
  if (!received || received.length !== expected.length) return false;

  // Compara todos os caracteres antes de decidir, reduzindo informação útil
  // para tentativas de descobrir o token por tempo de resposta.
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= received.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return difference === 0;
}

function paymentStatusFor(eventName: string) {
  switch (eventName) {
    case "PAYMENT_RECEIVED":
    case "PAYMENT_CONFIRMED":
      return "pago";
    case "PAYMENT_OVERDUE":
      return "vencido";
    case "PAYMENT_REFUNDED":
    case "PAYMENT_RECEIVED_IN_CASH_UNDONE":
      return "estornado";
    case "PAYMENT_DELETED":
      return "cancelado";
    default:
      return null;
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Método não suportado" }, 405);

  const webhookToken = Deno.env.get("ASAAS_WEBHOOK_AUTH_TOKEN");
  if (!webhookToken || !tokenMatches(request.headers.get("asaas-access-token"), webhookToken)) {
    return json({ error: "Não autorizado" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRole) {
    console.error("Configuração do Supabase indisponível para o webhook Asaas.");
    return json({ error: "Integração indisponível" }, 503);
  }

  let payload: AsaasEvent;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "JSON inválido" }, 400);
  }

  const eventName = typeof payload.event === "string" ? payload.event : "";
  const paymentId = typeof payload.payment?.id === "string" ? payload.payment.id : "";
  if (!eventName || !paymentId) return json({ error: "Evento de pagamento inválido" }, 400);

  // O Asaas reenvia eventos no modelo "at least once". Quando disponível,
  // o id do evento é a chave de idempotência; o fallback mantém compatibilidade
  // com cargas antigas que não o incluam.
  const eventId = typeof payload.id === "string" ? payload.id : `${eventName}:${paymentId}`;
  const externalId = `asaas:${eventId}`;
  const supabase = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });

  try {
    const { data: alreadyReceived, error: duplicateError } = await supabase
      .from("webhook_events")
      .select("id")
      .eq("source", "pagamento")
      .eq("external_id", externalId)
      .maybeSingle();
    if (duplicateError) throw duplicateError;
    if (alreadyReceived) return json({ ok: true, status: "duplicado" });

    const { data: webhookEvent, error: insertError } = await supabase
      .from("webhook_events")
      .insert({
        source: "pagamento",
        event_type: `asaas.${eventName}`,
        external_id: externalId,
        payload,
        status: "recebido",
        attempts: 1,
      })
      .select("id")
      .single();
    if (insertError) {
      // A restrição única também protege contra duas entregas simultâneas.
      if (insertError.code === "23505") return json({ ok: true, status: "duplicado" });
      throw insertError;
    }

    // Uma cobrança do Asaas pode cobrir a parcela de vários irmãos (mesmo
    // vencimento). Todas as parcelas ligadas a ela mudam juntas.
    const { data: installments, error: installmentError } = await supabase
      .from("installments")
      .select("id, status, amount_cents")
      .eq("provider", "asaas")
      .eq("provider_charge_id", paymentId);
    if (installmentError) throw installmentError;

    const targetStatus = paymentStatusFor(eventName);
    let outcome = "registrado";

    if (!installments?.length) {
      outcome = "cobranca_nao_localizada";
    } else if (targetStatus) {
      let applied = 0;
      for (const installment of installments) {
        // Um atraso recebido tardiamente não pode desfazer uma baixa já confirmada.
        if (targetStatus === "vencido" && installment.status !== "pendente") continue;
        const update: Record<string, unknown> = { status: targetStatus };
        if (targetStatus === "pago") {
          update.paid_amount_cents = installment.amount_cents;
          update.paid_at = new Date().toISOString();
        }
        const { error: updateError } = await supabase.from("installments").update(update).eq("id", installment.id);
        if (updateError) throw updateError;
        applied += 1;
      }
      outcome = applied ? "parcela_atualizada" : "evento_obsoleto";
    }

    const { error: processedError } = await supabase
      .from("webhook_events")
      .update({ status: "processado", processed_at: new Date().toISOString(), last_error: null })
      .eq("id", webhookEvent.id);
    if (processedError) throw processedError;

    return json({ ok: true, status: outcome });
  } catch (error) {
    console.error("Falha no webhook Asaas", error);
    return json({ error: "Não foi possível processar o evento de pagamento" }, 500);
  }
});
