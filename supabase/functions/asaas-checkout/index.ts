import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// Gera as cobranças da família no Asaas depois que ela assina e escolhe a
// forma de pagamento. Uma cobrança por vencimento cobre a parcela de todos os
// irmãos (o webhook baixa todas as parcelas ligadas àquela cobrança).
// Cartão parcelado vira uma cobrança parcelada do Asaas (installmentCount),
// para o cartão ser cobrado em parcelas. Idempotente: só cria cobrança para
// parcela que ainda não tem provider_charge_id.
//
// Segredos: ASAAS_API_KEY e, opcionalmente, ASAAS_BASE_URL
// (padrão produção; sandbox: https://api-sandbox.asaas.com/v3).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" } });
}

const BILLING_TYPE: Record<string, string> = { boleto: "BOLETO", pix: "PIX", cartao: "CREDIT_CARD" };

type Installment = { id: string; enrollment_id: string; amount_cents: number; due_date: string; method: string | null };

class AsaasError extends Error {}

function asaasClient(baseUrl: string, apiKey: string) {
  return async function call(path: string, init: RequestInit = {}) {
    const response = await fetch(`${baseUrl}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json", "User-Agent": "cec-matriculas", access_token: apiKey, ...(init.headers || {}) },
    });
    const body = await response.json().catch(() => null);
    if (!response.ok) {
      const detail = body?.errors?.map((item: { description?: string }) => item.description).filter(Boolean).join("; ");
      throw new AsaasError(detail || `Asaas respondeu ${response.status}`);
    }
    return body;
  };
}

// "Rua A, 120, Apto 2 - Centro, Nanuque/MG, CEP 39860-000" (AddressFields)
function splitAddress(value: string | null) {
  const match = String(value || "").match(/^(.+?), ([^,]+?)(?:, (.+?))? - (.+?), (.+?)\/([A-Z]{2}), CEP (\d{5}-?\d{3})$/);
  if (!match) return value ? { address: value } : {};
  const [, street, number, complement, district, , , cep] = match;
  return { address: street, addressNumber: number, complement: complement || undefined, province: district, postalCode: cep.replace(/\D/g, "") };
}

function localToday() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Método não suportado" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("ASAAS_API_KEY");
  const baseUrl = (Deno.env.get("ASAAS_BASE_URL") || "https://api.asaas.com/v3").replace(/\/$/, "");
  if (!supabaseUrl || !serviceRole) return json({ error: "Configuração interna ausente" }, 500);
  if (!apiKey) {
    return json({ error: "O pagamento online ainda não foi ativado pela escola. Avisaremos por aqui e pelo WhatsApp.", code: "asaas_not_configured" }, 503);
  }

  const supabase = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });
  const asaas = asaasClient(baseUrl, apiKey);

  try {
    const { token } = await request.json();
    if (typeof token !== "string" || token.length < 20) return json({ error: "Jornada inválida" }, 404);

    const { data: session, error: sessionError } = await supabase
      .from("enrollment_onboarding_sessions")
      .select("id, guardian_id, status")
      .eq("token", token.trim())
      .neq("status", "cancelada")
      .maybeSingle();
    if (sessionError) throw sessionError;
    if (!session?.guardian_id) return json({ error: "Jornada inválida ou expirada" }, 404);

    const { data: stage } = await supabase.rpc("onboarding_stage", { p_session_id: session.id });
    if (stage !== "pagamento" && stage !== "concluida") return json({ error: "Escolha a forma de pagamento antes de gerar a cobrança" }, 409);

    const { data: items, error: itemsError } = await supabase
      .from("enrollment_onboarding_items")
      .select("enrollment_id, enrollments!inner(students!inner(full_name))")
      .eq("onboarding_session_id", session.id);
    if (itemsError) throw itemsError;
    const enrollmentIds = (items || []).map((item) => item.enrollment_id);
    const names = (items || []).map((item) => {
      const enrollment = item.enrollments as unknown as { students?: { full_name?: string } };
      return String(enrollment?.students?.full_name || "").split(" ")[0];
    }).filter(Boolean);

    const { data: pending, error: pendingError } = await supabase
      .from("installments")
      .select("id, enrollment_id, amount_cents, due_date, method")
      .in("enrollment_id", enrollmentIds)
      .eq("status", "pendente")
      .is("provider_charge_id", null)
      .order("due_date");
    if (pendingError) throw pendingError;

    if ((pending || []).length) {
      const { data: guardian, error: guardianError } = await supabase
        .from("guardians")
        .select("id, full_name, cpf, email, phone, address, asaas_customer_id")
        .eq("id", session.guardian_id)
        .single();
      if (guardianError) throw guardianError;
      if (!guardian.cpf) return json({ error: "O CPF do responsável é necessário para gerar a cobrança" }, 422);

      let customerId = guardian.asaas_customer_id as string | null;
      if (!customerId) {
        const found = await asaas(`/customers?cpfCnpj=${guardian.cpf}`);
        customerId = found?.data?.[0]?.id || null;
      }
      if (!customerId) {
        const phone = String(guardian.phone || "").replace(/\D/g, "").replace(/^55/, "");
        const created = await asaas("/customers", {
          method: "POST",
          body: JSON.stringify({
            name: guardian.full_name,
            cpfCnpj: guardian.cpf,
            email: guardian.email || undefined,
            mobilePhone: phone || undefined,
            externalReference: guardian.id,
            ...splitAddress(guardian.address),
          }),
        });
        customerId = created.id;
      }
      if (customerId !== guardian.asaas_customer_id) {
        await supabase.from("guardians").update({ asaas_customer_id: customerId }).eq("id", guardian.id);
      }

      // Uma cobrança por vencimento, somando os irmãos.
      const groups = new Map<string, Installment[]>();
      for (const row of pending as Installment[]) groups.set(row.due_date, [...(groups.get(row.due_date) || []), row]);
      const dueDates = [...groups.keys()].sort();
      const method = (pending as Installment[])[0].method || "boleto";
      const billingType = BILLING_TYPE[method] || "BOLETO";
      const today = localToday();
      const description = (index: number) =>
        `CEC Matrícula 2027 — parcela ${index + 1}/${dueDates.length}${names.length ? ` — ${names.join(", ")}` : ""}`;
      const reais = (cents: number) => Math.round(cents) / 100;
      const save = async (dueDate: string, payment: { id: string; invoiceUrl?: string }) => {
        const ids = groups.get(dueDate)!.map((row) => row.id);
        const { error } = await supabase.from("installments")
          .update({ provider: "asaas", provider_charge_id: payment.id, payment_url: payment.invoiceUrl || null })
          .in("id", ids);
        if (error) throw error;
      };

      if (billingType === "CREDIT_CARD" && dueDates.length > 1) {
        const total = dueDates.reduce((sum, due) => sum + groups.get(due)!.reduce((acc, row) => acc + row.amount_cents, 0), 0);
        const first = await asaas("/payments", {
          method: "POST",
          body: JSON.stringify({
            customer: customerId, billingType, installmentCount: dueDates.length, totalValue: reais(total),
            dueDate: dueDates[0] < today ? today : dueDates[0],
            description: `CEC Matrícula 2027 — ${dueDates.length}x no cartão${names.length ? ` — ${names.join(", ")}` : ""}`,
            externalReference: session.id,
          }),
        });
        const list = first.installment ? await asaas(`/payments?installment=${first.installment}&limit=20`) : { data: [first] };
        const payments = [...(list?.data || [])].sort((a, b) => String(a.dueDate).localeCompare(String(b.dueDate)));
        for (let index = 0; index < dueDates.length; index += 1) {
          const payment = payments[index] || first;
          await save(dueDates[index], { id: payment.id, invoiceUrl: payment.invoiceUrl || first.invoiceUrl });
        }
      } else {
        for (let index = 0; index < dueDates.length; index += 1) {
          const due = dueDates[index];
          const value = groups.get(due)!.reduce((acc, row) => acc + row.amount_cents, 0);
          const payment = await asaas("/payments", {
            method: "POST",
            body: JSON.stringify({
              customer: customerId, billingType, value: reais(value),
              dueDate: due < today ? today : due,
              description: description(index),
              externalReference: session.id,
            }),
          });
          await save(due, payment);
        }
      }

      for (const enrollmentId of enrollmentIds) {
        await supabase.from("enrollment_events").insert({
          enrollment_id: enrollmentId, code: "PAYMENT_CHECKOUT_CREATED", title: "Cobrança gerada no Asaas",
          body: `Cobrança ${method} gerada para a família.`, actor: "sistema", metadata: { method, due_dates: dueDates },
        });
      }
    }

    const { data: charges, error: chargesError } = await supabase.rpc("onboarding_charges", { p_session_id: session.id });
    if (chargesError) throw chargesError;
    return json({ ok: true, charges });
  } catch (error) {
    console.error(error);
    if (error instanceof AsaasError) return json({ error: `O Asaas recusou a cobrança: ${error.message}` }, 502);
    return json({ error: "Não foi possível gerar a cobrança agora. Tente novamente em instantes." }, 500);
  }
});
