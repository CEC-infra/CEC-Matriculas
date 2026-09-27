param(
  [string]$CsvPath = (Join-Path $PSScriptRoot '..\importacao\alunos - alunos.csv.csv'),
  [int]$BatchSize = 25
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-EnvValue([string]$name) {
  $entry = Get-Content (Join-Path $projectRoot '.env') | Where-Object { $_ -like "$name=*" } | Select-Object -First 1
  if (-not $entry) { throw "$name ausente em .env" }
  return $entry.Substring($name.Length + 1)
}

function Sql([object]$value) {
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return 'null' }
  return "'" + ([string]$value).Replace("'", "''") + "'"
}

function SqlJson([object]$value) {
  return (Sql ($value | ConvertTo-Json -Compress -Depth 6)) + '::jsonb'
}

function Digits([object]$value) {
  if ($null -eq $value) { return '' }
  return [regex]::Replace([string]$value, '\D', '')
}

function Cpf([object]$value) {
  $digits = Digits $value
  if ($digits.Length -eq 11) { return $digits }
  return $null
}

function Phone([object]$value) {
  $digits = Digits $value
  if ($digits.Length -in 10, 11) { return "+55$digits" }
  if ($digits.Length -in 12, 13 -and $digits.StartsWith('55')) { return "+$digits" }
  return $null
}

function DateValue([object]$value) {
  if ([string]::IsNullOrWhiteSpace([string]$value)) { return $null }
  $date = [datetime]::MinValue
  if ([datetime]::TryParse([string]$value, [Globalization.CultureInfo]::GetCultureInfo('pt-BR'), [Globalization.DateTimeStyles]::None, [ref]$date)) {
    return $date.ToString('yyyy-MM-dd')
  }
  return $null
}

function AgeYears([object]$value) {
  $match = [regex]::Match([string]$value, '\d+')
  if ($match.Success) { return $match.Value }
  return $null
}

function AgeMonths([object]$value) {
  $match = [regex]::Match([string]$value, '(\d+)\s*mes')
  if ($match.Success -and [int]$match.Groups[1].Value -le 11) { return $match.Groups[1].Value }
  return $null
}

function BoolValue([object]$value) {
  $text = ([string]$value).Trim().ToUpperInvariant()
  if ($text -in 'SIM', 'S', 'TRUE', '1') { return 'true' }
  if ($text -in 'NÃO', 'NAO', 'N', 'FALSE', '0') { return 'false' }
  return 'null'
}

function GradeCode([string]$course) {
  if ($course -match '^GRUPO\s+([1-5])') {
    return @{ '1' = 'grupo_1'; '2' = 'grupo_2'; '3' = 'grupo_3'; '4' = 'infantil_4'; '5' = 'infantil_5' }[$Matches[1]]
  }
  if ($course -match '^([1-9])º\s+ANO') { return "ano_$($Matches[1])" }
  throw "Curso sem mapeamento: $course"
}

function Shift([string]$value) {
  if ($value -eq 'MATUTINO') { return 'manha' }
  if ($value -eq 'VESPERTINO') { return 'tarde' }
  throw "Turno sem mapeamento: $value"
}

$accessToken = Get-EnvValue 'SUPABASE_ACCESS_TOKEN'
$uri = 'https://mcp.supabase.com/mcp?project_ref=uczxuaaojixapkdlayph&features=database'
$headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json, text/event-stream' }
$init = @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ protocolVersion='2025-03-26'; capabilities=@{}; clientInfo=@{ name='cec-legacy-import'; version='1.0' } } } | ConvertTo-Json -Compress -Depth 8
$session = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -ContentType 'application/json' -Body $init -UseBasicParsing
$headers['Mcp-Session-Id'] = $session.Headers['mcp-session-id']
$script:requestId = 2

