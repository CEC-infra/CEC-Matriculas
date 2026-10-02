import { supabase } from '../lib/supabase';

const first = (rows) => rows?.[0] || null;
const q = (parts) => new URLSearchParams(parts).toString();
const eq = (value) => `eq.${value}`;

export async function getCurrentProfile() {
  const session = supabase.getSession();
  if (!session?.user?.id) return null;
  return first(await supabase.select('profiles', q({ select: '*', id: eq(session.user.id) })));
}

export async function getCampaigns() {
  return supabase.select('campaigns', q({ select: '*', order: 'starts_on.desc' }));
}

export async function getActiveCampaign(kind) {
  const campaigns = await supabase.select('campaigns', q({
    select: '*', kind: eq(kind), status: eq('ativa'), order: 'starts_on.desc', limit: '1'
  }));
  return first(campaigns);
}

export async function getDashboard() {
  const campaigns = await getCampaigns();
  const campaign = campaigns.find((item) => item.kind === 'rematricula' && item.status === 'ativa') || campaigns[0];
  if (!campaign) return { campaigns: [], campaign: null };
  const filter = q({ select: '*', campaign_id: eq(campaign.id) });
  const [funnel, finance, alerts, queue] = await Promise.all([
    supabase.select('v_campaign_funnel', filter),
    supabase.select('v_campaign_finance', filter),
    supabase.select('v_dashboard_alerts', filter),
    supabase.select('v_queue_stats', filter)
  ]);
  return { campaigns, campaign, funnel: first(funnel), finance: first(finance), alerts: first(alerts), queue: first(queue) };
}

export async function getEnrollments({ kind } = {}) {
  const filter = { select: '*', order: 'updated_at.desc' };
  if (kind) filter.campaign_kind = eq(kind);
  return supabase.select('v_enrollment_list', q(filter));
}

export async function getEnrollmentDetail(id) {
  const enrollment = first(await supabase.select('v_enrollment_list', q({ select: '*', id: eq(id) })));
  if (!enrollment) return null;
  const [events, installments, documents, family] = await Promise.all([
    supabase.select('enrollment_events', q({ select: '*', enrollment_id: eq(id), order: 'created_at.desc' })),
    supabase.select('installments', q({ select: '*', enrollment_id: eq(id), order: 'number.asc' })),
    supabase.select('document_acceptances', q({ select: '*,document_versions(version,pages,documents(title))', enrollment_id: eq(id), order: 'created_at.asc' })),
    enrollment.guardian_id
      ? supabase.select('v_enrollment_list', q({ select: '*', guardian_id: eq(enrollment.guardian_id), campaign_id: eq(enrollment.campaign_id), order: 'created_at.asc' }))
      : Promise.resolve([])
  ]);
  // Irmãos na mesma campanha: podem entrar no mesmo contrato conjunto.
  const siblings = (family || []).filter((item) => item.id !== enrollment.id);
  return { enrollment, events, installments, documents, siblings };
}

export async function getSettings() {
  const campaigns = await getCampaigns();
  const campaign = campaigns.find((item) => item.status === 'ativa' && item.kind === 'rematricula') || campaigns[0];
  if (!campaign) return { campaigns: [], campaign: null, offerings: [], policy: null, documents: [] };
  const [offerings, policies, documents] = await Promise.all([
    supabase.select('v_grade_offerings', q({ select: '*', academic_year: eq(campaign.academic_year), order: 'sort_order.asc' })),
    supabase.select('payment_policies', q({ select: '*', campaign_id: eq(campaign.id) })),
    supabase.select('document_versions', q({ select: '*,documents(title,requirement)', is_current: eq('true'), order: 'created_at.asc' }))
  ]);
  return { campaigns, campaign, offerings, policy: first(policies), documents };
}

export async function getPublicOfferings() {
  const rows = await supabase.rpc('public_grade_offerings');
  const offerings = (rows || []).map(({ grade_name, sort_order, ...item }) => ({
    ...item,
    grades: { name: grade_name, sort_order }
  }));
  return { offerings };
}

export function submitPreEnrollment(values) {
  return supabase.rpc('pre_matricula_submit', {
    p_guardian_name: values.guardianName,
    p_phone: values.phone,
    p_student_name: values.studentName,
    p_target_grade_id: values.gradeId,
    p_whatsapp_consent: values.consent,
    p_current_school: values.currentSchool || null,
    p_source: values.source || 'site',
    p_utm: Object.fromEntries(new URLSearchParams(window.location.search))
  });
}

