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
  const [events, installments, documents, conversations] = await Promise.all([
    supabase.select('enrollment_events', q({ select: '*', enrollment_id: eq(id), order: 'created_at.desc' })),
    supabase.select('installments', q({ select: '*', enrollment_id: eq(id), order: 'number.asc' })),
    supabase.select('document_acceptances', q({ select: '*,document_versions(version,pages,documents(title))', enrollment_id: eq(id), order: 'created_at.asc' })),
    supabase.select('conversations', q({ select: '*', enrollment_id: eq(id), limit: '1' }))
  ]);
  const conversation = first(conversations);
  const messages = conversation
    ? await supabase.select('messages', q({ select: '*', conversation_id: eq(conversation.id), order: 'created_at.asc' }))
    : [];
  return { enrollment, events, installments, documents, conversation, messages };
}

export async function getAutomation() {
  const campaign = await getActiveCampaign('rematricula');
  if (!campaign) return { campaign: null, stats: null, queue: [], throughput: [], attended: [] };
  const filter = q({ select: '*', campaign_id: eq(campaign.id) });
  const [stats, queue, throughput, attended] = await Promise.all([
    supabase.select('v_queue_stats', filter),
    supabase.select('v_queue_upcoming', q({ select: '*', campaign_id: eq(campaign.id), order: 'scheduled_for.asc', limit: '20' })),
    supabase.select('v_hourly_throughput', q({ select: '*', campaign_id: eq(campaign.id), order: 'hora.asc' })),
    supabase.select('v_enrollment_list', q({ select: '*', campaign_id: eq(campaign.id), order: 'updated_at.desc', limit: '12' }))
  ]);
  return { campaign, stats: first(stats), queue, throughput, attended };
}

export function getConversations() {
  return supabase.select('v_conversation_list', q({ select: '*', order: 'last_message_at.desc' }));
}

export function getConversationMessages(conversationId) {
  if (!conversationId) return Promise.resolve([]);
  return supabase.select('messages', q({ select: '*', conversation_id: eq(conversationId), order: 'created_at.asc' }));
}

export function setConversationHandler(conversationId, handler) {
  return supabase.update('conversations', `id=eq.${conversationId}`, { handler });
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
  const offerings = await supabase.select('grade_offerings', q({
    select: 'id,grade_id,amount_cents,cash_amount_cents,seats_total,grades(name,sort_order)',
    order: 'grades(sort_order).asc'
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

export function prepareOnboardingContract(token, enrollmentId, email) {
  return supabase.rpc('onboarding_prepare_individual_contract', {
    p_token: token,
    p_enrollment_id: enrollmentId,
    p_confirmation_email: email || null
  });
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

export function openContract(token) {
  return supabase.rpc('contract_open', { p_token: token });
}

export function sendContractCode(token) {
  return supabase.rpc('contract_send_email_code', { p_token: token });
}

export function verifyContractCode(token, code) {
  return supabase.rpc('contract_verify_email_code', { p_token: token, p_code: code });
}

export function signContract(token, values) {
  return supabase.rpc('contract_sign', {
    p_token: token,
    p_signer_full_name: values.signerName,
    p_signature_image_data: values.signatureImage,
    p_accepted: values.accepted
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

export function setQueuePaused(campaignId, paused) {
  return supabase.update('campaigns', `id=eq.${campaignId}`, { queue_paused: paused });
}