function Invoke-Sql([string]$query) {
  $body = @{ jsonrpc='2.0'; id=$script:requestId; method='tools/call'; params=@{ name='execute_sql'; arguments=@{ query=$query } } } | ConvertTo-Json -Compress -Depth 12
  $script:requestId++
  $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -ContentType 'application/json' -Body $body -UseBasicParsing
  $payload = $response.Content | ConvertFrom-Json
  if ($payload.isError -or $payload.result.isError) {
    $errorText = @($payload.result.content | ForEach-Object { $_.text }) -join "`n"
    $diagnostic = if ($errorText -match '(?i)Key \(([^)]+)\)=') { "conflito de unicidade na coluna $($Matches[1])" } elseif ($errorText -match '(?im)^ERROR:\s*([^\r\n]+)') { $Matches[1] } elseif ($errorText -match '(?im)^DETAIL:\s*([^\r\n]+)') { $Matches[1] } else {
      $fields = [regex]::Matches($errorText, '(?i)\\?"(?:message|code|hint|constraint)\\?"\s*:\s*\\?"([^"\\]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
      if ($fields) { $fields -join '; ' } else { 'erro retornado pelo banco (detalhes com dados de origem foram suprimidos)' }
    }
    throw "A consulta de importação falhou: $diagnostic"
  }
}

function GuardianSql($name, $cpf, $email, $phone, $address, $rg, $issuer, $birthDate, $profession, $religion, $deceased, $metadata, $variable) {
  $cpfSql = Sql $cpf
  $phoneSql = Sql $phone
  return @"
  insert into public.guardians (full_name, cpf, email, phone, address, rg, rg_issuer, birth_date, profession, religion, deceased, legacy_metadata)
  values (
    $(Sql $name), $cpfSql, $(Sql $email),
    case when $phoneSql is null or exists (select 1 from public.guardians x where x.phone = $phoneSql and ($cpfSql is null or x.cpf is distinct from $cpfSql)) then null else $phoneSql end,
    $(Sql $address), $(Sql $rg), $(Sql $issuer), $(Sql $birthDate), $(Sql $profession), $(Sql $religion), $deceased, $(SqlJson $metadata)
  )
  on conflict (cpf) do update set
    full_name = excluded.full_name,
    email = coalesce(excluded.email, public.guardians.email),
    phone = coalesce(excluded.phone, public.guardians.phone),
    address = coalesce(excluded.address, public.guardians.address),
    rg = coalesce(excluded.rg, public.guardians.rg),
    rg_issuer = coalesce(excluded.rg_issuer, public.guardians.rg_issuer),
    birth_date = coalesce(excluded.birth_date, public.guardians.birth_date),
    profession = coalesce(excluded.profession, public.guardians.profession),
    religion = coalesce(excluded.religion, public.guardians.religion),
    deceased = coalesce(excluded.deceased, public.guardians.deceased),
    legacy_metadata = excluded.legacy_metadata
  returning id into $variable;
"@
}

function LinkSql($guardianVariable, [string]$relationship, [bool]$financial, [bool]$primary) {
  $financialSql = $financial.ToString().ToLowerInvariant()
  $primarySql = $primary.ToString().ToLowerInvariant()
  return @"
  if $guardianVariable is not null then
    insert into public.student_guardians (student_id, guardian_id, relationship, is_financial, is_primary_contact)
    values (v_student, $guardianVariable, $(Sql $relationship), $financialSql, $primarySql)
    on conflict (student_id, guardian_id) do update set
      relationship = case when position(excluded.relationship in public.student_guardians.relationship) > 0 then public.student_guardians.relationship else concat_ws(' e ', public.student_guardians.relationship, excluded.relationship) end,
      is_financial = public.student_guardians.is_financial or excluded.is_financial,
      is_primary_contact = public.student_guardians.is_primary_contact or excluded.is_primary_contact;
  end if;
"@
}

$rows = Import-Csv -LiteralPath (Resolve-Path $CsvPath)
if (-not $rows.Count) { throw 'O CSV não contém registros.' }

$classes = $rows | Group-Object { "$($_.Curso)|$($_.Turma)|$($_.Turno)|$($_.UNIDADE)|$($_.'UNIDADE | CIDADE')|$($_.'UNIDADE | ESTADO')" } | ForEach-Object {
  $row = $_.Group[0]
  [PSCustomObject]@{ grade_code=(GradeCode $row.Curso); name=$row.Turma; shift=(Shift $row.Turno); campus=$row.UNIDADE; city=$row.'UNIDADE | CIDADE'; state=$row.'UNIDADE | ESTADO' }
}
$classValues = $classes | ForEach-Object { "($(Sql $_.grade_code), $(Sql $_.name), $(Sql $_.shift), $(Sql $_.campus), $(Sql $_.city), $(Sql $_.state))" }

Invoke-Sql @"
insert into public.campaigns (name, kind, academic_year, status, starts_on, ends_on, queue_paused)
values ('Base escolar importada 2026', 'rematricula', 2026, 'encerrada', '2026-01-01', '2026-12-31', true)
on conflict (name) do update set status = excluded.status, queue_paused = excluded.queue_paused;
with source (grade_code, name, shift, campus_name, campus_city, campus_state) as (values
$($classValues -join ",`n")
)
insert into public.classes (grade_id, academic_year, name, shift, campus_name, campus_city, campus_state)
select g.id, 2026, s.name, s.shift::public.shift, s.campus_name, s.campus_city, s.campus_state
from source s join public.grades g on g.code = s.grade_code
on conflict (academic_year, name) do update set
  grade_id = excluded.grade_id, shift = excluded.shift, campus_name = excluded.campus_name,
  campus_city = excluded.campus_city, campus_state = excluded.campus_state;
"@

for ($offset = 0; $offset -lt $rows.Count; $offset += $BatchSize) {
  $batch = @($rows | Select-Object -Skip $offset -First $BatchSize)
  $statements = New-Object System.Collections.Generic.List[string]
  foreach ($row in $batch) {
    $externalRef = ('legacy-2026-{0:d4}' -f ($offset + $statements.Count + 1))
    $primaryMeta = @{ role='responsavel'; source_phone=$row.Telefones; source_cpf=$row.'CPF Responsável'; source_address=$row.'Endereço do responsável' }
    $fatherMeta = @{ role='pai'; source_phone=$row.'Telefone pai'; source_cpf=$row.'CPF da pai'; source_birth_date=$row.'Dt. nasc. pai' }
    $motherMeta = @{ role='mae'; source_phone=$row.'Telefone mãe'; source_cpf=$row.'CPF da mãe'; source_birth_date=$row.'Dt. nasc. mãe' }
    $courseCode = GradeCode $row.Curso
    $statement = @"
  v_student := null; v_primary := null; v_father := null; v_mother := null; v_class := null; v_grade := null;
  insert into public.students (full_name, external_ref, rg, social_name, gender, email, phone, reported_age_years, reported_age_months)
  values ($(Sql $row.'Nome do aluno'), $(Sql $externalRef), $(Sql $row.'RG do aluno'), $(Sql $row.'NOME SOCIAL'), $(Sql $row.'Sexo do Aluno'), $(Sql $row.'E-mail aluno'), $(Sql (Phone $row.'Telefone do aluno')), $(Sql (AgeYears $row.'Idade (Anos)')), $(Sql (AgeMonths $row.'Idade (Anos e meses)')))
  on conflict (external_ref) do update set full_name = excluded.full_name, rg = excluded.rg, social_name = excluded.social_name, gender = excluded.gender, email = excluded.email, phone = excluded.phone, reported_age_years = excluded.reported_age_years, reported_age_months = excluded.reported_age_months
  returning id into v_student;
$(GuardianSql $row.'Nome do Responsável' (Cpf $row.'CPF Responsável') $null (Phone $row.Telefones) $row.'Endereço do responsável' $null $null $null $null $null 'null' $primaryMeta 'v_primary')
$(if ($row.'Nome pai') { GuardianSql $row.'Nome pai' (Cpf $row.'CPF da pai') $row.'E-mail pai' (Phone $row.'Telefone pai') $row.'ENDEREÇO | PAI ALUNO' $row.'RG da pai' $row.'órgão exp. RG da pai' (DateValue $row.'Dt. nasc. pai') $row.'Profissão do pai' $row.'Religião do pai' (BoolValue $row.'Falecido(a) do pai') $fatherMeta 'v_father' } else { '' })
$(if ($row.'Nome mãe') { GuardianSql $row.'Nome mãe' (Cpf $row.'CPF da mãe') $row.'E-mail mãe' (Phone $row.'Telefone mãe') $row.'ENDEREÇO | MÃE ALUNO' $row.'RG da mãe' $row.'órgão exp. RG da mãe' (DateValue $row.'Dt. nasc. mãe') $row.'Profissão da mãe' $row.'Religião da mãe' (BoolValue $row.'Falecido(a) da mãe') $motherMeta 'v_mother' } else { '' })
  select c.id, c.grade_id into v_class, v_grade from public.classes c where c.academic_year = 2026 and c.name = $(Sql $row.Turma);
  if v_class is null then raise exception 'Turma da importação não encontrada'; end if;
  update public.students set current_class_id = v_class where id = v_student;
$(LinkSql 'v_primary' 'responsável' $true $true)
$(LinkSql 'v_father' 'pai' $false $false)
$(LinkSql 'v_mother' 'mãe' $false $false)
  insert into public.enrollments (campaign_id, student_id, guardian_id, origin, from_class_id, target_grade_id, target_class_id, target_shift, status, source_enrollment_status, source_class_status, legacy_metadata)
  values ((select id from public.campaigns where name = 'Base escolar importada 2026'), v_student, v_primary, 'outro', v_class, v_grade, v_class, $(Sql (Shift $row.Turno))::public.shift, 'concluida', $(Sql $row.'Status da matrícula'), $(Sql $row.'Situação do aluno na turma'), $(SqlJson $row))
  on conflict (campaign_id, student_id) do update set guardian_id = excluded.guardian_id, from_class_id = excluded.from_class_id, target_grade_id = excluded.target_grade_id, target_class_id = excluded.target_class_id, target_shift = excluded.target_shift, source_enrollment_status = excluded.source_enrollment_status, source_class_status = excluded.source_class_status, legacy_metadata = excluded.legacy_metadata;
"@
    $statements.Add($statement)
  }
  $batchSql = "do `$import`$ declare v_student uuid; v_primary uuid; v_father uuid; v_mother uuid; v_class uuid; v_grade uuid; begin`n$($statements -join "`n")`nend `$import`$;"
  Invoke-Sql $batchSql
  Write-Output "Imported $([Math]::Min($offset + $batch.Count, $rows.Count)) of $($rows.Count) students."
}

Write-Output "Legacy import completed: $($rows.Count) students."
