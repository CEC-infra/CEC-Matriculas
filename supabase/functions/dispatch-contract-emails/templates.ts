import { LOGO_CONTENT_ID } from "./logo.ts";

// Paleta da marca (mesmos tokens do app em src/).
const c = {
  bg: "#FBF6EF",
  surface: "#FFFFFF",
  line: "#EFE3D4",
  navy: "#233A7A",
  navySoft: "#EEF2FC",
  inkBody: "#3E4A63",
  inkMute: "#6B6A63",
  orange: "#F07E26",
  green: "#3AA757",
};

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]!));
}

export type RenderedEmail = { html: string; text: string };

export function renderContractCodeEmail(data: { code: string; expires_minutes?: number }): RenderedEmail {
  const code = escapeHtml(String(data.code).toUpperCase());
  const minutes = Number(data.expires_minutes) || 15;

  const html = `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>Seu código de confirmação – CEC Matrículas</title>
</head>
<body style="margin:0;padding:0;background:${c.bg};-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${c.bg};">Seu código é ${code} · expira em ${minutes} minutos.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${c.bg};">
  <tr><td align="center" style="padding:32px 16px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;background:${c.surface};border:1px solid ${c.line};border-radius:20px;overflow:hidden;">
      <tr>
        <td height="6" style="height:6px;font-size:0;line-height:0;background:${c.orange};width:33%;">&nbsp;</td>
        <td height="6" style="height:6px;font-size:0;line-height:0;background:${c.navy};width:34%;">&nbsp;</td>
        <td height="6" style="height:6px;font-size:0;line-height:0;background:${c.green};width:33%;">&nbsp;</td>
      </tr>
      <tr><td colspan="3" align="center" style="padding:32px 32px 8px;">
        <img src="cid:${LOGO_CONTENT_ID}" width="180" height="102" alt="CEC Matrículas" style="display:block;width:180px;height:auto;border:0;">
      </td></tr>
      <tr><td colspan="3" align="center" style="padding:16px 32px 0;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <h1 style="margin:0;font-size:22px;line-height:1.3;font-weight:700;color:${c.navy};">Confirme sua identidade</h1>
        <p style="margin:12px 0 0;font-size:15px;line-height:1.6;color:${c.inkBody};">Use o código abaixo para confirmar seu e-mail e assinar o contrato de matrícula.</p>
      </td></tr>
      <tr><td colspan="3" align="center" style="padding:28px 24px 8px;">
        <!-- Um único bloco de texto: tocar e segurar seleciona o código inteiro, sem espaços entre as letras. -->
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="background:${c.navySoft};border:2px dashed ${c.navy};border-radius:14px;">
          <tr><td align="center" style="padding:16px 18px 16px 28px;font-family:'SFMono-Regular',Menlo,Consolas,monospace;font-size:34px;line-height:1.2;font-weight:700;letter-spacing:10px;color:${c.navy};-webkit-user-select:all;user-select:all;">${code}</td></tr>
        </table>
        <p style="margin:10px 0 0;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:${c.inkMute};">Toque e segure no código para copiar.</p>
      </td></tr>
      <tr><td colspan="3" align="center" style="padding:12px 32px 0;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <p style="margin:0;font-size:13px;line-height:1.5;color:${c.inkMute};">O código expira em <strong style="color:${c.navy};">${minutes} minutos</strong>.</p>
      </td></tr>
      <tr><td colspan="3" style="padding:28px 32px 32px;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${c.bg};border-radius:12px;">
          <tr><td style="padding:14px 16px;font-size:13px;line-height:1.55;color:${c.inkBody};">
            <strong style="color:${c.navy};">Não foi você?</strong> Ignore este e-mail. Ninguém da escola vai pedir este código por telefone ou mensagem.
          </td></tr>
        </table>
      </td></tr>
    </table>
    <p style="margin:20px 0 0;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:${c.inkMute};">CEC Matrículas · Este é um e-mail automático, não responda.</p>
  </td></tr>
</table>
</body>
</html>`;

  // O Gmail usa o início da versão em texto como prévia na lista de e-mails.
  const text = `Seu código é ${code} · expira em ${minutes} minutos.

Use este código para confirmar seu e-mail e assinar o contrato de matrícula CEC.
Não foi você? Ignore este e-mail. Ninguém da escola vai pedir este código por telefone ou mensagem.`;

  return { html, text };
}
