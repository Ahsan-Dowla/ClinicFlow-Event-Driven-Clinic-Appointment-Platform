docker pull httpd:2.4-alpine | Out-Null
$ErrorActionPreference = 'Stop'
if (-not (Test-Path .env.example)) { throw "Run this from the project root" }

function New-Secret([int]$Length = 24) {
  $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  $bytes = New-Object byte[] $Length
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function New-BcryptHash([string]$Password) {
  $raw  = & docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 u $Password 2>$null
  $line = @($raw) | Where-Object { $_ -match '^u:\$2[aby]\$' } | Select-Object -First 1
  if (-not $line) { throw "BCrypt generation failed" }
  ($line.Trim() -split ':', 2)[1].Replace('$2y$', '$2a$')
}

$adminPw = New-Secret 16
$doc1Pw  = New-Secret 16
$doc2Pw  = New-Secret 16

$values = [ordered]@{
  MYSQL_ROOT_PASSWORD              = New-Secret 24
  MYSQL_APP_PASSWORD               = New-Secret 24
  RABBITMQ_PASSWORD                = New-Secret 24
  JWT_SECRET                       = New-Secret 64
  INITIAL_ADMIN_EMAIL              = 'admin@clinic.local'
  INITIAL_DOCTOR_ONE_EMAIL         = 'doctor1@clinic.local'
  INITIAL_DOCTOR_TWO_EMAIL         = 'doctor2@clinic.local'
  INITIAL_ADMIN_PASSWORD_HASH      = "'" + (New-BcryptHash $adminPw) + "'"
  INITIAL_DOCTOR_ONE_PASSWORD_HASH = "'" + (New-BcryptHash $doc1Pw) + "'"
  INITIAL_DOCTOR_TWO_PASSWORD_HASH = "'" + (New-BcryptHash $doc2Pw) + "'"
  HTTP_PORT                        = '8092'
  RABBITMQ_MANAGEMENT_PORT         = '15673'
  FRONTEND_ORIGIN_DOCKER           = 'http://localhost:8092'
}
$values['DB_PASSWORD'] = $values['MYSQL_ROOT_PASSWORD']

if (Test-Path .env) { Move-Item .env .env.old -Force }

$lines = Get-Content .env.example | ForEach-Object {
  if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=' -and $values.Contains($Matches[1])) {
    "$($Matches[1])=$($values[$Matches[1]])"
  } else { $_ }
}
[IO.File]::WriteAllLines((Join-Path (Get-Location) '.env'), $lines, (New-Object Text.UTF8Encoding $false))

if (Select-String -Path .env -Pattern 'replace-with' -Quiet) { throw ".env still has placeholders" }

Write-Host "`nSAVE THESE NOW (shown once):"
Write-Host "Admin:   admin@clinic.local   / $adminPw"
Write-Host "Doctor1: doctor1@clinic.local / $doc1Pw"
Write-Host "Doctor2: doctor2@clinic.local / $doc2Pw"