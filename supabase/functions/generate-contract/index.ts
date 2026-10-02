import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function decodeBase64(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

async function sha256(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function formatCpf(value: string | null) {
  const digits = String(value || "").replace(/\D/g, "");
  return digits.length === 11 ? digits.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4") : String(value || "");
}

function formatPhone(value: string | null) {
  const digits = String(value || "").replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "");
  if (digits.length === 11) return digits.replace(/(\d{2})(\d{5})(\d{4})/, "($1) $2-$3");
  if (digits.length === 10) return digits.replace(/(\d{2})(\d{4})(\d{4})/, "($1) $2-$3");
  return String(value || "");
}

function shiftLabel(shift: string | null) {
  return ({ manha: "Matutino", tarde: "Vespertino", integral: "Integral" } as Record<string, string>)[shift || ""] || "";
}

function drawField(page: ReturnType<PDFDocument["getPages"]>[number], font: Awaited<ReturnType<PDFDocument["embedFont"]>>, value: string, x: number, y: number, maxWidth: number) {
  const content = value.trim();
  if (!content) return;
  let size = 8.2;
  while (size > 5.8 && font.widthOfTextAtSize(content, size) > maxWidth) size -= 0.35;
  const clipped = font.widthOfTextAtSize(content, size) > maxWidth
    ? `${content.slice(0, Math.max(0, Math.floor(content.length * maxWidth / font.widthOfTextAtSize(content, size)) - 1))}…`
    : content;
  page.drawText(clipped, { x, y, size, font, color: rgb(0.06, 0.12, 0.25), maxWidth });
}

// Texto que pode não caber numa linha (endereço, plano): até duas linhas
// menores dentro da mesma célula; a última é reduzida/cortada se precisar.
function drawWrapped(page: ReturnType<PDFDocument["getPages"]>[number], font: Awaited<ReturnType<PDFDocument["embedFont"]>>, value: string, x: number, y: number, maxWidth: number) {
  const content = value.trim();
  if (!content) return;
  if (font.widthOfTextAtSize(content, 8.2) <= maxWidth) return drawField(page, font, content, x, y, maxWidth);
  const size = 7;
  const words = content.split(/\s+/);
  let first = "";
  while (words.length && font.widthOfTextAtSize(`${first} ${words[0]}`.trim(), size) <= maxWidth) first = `${first} ${words.shift()}`.trim();
  page.drawText(first, { x, y: y + 2, size, font, color: rgb(0.06, 0.12, 0.25) });
  drawField(page, font, words.join(" "), x, y - 6.2, maxWidth);
}

function money(cents: number) {
  return (cents / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

function shortDate(value: string) {
  const [, month, day] = value.split("-");
  return `${day}/${month}`;
}

// Plano da 1ª parcela/matrícula pelas parcelas já montadas na jornada.
function planLabel(rows: Array<{ amount_cents: number; due_date: string }>) {
  if (!rows.length) return "";
  if (rows.length === 1) return `À vista: ${money(rows[0].amount_cents)} em ${shortDate(rows[0].due_date)}`;
  const dates = rows.map((row) => shortDate(row.due_date));
  const equal = rows.every((row) => row.amount_cents === rows[rows.length - 1].amount_cents);
  const value = equal ? `${rows.length}x de ${money(rows[0].amount_cents)}` : `${rows.length}x (${rows.map((row) => money(row.amount_cents)).join(" + ")})`;
  return `${value}: ${dates.slice(0, -1).join(", ")} e ${dates.at(-1)}`;
}

// Modelo 2027 (Carta, 2 páginas): quadro no topo da página 1, data e
// assinatura no fim da página 2. Modelo 2025 (A4, 6 páginas): mantido para
// rascunhos gerados antes da troca, que ainda podem ser assinados.
function isTemplate2027(page: ReturnType<PDFDocument["getPages"]>[number]) {
  return Math.round(page.getHeight()) === 792;
}

const MONTHS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];

function contractFilePath(sessionId: string, enrollmentId: string) {
  return `contracts/${sessionId}/${enrollmentId}.pdf`;
}

function signedContractFilePath(sessionId: string, enrollmentId: string) {
  return `contracts/${sessionId}/${enrollmentId}/assinado.pdf`;
}

function decodeSignature(value: string) {
  const match = value.match(/^data:image\/(png|jpeg);base64,(.+)$/);
  if (!match) throw new Error("Assinatura desenhada inválida");
  return { type: match[1], bytes: decodeBase64(match[2]) };
}

function signedDate() {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo" }).format(new Date());
}

async function applySignature(pdfBytes: Uint8Array, signatureData: string) {
  const pdf = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
  const page = pdf.getPages().at(-1);
  if (!page) throw new Error("Página de assinatura não encontrada");
  const signature = decodeSignature(signatureData);
  const image = signature.type === "png" ? await pdf.embedPng(signature.bytes) : await pdf.embedJpg(signature.bytes);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const modern = isTemplate2027(page);
  // Área da assinatura: sobre a linha do CONTRATANTE.
  const box = modern ? { x: 216, y: 158, width: 180, height: 21 } : { x: 212, y: 379, width: 172, height: 58 };
  const scale = Math.min(box.width / image.width, box.height / image.height);
  const width = image.width * scale;
  const height = image.height * scale;
  page.drawImage(image, { x: box.x + (box.width - width) / 2, y: box.y + (box.height - height) / 2, width, height });

  const [day, month, year] = signedDate().split("/");
  if (modern) {
    // "Nanuque/MG, ______ de ______________ de 20____."
    const centered = (text: string, start: number, end: number) => {
      const textWidth = font.widthOfTextAtSize(text, 9);
      page.drawText(text, { x: start + (end - start - textWidth) / 2, y: 185, size: 9, font, color: rgb(0.06, 0.12, 0.25) });
    };
    centered(day, 224, 254);
    centered(MONTHS[Number(month) - 1], 269, 399);
    centered(year.slice(2), 425, 444);
  } else {
    // O modelo 2025 traz "____/____/____": dia, mês e ano centralizados em
    // cada espaço, sem escrever por cima das barras.
    const blanks = [[436, 461], [465.5, 491], [495.5, 520.5]];
    [day, month, year].forEach((part, index) => {
      const [start, end] = blanks[index];
      const partWidth = font.widthOfTextAtSize(part, 8.2);
      drawField(page, font, part, start + (end - start - partWidth) / 2, 463, end - start);
    });
  }
  return pdf.save();
}

async function getSession(supabase: SupabaseClient, token: string) {
  const { data, error } = await supabase
    .from("contract_sessions")
    .select("id, guardian_id, campaign_id, status, expires_at")
    .eq("token", token)
    .not("status", "in", "(cancelada,expirada)")
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function servePdf(supabase: SupabaseClient, token: string, enrollmentId: string, download = false) {
  const session = await getSession(supabase, token);
  if (!session) return json({ error: "Contrato indisponível" }, 404);
  const { data: acceptance, error } = await supabase
    .from("document_acceptances")
    .select("generated_storage_path, signed_storage_path")
    .eq("contract_session_id", session.id)
    .eq("enrollment_id", enrollmentId)
    .not("generated_storage_path", "is", null)
    // Troca de modelo: a sessão pode ter o aceite antigo e o novo; vale o último.
    .order("generated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  const path = acceptance?.signed_storage_path || acceptance?.generated_storage_path;
  if (!path) return json({ error: "PDF individual ainda não foi gerado" }, 404);
  const { data: file, error: downloadError } = await supabase.storage.from("contract-files").download(path);
  if (downloadError || !file) throw downloadError || new Error("Arquivo não encontrado");
  // download=1 baixa direto (botão "Baixar contrato"); sem ele, abre no visualizador.
  let filename = "contrato-cec.pdf";
  if (download) {
    const { data: enrollment } = await supabase.from("enrollments").select("students(full_name)").eq("id", enrollmentId).maybeSingle();
    const name = String((enrollment as { students?: { full_name?: string } } | null)?.students?.full_name || "aluno")
      .normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^A-Za-z0-9]+/g, "-").replace(/^-|-$/g, "").toLowerCase();
    filename = `contrato-cec-${name}${acceptance?.signed_storage_path ? "-assinado" : ""}.pdf`;
  }
  return new Response(await file.arrayBuffer(), {
    headers: {
      ...corsHeaders,
      "Content-Type": "application/pdf",
      "Cache-Control": "private, no-store",
      "Content-Disposition": `${download ? "attachment" : "inline"}; filename=${filename}`,
    },
  });
}

async function generate(supabase: SupabaseClient, token: string, templateBase64: string, onlyIfOutdated = false) {
  const session = await getSession(supabase, token);
  if (!session) return json({ error: "Contrato indisponível" }, 404);
  if (templateBase64.length < 1000 || templateBase64.length > 1_000_000) return json({ error: "Modelo de contrato inválido" }, 422);

  const [guardianResult, enrollmentResult, versionResult] = await Promise.all([
    supabase.from("guardians").select("id, full_name, phone, rg, cpf, address").eq("id", session.guardian_id).single(),
    supabase.from("contract_session_enrollments").select("enrollment_id, enrollments!inner(id, campaign_id, target_grade_id, target_shift, amount_cents, students!inner(full_name), grades!enrollments_target_grade_id_fkey!inner(name), campaigns!inner(academic_year))").eq("contract_session_id", session.id),
    supabase.from("document_versions").select("id, sha256, version, documents!inner(code, kind)").eq("is_current", true).eq("documents.code", "contrato_prestacao").maybeSingle(),
  ]);
  if (guardianResult.error) throw guardianResult.error;
  if (enrollmentResult.error) throw enrollmentResult.error;
  if (versionResult.error) throw versionResult.error;
  if (!versionResult.data?.sha256) return json({ error: "Versão contratual indisponível" }, 409);

  // Abertura da página: só refaz o rascunho se ele não for do modelo atual
  // (ex.: gerado antes da troca para o contrato 2027).
  if (onlyIfOutdated) {
    const { data: current } = await supabase.from("document_acceptances")
      .select("enrollment_id").eq("contract_session_id", session.id)
      .eq("document_version_id", versionResult.data.id).not("generated_storage_path", "is", null);
    const done = new Set((current || []).map((item) => item.enrollment_id));
    if ((enrollmentResult.data || []).every((row: any) => done.has(row.enrollment_id))) return json({ ok: true, unchanged: true });
  }

  const template = decodeBase64(templateBase64);
  if (await sha256(template) !== versionResult.data.sha256) return json({ error: "O modelo do contrato não confere com a versão publicada pela escola" }, 409);
  const guardian = guardianResult.data;
  const rows = enrollmentResult.data || [];
  if (!guardian.full_name || !guardian.phone || !guardian.rg || !guardian.cpf || !guardian.address) {
    return json({ error: "Conclua os dados obrigatórios do responsável antes de gerar o contrato" }, 422);
  }
  if (!rows.length || rows.some((row: any) => !row.enrollments.students?.full_name || !row.enrollments.target_grade_id || !row.enrollments.target_shift)) {
    return json({ error: "Conclua os dados obrigatórios do aluno antes de gerar o contrato" }, 422);
  }

  await supabase.storage.createBucket("contract-files", { public: false, fileSizeLimit: "5MB", allowedMimeTypes: ["application/pdf"] }).catch(() => null);
  const files: Array<{ enrollment_id: string; path: string; hash: string }> = [];
  for (const row of rows as any[]) {
    const enrollment = row.enrollments;
    const path = contractFilePath(session.id, row.enrollment_id);
    const { data: existing } = await supabase
      .from("document_acceptances")
      .select("contract_session_id, generated_storage_path, generated_document_hash, signed_storage_path, signed_document_hash, status")
      .eq("enrollment_id", row.enrollment_id)
      .eq("document_version_id", versionResult.data.id)
      .maybeSingle();
    if (existing?.status === "assinado") {
      return json({ error: "Este contrato já foi assinado e seu PDF final está preservado." }, 409);
    }
    const pdf = await PDFDocument.load(template, { ignoreEncryption: true });
    const page = pdf.getPages()[0];
    const font = await pdf.embedFont(StandardFonts.Helvetica);
    if (isTemplate2027(page)) {
      // Quadro do modelo 2027. O RG continua no cadastro; o modelo não tem o campo.
      const { data: planRows } = await supabase.from("installments")
        .select("amount_cents, due_date").eq("enrollment_id", row.enrollment_id).neq("status", "cancelado").order("number");
      const monthly = Number(enrollment.amount_cents) || 0;
      drawField(page, font, guardian.full_name, 86, 691.3, 246);
      drawField(page, font, formatCpf(guardian.cpf), 363, 691.3, 193);
      drawField(page, font, formatPhone(guardian.phone), 93, 670, 239);
      drawWrapped(page, font, guardian.address, 383, 670, 173);
      drawField(page, font, enrollment.students.full_name, 85, 606.4, 247);
      drawField(page, font, enrollment.grades.name, 385, 606.4, 52);
      drawField(page, font, shiftLabel(enrollment.target_shift), 468, 606.4, 88);
      if (monthly) {
        drawField(page, font, `${money(monthly * 12)} (12 x ${money(monthly)})`, 135, 584.7, 197);
        drawField(page, font, money(monthly), 142, 562.7, 190);
      }
      drawField(page, font, "Dia 10 de cada mês", 393, 584.7, 163);
      drawWrapped(page, font, planLabel(planRows || []), 429, 562.7, 127);
    } else {
      drawField(page, font, guardian.full_name, 84, 734, 450);
      drawField(page, font, guardian.phone, 93, 714, 441);
      drawField(page, font, guardian.rg, 71, 694, 241);
      drawField(page, font, guardian.cpf, 351, 694, 183);
      drawField(page, font, guardian.address, 101, 673, 433);
      drawField(page, font, enrollment.students.full_name, 81, 622, 453);
      drawField(page, font, enrollment.grades.name, 98, 602, 110);
      drawField(page, font, shiftLabel(enrollment.target_shift), 252, 602, 282);
    }
    const output = await pdf.save();
    const outputHash = await sha256(output);
    // A correção dos dados invalida o rascunho antes da assinatura. O mesmo
    // caminho é sobrescrito com o PDF novo; cópias já assinadas nunca chegam
    // aqui porque a sessão é bloqueada pelo banco.
    const { error: uploadError } = await supabase.storage.from("contract-files").upload(path, output, { contentType: "application/pdf", upsert: true });
    if (uploadError) throw uploadError;
    const generationData = {
      template_version: versionResult.data.version,
      guardian: { full_name: guardian.full_name, phone: guardian.phone, rg: guardian.rg, cpf: guardian.cpf, address: guardian.address },
      student: { full_name: enrollment.students.full_name, grade: enrollment.grades.name, shift: shiftLabel(enrollment.target_shift) },
    };
    const { error: acceptanceError } = await supabase.from("document_acceptances").upsert({
      enrollment_id: row.enrollment_id,
      document_version_id: versionResult.data.id,
      contract_session_id: session.id,
      status: "pendente",
      provider: "cec_contrato_gerado",
      generated_storage_path: path,
      generated_document_hash: outputHash,
      generated_at: new Date().toISOString(),
      generation_data: generationData,
      document_hash: outputHash,
    }, { onConflict: "enrollment_id,document_version_id" });
    if (acceptanceError) throw acceptanceError;
    files.push({ enrollment_id: row.enrollment_id, path, hash: outputHash });
  }
  return json({ ok: true, files: files.map((file) => ({ enrollment_id: file.enrollment_id, sha256: file.hash })) });
}

async function sign(supabase: SupabaseClient, token: string, signerName: string, signatureData: string, accepted: boolean, request: Request) {
  if (!accepted) return json({ error: "Confirme a leitura e o aceite do contrato" }, 422);
  if (signerName.trim().length < 3) return json({ error: "Informe o nome completo de quem assina" }, 422);
  if (!/^data:image\/(png|jpeg);base64,/.test(signatureData) || signatureData.length < 100 || signatureData.length > 500_000) {
    return json({ error: "A assinatura desenhada é obrigatória" }, 422);
  }
  const session = await getSession(supabase, token);
  if (!session) return json({ error: "Contrato indisponível" }, 404);
  const { data: verification, error: verificationError } = await supabase
    .from("contract_sessions")
    .select("verification_verified_at")
    .eq("id", session.id)
    .single();
  if (verificationError) throw verificationError;
  if (!verification?.verification_verified_at) return json({ error: "Confirme o código enviado por e-mail antes de assinar" }, 422);

  const { data: acceptances, error: acceptanceError } = await supabase
    .from("document_acceptances")
    .select("id, enrollment_id, document_version_id, generated_storage_path, generated_document_hash, signed_storage_path, signed_document_hash, status")
    .eq("contract_session_id", session.id);
  if (acceptanceError) throw acceptanceError;
  // Vale só o contrato do modelo atual; um rascunho antigo da mesma sessão é ignorado.
  const { data: currentVersion } = await supabase.from("document_versions")
    .select("id, documents!inner(code)").eq("is_current", true).eq("documents.code", "contrato_prestacao").maybeSingle();
  const { data: sessionEnrollments } = await supabase.from("contract_session_enrollments")
    .select("enrollment_id").eq("contract_session_id", session.id);
  const current = (acceptances || []).filter((item) => !currentVersion?.id || item.document_version_id === currentVersion.id);
  const covered = new Set(current.map((item) => item.enrollment_id));
  if ((sessionEnrollments || []).some((item) => !covered.has(item.enrollment_id))) {
    return json({ error: "O contrato foi atualizado. Recarregue a página para ver a versão nova antes de assinar." }, 409);
  }
  if (!current.length || current.some((item) => !item.generated_storage_path || !item.generated_document_hash)) {
    return json({ error: "O PDF individual precisa ser gerado antes da assinatura" }, 422);
  }

  for (const acceptance of current) {
    // Enquanto a finalização ainda não aconteceu, uma nova tentativa pode
    // substituir apenas o rascunho assinado. Depois de finalizado, o banco
    // bloqueia a sessão e o arquivo final não é alterado.
    if (acceptance.status === "assinado") continue;
    const { data: source, error: sourceError } = await supabase.storage.from("contract-files").download(acceptance.generated_storage_path);
    if (sourceError || !source) throw sourceError || new Error("PDF individual não encontrado");
    const signedPdf = await applySignature(new Uint8Array(await source.arrayBuffer()), signatureData);
    const signedHash = await sha256(signedPdf);
    const path = signedContractFilePath(session.id, acceptance.enrollment_id);
    const { error: uploadError } = await supabase.storage.from("contract-files").upload(path, signedPdf, { contentType: "application/pdf", upsert: true });
    if (uploadError) throw uploadError;
    const { error: updateError } = await supabase
      .from("document_acceptances")
      .update({ signed_storage_path: path, signed_document_hash: signedHash, signed_pdf_at: new Date().toISOString() })
      .eq("id", acceptance.id);
    if (updateError) throw updateError;
  }

  const { data, error } = await supabase.rpc("contract_finalize_signed_pdf", {
    p_token: token,
    p_signer_full_name: signerName.trim(),
    p_signature_image_data: signatureData,
    p_accepted: true,
    p_ip: request.headers.get("x-forwarded-for"),
    p_user_agent: request.headers.get("user-agent"),
    p_device: request.headers.get("sec-ch-ua-mobile"),
  });
  if (error) throw error;
  return json(data);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRole) return json({ error: "Configuração interna ausente" }, 500);
  const supabase = createClient(supabaseUrl, serviceRole, { auth: { persistSession: false } });
  try {
    const url = new URL(request.url);
    if (request.method === "GET") {
      return await servePdf(supabase, url.searchParams.get("token") || "", url.searchParams.get("enrollment_id") || "", url.searchParams.get("download") === "1");
    }
    if (request.method !== "POST") return json({ error: "Método não suportado" }, 405);
    const body = await request.json();
    if (body?.action === "sign") {
      return await sign(supabase, String(body?.token || ""), String(body?.signer_name || ""), String(body?.signature_image_data || ""), body?.accepted === true, request);
    }
    return await generate(supabase, String(body?.token || ""), String(body?.template_base64 || ""), body?.only_if_outdated === true);
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Não foi possível gerar o contrato" }, 500);
  }
});
