/* Dados de demonstração. Trocar por chamadas à API quando o backend existir.
   Só as telas em src/pages dependem da forma exata destes objetos. */
export const DATA = {

  /* Menu da sidebar. `icon` referencia um traçado de src/components/Icon.jsx,
     `dot` é a cor de acento do item e `path` é a rota que ele abre. */
  nav: [
    { path: '/dashboard',              label: 'Dashboard',              icon: 'dashboard',  dot: '#E4581C' },
    { path: '/familias',               label: 'Famílias',               icon: 'families',   dot: '#3AA757' },
    { path: '/atendimento',            label: 'Atendimento',            icon: 'chat',       dot: '#5B8DEF' },
    { path: '/matriculas-novas',       label: 'Matrículas novas',       icon: 'newEnroll',  dot: '#C77DFF' },
    { path: '/matriculados',           label: 'Matriculados',           icon: 'enrolled',   dot: '#3AA757' },
    { path: '/automacao',              label: 'Automação',              icon: 'automation', dot: '#E89A4E' },
    { path: '/assinatura-e-pagamento', label: 'Assinatura e pagamento', icon: 'signature',  dot: '#3AA757' },
    { path: '/configuracoes',          label: 'Configurações',          icon: 'settings',   dot: '#A8B8E0' }
  ],

  /* Cabeçalho por rota: [migalha, título]. O detalhe da família monta o seu. */
  heads: {
    '/dashboard':              ['Campanha Rematrícula 2027 · dia 12 de 20', 'Visão geral da operação'],
    '/familias':               ['CRM operacional', 'Famílias na campanha'],
    '/atendimento':            ['Central de atendimento · WhatsApp', 'Conversas e handoff humano'],
    '/matriculas-novas':       ['Entrada de novas famílias', 'Matrículas novas'],
    '/matriculados':           ['Resultado da campanha', 'Matriculados'],
    '/automacao':              ['Motor de mensagens · fila de envio', 'Automação'],
    '/assinatura-e-pagamento': ['Conclusão da jornada', 'Assinatura digital e pagamento'],
    '/configuracoes':          ['Cadastros da campanha · somente leitura', 'Configurações'],
    '/rematricula':            ['Jornada online do responsável', 'Página individual de rematrícula'],
    '/matricula':              ['Novas matrículas', 'Link público de pré-matrícula']
  },

  headerLinks: [
    { path: '/rematricula', label: 'Link de rematrícula',    url: 'cec.app/rematricula', icon: 'link',    dot: '#F07E26' },
    { path: '/matricula',   label: 'Link de matrícula nova', url: 'cec.app/matricula',   icon: 'sparkle', dot: '#3AA757' }
  ],

  dashLinks: [
    { path: '/rematricula', label: 'Rematrícula',    url: 'cec.app/rematricula/{token}', dot: '#F07E26', n: '178 enviados · 141 abertos', sub: 'Link individual por família · enviado pela IA na conversa' },
    { path: '/matricula',   label: 'Matrícula nova', url: 'cec.app/matricula',           dot: '#3AA757', n: '14 pré-matrículas hoje',    sub: 'Link público de pré-matrícula · divulgação e indicações' }
  ],

  kpis: [
    { label: 'Receita confirmada', value: 'R$ 38,6 mil',  sub: 'de R$ 214,3 mil previstos', delta: '18%',      tone: 'ok' },
    { label: 'Em negociação',      value: 'R$ 127,3 mil', sub: '244 famílias em aberto',    delta: '59%',      tone: 'warn' },
    { label: 'Ticket médio',       value: 'R$ 522',       sub: 'por família concluída',     delta: '',         tone: 'mute' },
    { label: 'Taxa de resposta',   value: '65%',          sub: '206 de 318 contatadas',     delta: '+28 hoje', tone: 'ok' },
    { label: 'Conversão final',    value: '18%',          sub: '74 de 412 elegíveis',       delta: '+11 hoje', tone: 'ok' }
  ],

  closing: [
    { label: 'Fechadas', n: 74,  money: 'R$ 38.610',  share: '18%', navy: true,  bar: '#5BD98A', sub: 'Contrato assinado e pagamento confirmado' },
    { label: 'A fechar', n: 244, money: 'R$ 127.320', share: '59%', navy: false, bar: '#F07E26', ink: 'var(--orange-ink)', sub: 'Em conversa, com link enviado ou aguardando assinatura' },
    { label: 'Perdidas', n: 94,  money: 'R$ 48.390',  share: '23%', navy: false, bar: '#B9B2A5', ink: 'var(--ink-mute)',   sub: 'Opt-out, sem interesse ou fora da campanha' }
  ],

  funnel: [
    { label: 'Elegíveis',           n: 412, pct: '100%', color: '#233A7A' },
    { label: 'Contatadas',          n: 318, pct: '77%',  color: '#2E4A96' },
    { label: 'Responderam',         n: 206, pct: '50%',  color: '#3A5FBF' },
    { label: 'Link enviado',        n: 178, pct: '43%',  color: '#4A7BD8' },
    { label: 'Link aberto',         n: 141, pct: '34%',  color: '#F0A93C' },
    { label: 'Formulário iniciado', n: 118, pct: '29%',  color: '#F07E26' },
    { label: 'Assinado',            n: 97,  pct: '24%',  color: '#E4581C' },
    { label: 'Pago / concluído',    n: 74,  pct: '18%',  color: '#3AA757' }
  ],

  alerts: [
    { n: 7, label: 'Conversas travadas',  sub: 'sem resposta após o link aberto', color: '#B8430E', go: '/familias' },
    { n: 4, label: 'Pagamentos vencidos', sub: 'boleto de novembro em atraso',    color: '#C0392B', go: '/familias' },
    { n: 3, label: 'Aguardando humano',   sub: 'negociação e pedidos de bolsa',   color: '#8A5D08', go: '/familias/patricia-andrade' },
    { n: 2, label: 'Falhas de webhook',   sub: 'reprocessar integração',          color: '#233A7A', go: '/automacao' }
  ],

  engine: [
    { label: 'Na fila agora',   value: '34' },
    { label: 'Enviadas hoje',   value: '128' },
    { label: 'Falhas / retry',  value: '3' },
    { label: 'Próximo lote',    value: '15:00' }
  ],

  finance: [
    { label: 'Previsto',   value: 'R$ 214.320', pct: '100%', color: '#233A7A', sub: '412 famílias × valor da turma' },
    { label: 'Contratado', value: 'R$ 51.940',  pct: '24%',  color: '#F07E26', sub: '97 contratos assinados' },
    { label: 'Recebido',   value: 'R$ 38.610',  pct: '18%',  color: '#3AA757', sub: '74 pagamentos confirmados' },
    { label: 'Em atraso',  value: 'R$ 2.480',   pct: '5%',   color: '#C0392B', sub: '4 parcelas vencidas' }
  ],

  familyFilters: [
    ['Todas', 412], ['Em fila', 34], ['Conversando', 61], ['Link aberto', 141],
    ['Aguardando assinatura', 21], ['Aguardando pagamento', 23], ['Sem interesse', 12]
  ],

  /* `id` é o segmento usado em /familias/:id. */
  families: [
    { id: 'patricia-andrade', parent: 'Patrícia Andrade', phone: '(83) 99812-4471', student: 'Lucas Andrade',   klass: '5º ano A → 6º ano',   status: 'Aguardando assinatura', tone: 'warn', tries: 3, next: 'Follow-up 15:00' },
    { id: 'rogerio-lima',     parent: 'Rogério Lima',     phone: '(83) 99640-1180', student: 'Ana Lima',        klass: '2º ano B → 3º ano',   status: 'Pago',                  tone: 'ok',   tries: 2, next: '—' },
    { id: 'cleide-barbosa',   parent: 'Cleide Barbosa',   phone: '(83) 98871-0093', student: 'Miguel Barbosa',  klass: '8º ano A → 9º ano',   status: 'Link aberto',           tone: 'info', tries: 4, next: 'Follow-up 2 amanhã' },
    { id: 'juliana-reis',     parent: 'Juliana Reis',     phone: '(83) 99127-6650', student: 'Sofia Reis',      klass: 'Infantil V → 1º ano', status: 'Conversando',           tone: 'info', tries: 1, next: 'IA aguardando' },
    { id: 'marcos-tavares',   parent: 'Marcos Tavares',   phone: '(83) 98812-3390', student: 'Pedro Tavares',   klass: '7º ano A → 8º ano',   status: 'Precisa de humano',     tone: 'warn', tries: 5, next: 'Negociação' },
    { id: 'elaine-duarte',    parent: 'Elaine Duarte',    phone: '(83) 99334-2201', student: 'Bruna Duarte',    klass: '4º ano B → 5º ano',   status: 'Em fila',               tone: 'mute', tries: 0, next: 'Envio 15:00' },
    { id: 'fabio-nogueira',   parent: 'Fábio Nogueira',   phone: '(83) 99001-7742', student: 'Heitor Nogueira', klass: '1º ano A → 2º ano',   status: 'Pagamento vencido',     tone: 'warn', tries: 3, next: 'Cobrança hoje' },
    { id: 'sandra-vieira',    parent: 'Sandra Vieira',    phone: '(83) 98770-5512', student: 'Isabela Vieira',  klass: '9º ano A → 1ª série', status: 'Sem interesse',         tone: 'mute', tries: 4, next: 'Encerrado' }
  ],

  famFacts: [
    { label: 'Turma atual',     value: '5º ano A' },
    { label: 'Próxima turma',   value: '6º ano' },
    { label: 'Valor aplicável', value: 'R$ 1.458' },
    { label: 'Campanha',        value: 'Rematrícula 2027' }
  ],

  timeline: [
    { time: 'hoje 14:12', title: 'Assinatura pendente',            code: 'SIGNATURE_PENDING', color: '#8A5D08', body: 'Documento enviado ao provedor de assinatura. Aguardando conclusão da responsável.' },
    { time: 'hoje 14:05', title: 'Termos aceitos',                 code: 'TERMS_ACCEPTED',    color: '#F07E26', body: 'Contrato 2027 aceito na versão v3 · IP registrado.' },
    { time: 'hoje 13:58', title: 'Formulário iniciado',            code: 'FORM_STARTED',      color: '#F07E26', body: 'Dados pré-preenchidos confirmados; telefone atualizado pela responsável.' },
    { time: 'hoje 13:51', title: 'Link aberto',                    code: 'LINK_OPENED',       color: '#4A7BD8', body: 'Primeira abertura em dispositivo móvel.' },
    { time: 'hoje 13:44', title: 'Link enviado pela IA',           code: 'LINK_SENT',         color: '#4A7BD8', body: 'Token individual gerado para Patrícia · Lucas · campanha 2027.' },
    { time: 'hoje 13:40', title: 'Intenção classificada: interessada', code: 'AI_INTENT',     color: '#5B8DEF', body: 'A IA identificou interesse e liberou o envio do link.' },
    { time: 'ontem 09:02', title: 'Contato inicial enviado',       code: 'MSG_SENT',          color: '#6B6A63', body: 'Tentativa 1 da régua · janela 08:00–19:30 respeitada.' }
  ],

  familyActions: ['Assumir conversa', 'Pausar automação', 'Reenviar link', 'Corrigir dado', 'Marcar exceção', 'Ver contrato'],

  payRows: [
    { label: 'Contrato 2027',           sub: 'provedor de assinatura · v3', status: 'Pendente',  tone: 'warn' },
    { label: 'Parcela 1 · novembro',    sub: 'R$ 486,00 · boleto',          status: 'Aguardando', tone: 'mute' },
    { label: 'Parcela 2 · dezembro',    sub: 'R$ 486,00 · boleto',          status: 'Aguardando', tone: 'mute' },
    { label: 'Parcela 3 · janeiro',     sub: 'R$ 486,00 · boleto',          status: 'Aguardando', tone: 'mute' }
  ],

  convos: [
    { id: 'patricia-andrade', name: 'Patrícia Andrade', last: 'Dá sim — até 3x, com a última em janeiro…', tag: 'IA',        color: 'var(--green-ink)',  time: '14:12', active: true },
    { id: 'marcos-tavares',   name: 'Marcos Tavares',   last: 'Preciso falar sobre desconto de irmãos',    tag: 'Humano',    color: 'var(--orange-ink)', time: '13:58' },
    { id: 'juliana-reis',     name: 'Juliana Reis',     last: 'Qual o valor do 1º ano?',                   tag: 'IA',        color: 'var(--green-ink)',  time: '13:40' },
    { id: 'cleide-barbosa',   name: 'Cleide Barbosa',   last: 'Abri o link mas travou no pagamento',       tag: 'Humano',    color: 'var(--orange-ink)', time: '11:22' },
    { id: 'rogerio-lima',     name: 'Rogério Lima',     last: 'Obrigado! Já paguei 🙏',                    tag: 'Encerrada', color: 'var(--ink-mute)',   time: 'ontem' },
    { id: 'elaine-duarte',    name: 'Elaine Duarte',    last: 'Aguardando primeiro contato',               tag: 'Fila',      color: 'var(--navy)',       time: 'ontem' }
  ],

  thread: [
    { dir: 'in',  text: 'Oi Patrícia! Aqui é do CEC 👋 A rematrícula do Lucas para o 6º ano já está aberta. Quer que eu te explique as condições?', meta: 'IA · ontem 09:02' },
    { dir: 'out', text: 'Oi! Quero sim, dá pra parcelar?', meta: 'Patrícia · hoje 13:38' },
    { dir: 'in',  text: 'Dá sim: à vista R$ 1.385 ou 3x de R$ 486 (nov, dez, jan). Boleto ou cartão.', meta: 'IA · hoje 13:39' },
    { dir: 'out', text: 'Perfeito, quero em 3x', meta: 'Patrícia · hoje 13:43' },
    { dir: 'in',  text: 'Ótimo! Segue seu link individual: cec.app/rematricula/8fa21c — é só confirmar os dados e assinar.', meta: 'IA · hoje 13:44' },
    { dir: 'out', text: 'Assinei agora, valeu!', meta: 'Patrícia · hoje 14:06' }
  ],

  chatIntel: [
    { label: 'Intenção detectada',  value: 'Interessada · quer parcelar' },
    { label: 'Etapa atual',         value: 'Assinatura pendente' },
    { label: 'Tentativas da régua', value: '3 de 5' },
    { label: 'Sentimento',          value: 'Positivo' }
  ],

  handoff: [
    { label: 'Assumir conversa',          variant: 'btn--orange' },
    { label: 'Devolver para a IA',        variant: '' },
    { label: 'Encerrar contatos (opt-out)', variant: 'btn--danger' }
  ],

  campaignStats: [
    { label: 'Na fila agora',      value: '34',  sub: 'próximo lote 15:00' },
    { label: 'Mensagens por hora', value: '18',  sub: 'limite 25/h · 150/dia' },
    { label: 'Contatadas',         value: '318', sub: 'de 412 · 77% da base' },
    { label: 'Enviadas hoje',      value: '128', sub: '3 falhas em retry' }
  ],

  queue: [
    { time: '15:00', parent: 'Elaine Duarte',    student: 'Bruna · 4º ano B',   attempt: 'Tentativa 1', kind: 'Contato inicial' },
    { time: '15:02', parent: 'Rafael Monteiro',  student: 'Théo · Infantil IV', attempt: 'Tentativa 1', kind: 'Contato inicial' },
    { time: '15:03', parent: 'Simone Alencar',   student: 'Davi · 6º ano A',    attempt: 'Tentativa 3', kind: 'Condições de pagamento' },
    { time: '15:05', parent: 'Carla Peixoto',    student: 'Alice · 2º ano A',   attempt: 'Tentativa 2', kind: 'Lembrete leve' },
    { time: '15:06', parent: 'Wagner Belo',      student: 'Iago · 8º ano B',    attempt: 'Tentativa 3', kind: 'Condições de pagamento' },
    { time: '15:08', parent: 'Tatiane Moreira',  student: 'Cauã · 5º ano B',    attempt: 'Tentativa 1', kind: 'Contato inicial' }
  ],

  throughput: [
    { h: '08h', n: 34 }, { h: '09h', n: 62 }, { h: '10h', n: 71 }, { h: '11h', n: 58 },
    { h: '12h', n: 12 }, { h: '13h', n: 44 }, { h: '14h', n: 68 }, { h: '15h', n: 18 }
  ],
  throughputMax: 75,

  guards: [
    { label: 'Janela de envio',          value: '08:00 – 19:30' },
    { label: 'Intervalo entre disparos', value: '40 – 90 s' },
    { label: 'Teto por hora',            value: '25 mensagens' },
    { label: 'Teto diário',              value: '150 mensagens' },
    { label: 'Conexão do WhatsApp',      value: 'Estável · health check ok' },
    { label: 'Fila persistente',         value: 'Ativa · nada se perde na queda' }
  ],

  attended: [
    { time: 'hoje 14:12',  parent: 'Patrícia Andrade', student: 'Lucas · 5º ano A',   by: 'IA',     outcome: 'Assinou',        tone: 'ok' },
    { time: 'hoje 13:58',  parent: 'Marcos Tavares',   student: 'Pedro · 7º ano A',   by: 'equipe', outcome: 'Em negociação',  tone: 'warn' },
    { time: 'hoje 13:40',  parent: 'Juliana Reis',     student: 'Sofia · Infantil V', by: 'IA',     outcome: 'Interessada',    tone: 'info' },
    { time: 'hoje 11:22',  parent: 'Cleide Barbosa',   student: 'Miguel · 8º ano A',  by: 'equipe', outcome: 'Link reenviado', tone: 'info' },
    { time: 'hoje 09:47',  parent: 'Rogério Lima',     student: 'Ana · 2º ano B',     by: 'IA',     outcome: 'Concluída',      tone: 'ok' },
    { time: 'ontem 16:05', parent: 'Sandra Vieira',    student: 'Isabela · 9º ano A', by: 'IA',     outcome: 'Sem interesse',  tone: 'mute' }
  ],

  novasStats: [
    { label: 'Pré-matrículas',          value: '38', sub: 'formulário público preenchido' },
    { label: 'Em atendimento',          value: '21', sub: 'conversando com a IA ou equipe' },
    { label: 'Matrículas efetivadas',   value: '17', sub: 'contrato assinado e pago' },
    { label: 'Cadastradas pela equipe', value: '9',  sub: 'visita presencial ou telefone' }
  ],

  novasFilters: ['Todas', 'Pré-matrícula', 'Matrícula em andamento', 'Efetivada'],

  novas: [
    { id: 'rafael-monteiro',  parent: 'Rafael Monteiro',  phone: '(83) 99220-7781', student: 'Théo Monteiro',    target: 'Infantil IV · manhã', stage: 'Pré-matrícula',          tone: 'warn', origin: 'Site',             when: 'hoje 14:20' },
    { id: 'bianca-furtado',   parent: 'Bianca Furtado',   phone: '(83) 98866-1204', student: 'Manuela Furtado',  target: '1º ano · manhã',      stage: 'Matrícula em andamento', tone: 'info', origin: 'Indicação',        when: 'hoje 13:05' },
    { id: 'otavio-serrano',   parent: 'Otávio Serrano',   phone: '(83) 99411-3390', student: 'Enzo Serrano',     target: '4º ano · tarde',      stage: 'Pré-matrícula',          tone: 'warn', origin: 'Instagram',        when: 'hoje 11:48' },
    { id: 'larissa-coelho',   parent: 'Larissa Coelho',   phone: '(83) 98123-5566', student: 'Helena Coelho',    target: '2º ano · manhã',      stage: 'Efetivada',              tone: 'ok',   origin: 'Visita presencial', when: 'ontem 16:32' },
    { id: 'diego-ramalho',    parent: 'Diego Ramalho',    phone: '(83) 99677-8820', student: 'Arthur Ramalho',   target: '6º ano · manhã',      stage: 'Matrícula em andamento', tone: 'info', origin: 'Site',             when: 'ontem 15:10' },
    { id: 'priscila-vasques', parent: 'Priscila Vasques', phone: '(83) 98330-4417', student: 'Laura Vasques',    target: 'Infantil V · manhã',  stage: 'Efetivada',              tone: 'ok',   origin: 'Indicação',        when: 'ontem 09:58' }
  ],

  novaForm: [
    { label: 'Nome do responsável', ph: 'Nome completo' },
    { label: 'WhatsApp',            ph: '(83) 9 0000-0000' },
    { label: 'Nome do aluno',       ph: 'Nome completo' },
    { label: 'Série pretendida',    ph: 'Selecionar série' },
    { label: 'Turno',               ph: 'Manhã ou tarde' },
    { label: 'Origem do contato',   ph: 'Visita, telefone, indicação…' }
  ],

  matriculadosStats: [
    { label: 'Total matriculados', value: '91',         sub: '74 rematrículas · 17 matrículas novas' },
    { label: 'Receita confirmada', value: 'R$ 47,4 mil', sub: 'pagamentos compensados' },
    { label: 'Ticket médio',       value: 'R$ 521',     sub: 'por família' },
    { label: 'Concluídas hoje',    value: '11',         sub: 'assinatura + pagamento' }
  ],

  matriculadosFilters: ['Todos', 'Rematrícula', 'Matrícula nova'],

  matriculados: [
    { id: 'patricia-andrade', parent: 'Patrícia Andrade', student: 'Lucas Andrade',    klass: '6º ano · 2027',      type: 'Rematrícula',    tone: 'info', plan: '3x R$ 486',        when: 'hoje 14:12' },
    { id: 'rogerio-lima',     parent: 'Rogério Lima',     student: 'Ana Lima',         klass: '3º ano · 2027',      type: 'Rematrícula',    tone: 'info', plan: 'À vista R$ 1.205', when: 'hoje 09:47' },
    { id: 'larissa-coelho',   parent: 'Larissa Coelho',   student: 'Helena Coelho',    klass: '2º ano · 2027',      type: 'Matrícula nova', tone: 'new',  plan: '3x R$ 414',        when: 'ontem 16:32' },
    { id: 'priscila-vasques', parent: 'Priscila Vasques', student: 'Laura Vasques',    klass: 'Infantil V · 2027',  type: 'Matrícula nova', tone: 'new',  plan: 'À vista R$ 957',   when: 'ontem 09:58' },
    { id: 'elaine-duarte',    parent: 'Elaine Duarte',    student: 'Bruna Duarte',     klass: '5º ano · 2027',      type: 'Rematrícula',    tone: 'info', plan: '2x R$ 637',        when: 'ontem 08:21' },
    { id: 'fabio-nogueira',   parent: 'Fábio Nogueira',   student: 'Heitor Nogueira',  klass: '2º ano · 2027',      type: 'Rematrícula',    tone: 'info', plan: '3x R$ 381',        when: '05/09 17:40' },
    { id: 'carla-peixoto',    parent: 'Carla Peixoto',    student: 'Alice Peixoto',    klass: '3º ano · 2027',      type: 'Matrícula nova', tone: 'new',  plan: '3x R$ 402',        when: '05/09 11:15' }
  ],

  signItems: [
    { label: 'Contrato de prestação de serviços 2027', sub: 'versão v3 · 6 páginas', status: 'Assinado' },
    { label: 'Termo de uso de imagem',                 sub: 'opcional',              status: 'Assinado' },
    { label: 'Regimento interno',                      sub: 'aceite eletrônico',     status: 'Aceito' }
  ],

  evidence: [
    { label: 'IP do aceite',     value: '177.42.118.204' },
    { label: 'Dispositivo',      value: 'Android · Chrome' },
    { label: 'Data e hora',      value: '07/09/2026 14:12' },
    { label: 'Hash do documento', value: '9f2c…a41b' }
  ],

  payMethods: [
    { label: 'Cartão de crédito', sub: 'até 3x sem juros · confirmação na hora', badge: 'Recomendado', solid: true },
    { label: 'Boleto bancário',   sub: 'vencimento em 3 dias úteis',             badge: 'Disponível' },
    { label: 'Pix',               sub: 'confirmação automática',                 badge: 'Disponível' }
  ],

  installments: [
    { label: 'Parcela 1 · novembro', value: 'R$ 486,00', status: 'Pago',     tone: 'ok' },
    { label: 'Parcela 2 · dezembro', value: 'R$ 486,00', status: 'A vencer', tone: 'mute' },
    { label: 'Parcela 3 · janeiro',  value: 'R$ 486,00', status: 'A vencer', tone: 'mute' }
  ],

  series: [
    { from: 'Infantil IV', to: 'Infantil V', turno: 'Manhã',         mensal: 'R$ 968',   avista: 'R$ 891',   vagas: '12 vagas' },
    { from: 'Infantil V',  to: '1º ano',     turno: 'Manhã',         mensal: 'R$ 1.040', avista: 'R$ 957',   vagas: '8 vagas' },
    { from: '1º ano',      to: '2º ano',     turno: 'Manhã / Tarde', mensal: 'R$ 1.185', avista: 'R$ 1.090', vagas: '6 vagas' },
    { from: '2º ano',      to: '3º ano',     turno: 'Manhã / Tarde', mensal: 'R$ 1.242', avista: 'R$ 1.143', vagas: '9 vagas' },
    { from: '3º ano',      to: '4º ano',     turno: 'Manhã / Tarde', mensal: 'R$ 1.310', avista: 'R$ 1.205', vagas: '4 vagas' },
    { from: '4º ano',      to: '5º ano',     turno: 'Manhã',         mensal: 'R$ 1.386', avista: 'R$ 1.275', vagas: '7 vagas' },
    { from: '5º ano',      to: '6º ano',     turno: 'Manhã',         mensal: 'R$ 1.458', avista: 'R$ 1.341', vagas: '11 vagas' },
    { from: '6º ano',      to: '7º ano',     turno: 'Manhã',         mensal: 'R$ 1.520', avista: 'R$ 1.398', vagas: '5 vagas' },
    { from: '7º ano',      to: '8º ano',     turno: 'Manhã',         mensal: 'R$ 1.584', avista: 'R$ 1.457', vagas: '3 vagas' },
    { from: '8º ano',      to: '9º ano',     turno: 'Manhã',         mensal: 'R$ 1.642', avista: 'R$ 1.510', vagas: '6 vagas' },
    { from: '9º ano',      to: '1ª série',   turno: 'Manhã',         mensal: 'R$ 1.780', avista: 'R$ 1.637', vagas: '10 vagas' }
  ],

  conditions: [
    { label: 'À vista',               value: 'Desconto de 8%',        sub: 'Pagamento único até o vencimento de novembro' },
    { label: 'Parcelamento máximo',   value: '3x sem juros',          sub: 'Última parcela sempre em janeiro' },
    { label: 'Formas aceitas',        value: 'Cartão · Boleto · Pix', sub: 'Cartão confirma na hora; boleto em até 3 dias úteis' },
    { label: 'Desconto de irmãos',    value: '10% no segundo filho',  sub: 'Aplicado sobre a menor mensalidade' },
    { label: 'Bolsa e negociação',    value: 'Análise manual',        sub: 'Sempre gera handoff para a equipe' },
    { label: 'Multa por atraso',      value: '2% + 1% ao mês',        sub: 'Conforme contrato 2027' }
  ],

  campaignConfig: [
    { label: 'Campanha ativa',       value: 'Rematrícula 2027' },
    { label: 'Período',              value: '01/09 – 20/09/2026' },
    { label: 'Base elegível',        value: '412 famílias' },
    { label: 'Janela de envio',      value: '08:00 – 19:30' },
    { label: 'Teto por hora',        value: '25 mensagens' },
    { label: 'Teto diário',          value: '150 mensagens' },
    { label: 'Tentativas da régua',  value: '5 contatos' },
    { label: 'Reenvio de link',      value: 'Após 48h sem conclusão' },
    { label: 'Contrato vigente',     value: 'Versão v3' }
  ],

  docsConfig: [
    { label: 'Contrato de prestação de serviços', value: 'v3 · 6 páginas',  sub: 'Assinatura eletrônica obrigatória' },
    { label: 'Termo de uso de imagem',            value: 'v1 · 1 página',   sub: 'Aceite opcional' },
    { label: 'Regimento interno',                 value: 'v2 · 14 páginas', sub: 'Aceite eletrônico obrigatório' },
    { label: 'Lista de material',                 value: 'PDF por série',   sub: 'Anexado ao final da jornada' }
  ],

  steps: ['Dados', 'Contrato', 'Assinatura', 'Pagamento', 'Pronto'],

  linkFields: [
    { label: 'Responsável',   value: 'Patrícia Andrade' },
    { label: 'Telefone',      value: '(83) 99812-4471' },
    { label: 'Aluno',         value: 'Lucas Andrade' },
    { label: 'Turma atual',   value: '5º ano A' },
    { label: 'Próxima turma', value: '6º ano · 2027' },
    { label: 'E-mail',        value: 'patricia.andrade@email.com' }
  ],

  mobileFields: [
    { label: 'Responsável',   value: 'Patrícia Andrade' },
    { label: 'Aluno',         value: 'Lucas Andrade' },
    { label: 'Próxima turma', value: '6º ano · 2027' }
  ],

  plans: [
    { label: 'À vista',      sub: 'pagamento único em novembro',    price: 'R$ 1.385' },
    { label: '3x sem juros', sub: 'novembro · dezembro · janeiro',  price: 'R$ 486' },
    { label: '2x sem juros', sub: 'dezembro · janeiro',             price: 'R$ 729' }
  ],

  preFields: [
    { label: 'Nome do responsável',       ph: 'Como podemos te chamar?' },
    { label: 'WhatsApp',                  ph: '(83) 9 0000-0000' },
    { label: 'Nome do aluno',             ph: 'Nome completo' },
    { label: 'Série pretendida em 2027',  ph: 'Ex.: 3º ano' },
    { label: 'Escola atual',              ph: 'Opcional' },
    { label: 'Turno de preferência',      ph: 'Manhã ou tarde' }
  ],

  preBenefits: [
    'Atendimento pelo WhatsApp no mesmo dia',
    'Valores, turnos e vagas sem precisar ligar',
    'Visita agendada pela própria conversa',
    'Matrícula concluída online, com assinatura digital'
  ]
};