export function startEnrollmentOnboarding(flow, token = null) {
  return supabase.rpc('onboarding_start', { p_flow: flow, p_token: token });
}

export function openEnrollmentOnboarding(token) {
  return supabase.rpc('onboarding_open', { p_token: token });
}

export function identifyRematriculaOnboarding(token, values) {
  return supabase.rpc('onboarding_identify_rematricula', {
    p_token: token,
    p_cpf: values.cpf,
    p_phone: values.phone,
    p_full_name: values.fullName || null
  });
}

export function selectRematriculaChildren(token, studentIds) {
  return supabase.rpc('onboarding_select_rematricula_children', { p_token: token, p_student_ids: studentIds });
}

export function createMatriculaOnboarding(token, values) {
  return supabase.rpc('onboarding_create_matricula', {
    p_token: token,
    p_guardian_cpf: values.cpf,
    p_guardian_name: values.fullName,
    p_phone: values.phone,
    p_email: values.email,
    p_address: values.address,
    p_children: values.children
  });
}

export function lookupExistingFamilyForNewEnrollment(token, values) {
  return supabase.rpc('onboarding_lookup_existing_family', {
    p_token: token,
    p_cpf: values.cpf,
    p_phone: values.phone
  });
}

export function startRematriculaFromNewEnrollment(token, values) {
  return supabase.rpc('onboarding_start_rematricula_from_new_enrollment', {
    p_token: token,
    p_cpf: values.cpf,
    p_phone: values.phone
  });
}

export function prepareOnboardingContract(token, enrollmentId, email) {
  return supabase.rpc('onboarding_prepare_individual_contract', {
    p_token: token,
    p_enrollment_id: enrollmentId,
    p_confirmation_email: email || null
  });
}

export function chooseRematriculaPaymentOption(token, option) {
  return supabase.rpc('onboarding_choose_payment_option', { p_token: token, p_option: option });
}

export function prepareFamilyContract(token, email) {
  return supabase.rpc('onboarding_prepare_family_contract', { p_token: token, p_confirmation_email: email || null });
}

export function chooseOnboardingPlan(token, installments) {
  return supabase.rpc('onboarding_choose_plan', { p_token: token, p_installments: installments });
}

export function chooseOnboardingBilling(token, method) {
  return supabase.rpc('onboarding_choose_billing', { p_token: token, p_method: method });
}

export function onboardingCardQuote(token) {
  return supabase.rpc('onboarding_card_quote', { p_token: token });
}

export function createAsaasCheckout(token) {
  return supabase.invokeFunction('asaas-checkout', { token });
}

export function addRematriculaChild(token, child) {
  return supabase.rpc('onboarding_add_child', {
    p_token: token,
    p_name: child.name,
    p_grade_id: child.gradeId,
    p_birth_date: child.birthDate || null,
    p_previous_school: child.previousSchool || null
  });
}

export function removeAddedChild(token, studentId) {
  return supabase.rpc('onboarding_remove_added_child', { p_token: token, p_student_id: studentId });
}

export function setGuardianRg(token, rg) {
  return supabase.rpc('onboarding_set_guardian_rg', { p_token: token, p_rg: rg });
}

export function chooseOnboardingPayment(token, paymentPlanId, method) {
  return supabase.rpc('onboarding_choose_payment', {
    p_token: token,
    p_payment_plan_id: paymentPlanId,
    p_method: method
  });
}

export function openRematricula(token) {
  return supabase.rpc('rematricula_open', { p_token: token });
}

export function saveRematricula(token, values) {
  return supabase.rpc('rematricula_save', {
    p_token: token,
    p_payment_plan_id: values.planId,
    p_email: values.email || null,
    p_phone: values.phone || null
  });
}

export function createPersonalizedEnrollmentLink(enrollmentId) {
  return supabase.rpc('create_personalized_enrollment_link', { p_enrollment_id: enrollmentId });
}

export function getActiveEnrollmentLinks() {
  return supabase.select('enrollment_links', q({
    select: 'enrollment_id,token,expires_at,created_at',
    revoked_at: 'is.null',
    expires_at: `gt.${new Date().toISOString()}`,
    order: 'created_at.desc'
  }));
}

export function openMatriculaLink(token) {
  return supabase.rpc('matricula_link_open', { p_token: token });
}

