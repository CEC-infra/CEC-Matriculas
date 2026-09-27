param(
  [string]$CsvPath = (Join-Path $PSScriptRoot '..\importacao\alunos - alunos.csv.csv'),
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\importacao\auditoria-dados-nao-importados.csv')
)

$ErrorActionPreference = 'Stop'

function Get-EnvValue([string]$name) {
  $envPath = Join-Path $PSScriptRoot '..\.env'
  $line = Get-Content -LiteralPath $envPath | Where-Object { $_ -match "^$([regex]::Escape($name))=" } | Select-Object -First 1
  if (-not $line) { throw "Variável $name não encontrada no .env." }
  return $line.Substring($line.IndexOf('=') + 1).Trim('"')
}

function Invoke-AuditSql([string]$query) {
  $queryJson = $query | ConvertTo-Json -Compress
  $body = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"execute_sql","arguments":{"query":' + $queryJson + '}}}'
  $response = Invoke-WebRequest -Uri $script:mcpUri -Method Post -Headers $script:mcpHeaders -ContentType 'application/json' -Body $body -UseBasicParsing
  $payload = $response.Content | ConvertFrom-Json
  if ($payload.result.isError) { throw 'A consulta de auditoria ao Supabase falhou.' }
  $content = @($payload.result.content | ForEach-Object { $_.text }) -join "`n"
  $match = [regex]::Match($content, '(?s)<untrusted-data-[^>]+>\s*(\[.*?\])\s*</untrusted-data-[^>]+>')
  if (-not $match.Success) { $match = [regex]::Match($content, '(?s)(\[\s*\{.*\}\s*\])') }
  if (-not $match.Success) { throw 'O Supabase retornou um formato de auditoria inesperado.' }
  $json = $match.Groups[1].Value -replace '\\"', '"'
  return @($json | ConvertFrom-Json)
}

$rows = @(Import-Csv -LiteralPath (Resolve-Path $CsvPath))
if (-not $rows.Count) { throw 'O CSV não contém registros.' }
$sourceFieldCount = @($rows[0].PSObject.Properties).Count

$token = Get-EnvValue 'SUPABASE_ACCESS_TOKEN'
$script:mcpUri = 'https://mcp.supabase.com/mcp?project_ref=uczxuaaojixapkdlayph&features=database'
$script:mcpHeaders = @{ Authorization = "Bearer $token"; Accept = 'application/json, text/event-stream' }
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cec-legacy-audit","version":"1.0"}}}'
$session = Invoke-WebRequest -Uri $script:mcpUri -Method Post -Headers $script:mcpHeaders -ContentType 'application/json' -Body $init -UseBasicParsing
$script:mcpHeaders['Mcp-Session-Id'] = $session.Headers['mcp-session-id']

$dbRows = Invoke-AuditSql @"
select
  s.external_ref,
  exists (
    select 1 from public.enrollments e
    join public.campaigns c on c.id = e.campaign_id
    where e.student_id = s.id and c.name = 'Base escolar importada 2026'
  ) as matricula_presente,
  s.current_class_id is not null as turma_atual_presente,
  exists (
    select 1 from public.student_guardians sg
    where sg.student_id = s.id and sg.is_primary_contact
  ) as responsavel_principal_presente,
  coalesce((
    select count(*) from public.enrollments e
    join public.campaigns c on c.id = e.campaign_id
    cross join lateral jsonb_object_keys(e.legacy_metadata) as k(key)
    where e.student_id = s.id and c.name = 'Base escolar importada 2026'
  ), 0) as campos_de_origem_preservados
from public.students s
where s.external_ref like 'legacy-2026-%'
order by s.external_ref;
"@

$byReference = @{}
foreach ($dbRow in $dbRows) { $byReference[$dbRow.external_ref] = $dbRow }

$issues = New-Object System.Collections.Generic.List[object]
for ($index = 0; $index -lt $rows.Count; $index++) {
  $reference = 'legacy-2026-{0:d4}' -f ($index + 1)
  $row = $rows[$index]
  $dbRow = $byReference[$reference]
  $reasons = New-Object System.Collections.Generic.List[string]
  if (-not $dbRow) {
    $reasons.Add('registro_de_aluno_ausente')
  } else {
    if (-not $dbRow.matricula_presente) { $reasons.Add('matricula_importada_ausente') }
    if (-not $dbRow.turma_atual_presente) { $reasons.Add('turma_atual_ausente') }
    if (-not $dbRow.responsavel_principal_presente) { $reasons.Add('responsavel_principal_ausente') }
    if ([int]$dbRow.campos_de_origem_preservados -lt $sourceFieldCount) { $reasons.Add('campos_originais_incompletos') }
  }
  if ($reasons.Count) {
    $issues.Add([PSCustomObject]@{
      linha_csv = $index + 2
      referencia_importacao = $reference
      nome_aluno = $row.'Nome do aluno'
      curso = $row.Curso
      turma = $row.Turma
      motivo = $reasons -join '; '
    })
  }
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
if ($issues.Count) {
  $issues | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8BOM
} else {
  'linha_csv,referencia_importacao,nome_aluno,curso,turma,motivo' | Set-Content -LiteralPath $OutputPath -Encoding utf8BOM
}

Write-Output "Audited $($rows.Count) CSV records against $($dbRows.Count) imported students."
Write-Output "Records with missing or incomplete import data: $($issues.Count)."
Write-Output "Report written to: $OutputPath"
