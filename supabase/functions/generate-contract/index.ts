import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
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
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
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
  const maxWidth = 172;
  const maxHeight = 58;
  const scale = Math.min(maxWidth / image.width, maxHeight / image.height);
  const width = image.width * scale;
  const height = image.height * scale;
  page.drawImage(image, { x: 212 + (maxWidth - width) / 2, y: 379 + (maxHeight - height) / 2, width, height });
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  drawField(page, font, signedDate(), 453, 462, 78);
  return pdf.save();
}

async function getSession(supabase: ReturnType<typeof createClient>, token: string) {
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

async function servePdf(supabase: ReturnType<typeof createClient>, token: string, enrollmentId: string, download = false) {
  const session = await getSession(supabase, token);
  if (!session) return json({ error: "Contrato indisponível" }, 404);
  const { data: acceptance, error } = await supabase
    .from("document_acceptances")
    .select("generated_storage_path, signed_storage_path")
    .eq("contract_session_id", session.id)
    .eq("enrollment_id", enrollmentId)
    .not("generated_storage_path", "is", null)
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

async function generate(supabase: ReturnType<typeof createClient>, token: string, templateBase64: string) {
  const session = await getSession(supabase, token);
  if (!session) return json({ error: "Contrato indisponível" }, 404);
  if (templateBase64.length < 1000 || templateBase64.length > 1_000_000) return json({ error: "Modelo de contrato inválido" }, 422);

  const [guardianResult, enrollmentResult, versionResult] = await Promise.all([
    supabase.from("guardians").select("id, full_name, phone, rg, cpf, address").eq("id", session.guardian_id).single(),
    supabase.from("contract_session_enrollments").select("enrollment_id, enrollments!inner(id, campaign_id, target_grade_id, target_shift, students!inner(full_name), grades!enrollments_target_grade_id_fkey!inner(name), campaigns!inner(academic_year))").eq("contract_session_id", session.id),
    supabase.from("document_versions").select("id, sha256, version, documents!inner(code, kind)").eq("is_current", true).eq("documents.code", "contrato_prestacao").maybeSingle(),
  ]);
  if (guardianResult.error) throw guardianResult.error;
  if (enrollmentResult.error) throw enrollmentResult.error;
  if (versionResult.error) throw versionResult.error;
  if (!versionResult.data?.sha256) return json({ error: "Versão contratual indisponível" }, 409);

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
    drawField(page, font, guardian.full_name, 84, 734, 450);
    drawField(page, font, guardian.phone, 93, 714, 441);
    drawField(page, font, guardian.rg, 71, 694, 241);
    drawField(page, font, guardian.cpf, 351, 694, 183);
    drawField(page, font, guardian.address, 101, 673, 433);
    drawField(page, font, enrollment.students.full_name, 81, 622, 453);
    drawField(page, font, enrollment.grades.name, 98, 602, 110);
    drawField(page, font, shiftLabel(enrollment.target_shift), 252, 602, 282);
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

async function sign(supabase: ReturnType<typeof createClient>, token: string, signerName: string, signatureData: string, accepted: boolean, request: Request) {
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
    .select("id, enrollment_id, generated_storage_path, generated_document_hash, signed_storage_path, signed_document_hash, status")
    .eq("contract_session_id", session.id);
  if (acceptanceError) throw acceptanceError;
  if (!acceptances?.length || acceptances.some((item) => !item.generated_storage_path || !item.generated_document_hash)) {
    return json({ error: "O PDF individual precisa ser gerado antes da assinatura" }, 422);
  }

  for (const acceptance of acceptances) {
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
    return await generate(supabase, String(body?.token || ""), String(body?.template_base64 || ""));
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Não foi possível gerar o contrato" }, 500);
  }
});