/** Iniciais para o avatar ("Patrícia Andrade" → "PA"). */
export function initials(name) {
  return String(name || '')
    .split(/\s+/).filter(Boolean).slice(0, 2)
    .map(function (part) { return part[0].toUpperCase(); })
    .join('');
}

/** Localiza a família de /familias/:id nas três listas e devolve um registro
    normalizado. Sem correspondência, cai na família de demonstração. */
export function findFamily(id) {
  const fam = DATA.families.find((f) => f.id === id);
  if (fam) return { ...fam, origin: 'Rematrícula' };

  const nova = DATA.novas.find((n) => n.id === id);
  if (nova) {
    return {
      id: nova.id, parent: nova.parent, phone: nova.phone, student: nova.student,
      klass: nova.target, status: nova.stage, tone: nova.tone, tries: 1,
      next: 'Atendimento em andamento', origin: 'Matrícula nova'
    };
  }

  const mat = DATA.matriculados.find((m) => m.id === id);
  if (mat) {
    return {
      id: mat.id, parent: mat.parent, phone: DATA.families[0].phone, student: mat.student,
      klass: mat.klass, status: 'Concluída', tone: 'ok', tries: 3,
      next: '—', origin: mat.type
    };
  }

  return { ...DATA.families[0], origin: 'Rematrícula' };
}