export function saveMatriculaLink(token, values) {
  return supabase.rpc('matricula_link_save', {
    p_token: token,
    p_guardian_name: values.guardianName,
    p_email: values.email || null,
    p_phone: values.phone || null,
    p_student_name: values.studentName,
    p_birth_date: values.birthDate || null,
    p_previous_school: values.previousSchool || null,
    p_target_grade_id: values.gradeId || null,
    p_payment_plan_id: values.planId || null
  });
}

export function completeMatriculaLink(token) {
  return supabase.rpc('matricula_link_complete', { p_token: token });
}

export function startContract(enrollmentId, confirmationEmail) {
  return supabase.rpc('contract_create_session', {
    p_enrollment_id: enrollmentId,
    p_confirmation_email: confirmationEmail || null
  });
}

export function startFamilyContract(enrollmentIds, confirmationEmail) {
  return supabase.rpc('contract_create_family_session', {
    p_enrollment_ids: enrollmentIds,
    p_confirmation_email: confirmationEmail || null
  });
}

export function openContract(token) {
  return supabase.rpc('contract_open', { p_token: token });
}

export function completeContractRequiredData(token, guardian, students) {
  return supabase.rpc('contract_complete_required_data', {
    p_token: token,
    p_guardian: guardian,
    p_students: students
  });
}

function bytesToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  let binary = '';
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary);
}

export async function generateContractPdf(token) {
  const response = await fetch('/contracts/contrato-matricula-cec-2025.pdf');
  if (!response.ok) throw new Error('Não foi possível carregar o modelo final do contrato.');
  return supabase.invokeFunction('generate-contract', {
    token,
    template_base64: bytesToBase64(await response.arrayBuffer())
  });
}

export function contractPdfUrl(token, enrollmentId, { download = false } = {}) {
  const url = import.meta.env.VITE_SUPABASE_URL;
  if (!url) return '';
  return `${url}/functions/v1/generate-contract?token=${encodeURIComponent(token)}&enrollment_id=${encodeURIComponent(enrollmentId)}${download ? '&download=1' : ''}`;
}

/** Baixa vários PDFs de uma vez, sem sair da página (o servidor responde como anexo). */
export function downloadFiles(urls) {
  urls.filter(Boolean).forEach((url, index) => {
    window.setTimeout(() => {
      const frame = document.createElement('iframe');
      frame.style.display = 'none';
      frame.src = url;
      document.body.appendChild(frame);
      window.setTimeout(() => frame.remove(), 60000);
    }, index * 400);
  });
}

export async function sendContractCode(token) {
  await supabase.rpc('contract_send_email_code', { p_token: token });
  return supabase.invokeFunction('dispatch-contract-emails', { token });
}

export function dispatchPendingContractEmail(token) {
  return supabase.invokeFunction('dispatch-contract-emails', { token });
}

export function verifyContractCode(token, code) {
  return supabase.rpc('contract_verify_email_code', { p_token: token, p_code: code });
}

export function signContract(token, values) {
  return supabase.invokeFunction('generate-contract', {
    action: 'sign',
    token,
    signer_name: values.signerName,
    signature_image_data: values.signatureImage,
    accepted: values.accepted
  });
}

export function getContractSessions() {
  return supabase.select('v_contract_sessions', q({ select: '*', order: 'updated_at.desc' }));
}

export function getPaymentPlans(campaignId) {
  if (!campaignId) return Promise.resolve([]);
  return supabase.select('payment_plans', q({ select: '*', campaign_id: eq(campaignId), active: eq('true'), order: 'sort_order.asc' }));
}

export function setEnrollmentPaymentPlan(enrollmentId, paymentPlanId) {
  return supabase.rpc('staff_set_enrollment_payment_plan', { p_enrollment_id: enrollmentId, p_payment_plan_id: paymentPlanId });
}

export async function createStaffEnrollment(values) {
  return supabase.rpc('staff_create_family_enrollment', {
    p_guardian_cpf: values.guardianCpf,
    p_guardian_name: values.guardianName,
    p_guardian_phone: values.phone,
    p_guardian_email: values.email,
    p_guardian_address: values.address,
    p_student_name: values.studentName,
    p_target_grade_id: values.gradeId,
    p_student_birth_date: values.birthDate || null,
    p_current_school: values.currentSchool || null,
    p_source: values.source || 'outro',
    p_relationship: values.relationship || null,
    p_guardian_notes: values.notes || null
  });
}
