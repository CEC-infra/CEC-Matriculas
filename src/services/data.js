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
    select: 'id,grade_id,shifts,amount_cents,cash_amount_cents,seats_total,grades(name,sort_order)',
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
    p_preferred_shift: values.shift || null,
    p_current_school: values.currentSchool || null,
    p_source: values.source || 'site',
    p_utm: Object.fromEntries(new URLSearchParams(window.location.search))
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

export async function createStaffEnrollment(values) {
  const campaign = await getActiveCampaign('matricula_nova');
  if (!campaign) throw new Error('Não há campanha de matrícula nova ativa.');
  const normalizedPhone = await supabase.rpc('normalize_phone_br', { raw: values.phone });
  if (!normalizedPhone) throw new Error('Informe um WhatsApp válido.');
  let guardian = first(await supabase.select('guardians', q({ select: '*', phone: eq(normalizedPhone) })));
  if (!guardian) guardian = first(await supabase.insert('guardians', { full_name: values.guardianName, phone: normalizedPhone, whatsapp_consent_at: new Date().toISOString() }));
  const student = first(await supabase.insert('students', { full_name: values.studentName, previous_school: values.currentSchool || null }));
  await supabase.insert('student_guardians', { student_id: student.id, guardian_id: guardian.id, is_financial: true, is_primary_contact: true });
  const offering = first(await supabase.select('grade_offerings', q({ select: '*', academic_year: eq(campaign.academic_year), grade_id: eq(values.gradeId) })));
  const enrollment = first(await supabase.insert('enrollments', {
    campaign_id: campaign.id, guardian_id: guardian.id, student_id: student.id,
    origin: values.source || 'outro', target_grade_id: values.gradeId, target_shift: values.shift || null,
    status: 'em_fila', amount_cents: offering?.amount_cents || null
  }));
  await supabase.insert('enrollment_events', { enrollment_id: enrollment.id, code: 'STAFF_CREATED', title: 'Cadastro criado pela equipe', body: 'Família adicionada ao atendimento.', actor: 'equipe' });
  return enrollment;
}

export function setQueuePaused(campaignId, paused) {
  return supabase.update('campaigns', `id=eq.${campaignId}`, { queue_paused: paused });
}
