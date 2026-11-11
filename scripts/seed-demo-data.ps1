$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Missing .env. Copy .env.example to .env and configure it first."
}

function Read-EnvFile([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $Matches[2]
            if ($value.Length -ge 2 -and
                (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                 ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    return $values
}

function Convert-SecureStringToPlainText([Security.SecureString]$Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Invoke-JsonRequest([string]$Method, [string]$Url, [string]$Token, $Body) {
    $headers = @{}
    if ($Token) {
        $headers.Authorization = "Bearer $Token"
    }

    $parameters = @{
        Uri             = $Url
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
        TimeoutSec      = 30
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
    }

    try {
        $response = Invoke-WebRequest @parameters
        $data = $null
        if ($response.Content) {
            try { $data = $response.Content | ConvertFrom-Json } catch { $data = $response.Content }
        }
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Data = $data }
    } catch {
        $status = 0
        $data = $null
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object IO.StreamReader($stream)
                    $content = $reader.ReadToEnd()
                    $reader.Dispose()
                    if ($content) {
                        try { $data = $content | ConvertFrom-Json } catch { $data = $content }
                    }
                }
            } catch { }
        }
        return [pscustomobject]@{ Status = $status; Data = $data }
    }
}

function Invoke-Api([string]$Method, [string]$Path, [string]$Token, $Body, [int[]]$AllowedStatus = @(200)) {
    $response = Invoke-JsonRequest $Method "$script:apiBase$Path" $Token $Body
    if ($response.Status -notin $AllowedStatus) {
        throw "$Method $Path returned HTTP $($response.Status)."
    }
    return $response.Data
}

function New-RandomPassword([int]$Length = 24) {
    $characters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%_-'
    $bytes = New-Object byte[] $Length
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
    $password = New-Object System.Text.StringBuilder
    foreach ($byte in $bytes) {
        [void]$password.Append($characters[[int]$byte % $characters.Length])
    }
    return $password.ToString()
}

function Get-DoctorUserByEmail([string]$Email, [string]$AdminToken) {
    for ($userId = 1; $userId -le 256; $userId++) {
        $response = Invoke-JsonRequest 'GET' "$script:apiBase/auth/users/$userId" $AdminToken $null
        if ($response.Status -eq 200 -and $response.Data.email -ieq $Email) {
            return $response.Data
        }
        if ($response.Status -notin @(200, 404)) {
            throw "Could not look up seeded user ID $userId (HTTP $($response.Status))."
        }
    }
    throw "Could not find seeded doctor account $Email among user IDs 1 through 256."
}

function Add-MissingSlots([long]$DoctorId, [string]$DoctorName, [string]$AdminToken) {
    $created = 0
    for ($dayOffset = 1; $dayOffset -le 7; $dayOffset++) {
        $date = [DateTime]::Now.Date.AddDays($dayOffset)
        $dateText = $date.ToString('yyyy-MM-dd')
        $existing = @(Invoke-Api 'GET' "/doctors/$DoctorId/slots?date=$dateText" $AdminToken $null)

        $missing = New-Object System.Collections.Generic.List[DateTime]
        for ($minute = 9 * 60; $minute -lt 17 * 60; $minute += 30) {
            $start = $date.AddMinutes($minute)
            if ($start -le [DateTime]::Now.AddMinutes(2)) { continue }
            $end = $start.AddMinutes(30)
            $alreadyPresent = $false
            foreach ($slot in $existing) {
                $existingStart = [DateTime]::Parse($slot.startTime)
                $existingEnd = [DateTime]::Parse($slot.endTime)
                if ($existingStart -eq $start -and $existingEnd -eq $end) {
                    $alreadyPresent = $true
                    break
                }
                if ($existingStart -lt $end -and $existingEnd -gt $start) {
                    throw "Existing slot on $dateText overlaps the requested 30-minute schedule for $DoctorName."
                }
            }
            if (-not $alreadyPresent) {
                $missing.Add($start)
            }
        }

        $index = 0
        while ($index -lt $missing.Count) {
            $runStart = $missing[$index]
            $runEnd = $runStart.AddMinutes(30)
            $index++
            while ($index -lt $missing.Count -and $missing[$index] -eq $runEnd) {
                $runEnd = $runEnd.AddMinutes(30)
                $index++
            }
            $body = @{
                date           = $dateText
                startTime      = $runStart.ToString('HH:mm')
                endTime        = $runEnd.ToString('HH:mm')
                durationMinutes = 30
            }
            $newSlots = @(Invoke-Api 'POST' "/doctors/$DoctorId/slots/generate" $AdminToken $body)
            $created += $newSlots.Count
        }
    }
    Write-Host "$DoctorName`: ensured 30-minute slots for the next seven days ($created added)."
}

$envValues = Read-EnvFile $envPath
$port = 80
if ($envValues.ContainsKey('HTTP_PORT') -and $envValues.HTTP_PORT) {
    if ($envValues.HTTP_PORT -notmatch '^\d{1,5}$' -or [int]$envValues.HTTP_PORT -lt 1 -or [int]$envValues.HTTP_PORT -gt 65535) {
        throw 'HTTP_PORT in .env must be an integer between 1 and 65535.'
    }
    $port = [int]$envValues.HTTP_PORT
}
$script:apiBase = "http://localhost:$port/api"

$adminEmail = $envValues.INITIAL_ADMIN_EMAIL
$doctorOneEmail = $envValues.INITIAL_DOCTOR_ONE_EMAIL
$doctorTwoEmail = $envValues.INITIAL_DOCTOR_TWO_EMAIL
if (-not $adminEmail -or $adminEmail -match 'example\.invalid|replace-with') {
    throw 'Set INITIAL_ADMIN_EMAIL to the seeded administrator email in .env.'
}
if (-not $doctorOneEmail -or -not $doctorTwoEmail -or
    $doctorOneEmail -match 'example\.invalid|replace-with' -or
    $doctorTwoEmail -match 'example\.invalid|replace-with') {
    throw 'Set INITIAL_DOCTOR_ONE_EMAIL and INITIAL_DOCTOR_TWO_EMAIL to seeded users in .env.'
}

$secureAdminPassword = Read-Host "Password for seeded administrator $adminEmail" -AsSecureString
$adminPassword = $null
try {
    $adminPassword = Convert-SecureStringToPlainText $secureAdminPassword
    try {
        $login = Invoke-Api 'POST' '/auth/login' '' @{
            email    = $adminEmail
            password = $adminPassword
        } 200
    } finally {
        $adminPassword = $null
    }
    $adminToken = $login.token
    if (-not $adminToken) { throw 'Administrator login response did not contain a token.' }

    $doctorUsers = @(
        (Get-DoctorUserByEmail $doctorOneEmail $adminToken),
        (Get-DoctorUserByEmail $doctorTwoEmail $adminToken)
    )
    $doctors = @(Invoke-Api 'GET' '/doctors' $adminToken $null)
    $specifications = @{
        $doctorOneEmail = 'Family Medicine'
        $doctorTwoEmail = 'Cardiology'
    }
    foreach ($doctorUser in $doctorUsers) {
        $profile = $doctors | Where-Object { [long]$_.userId -eq [long]$doctorUser.id } | Select-Object -First 1
        if (-not $profile) {
            $profile = Invoke-Api 'POST' '/doctors' $adminToken @{
                userId        = [long]$doctorUser.id
                name          = $doctorUser.name
                specialization = $specifications[$doctorUser.email]
            } 201
            $doctors += $profile
            Write-Host "Created doctor profile for $($doctorUser.email) ($($profile.specialization))."
        } else {
            Write-Host "Doctor profile already exists for $($doctorUser.email); leaving it unchanged."
        }
        Add-MissingSlots ([long]$profile.id) $doctorUser.name $adminToken
    }

    for ($patientNumber = 1; $patientNumber -le 3; $patientNumber++) {
        $email = "demo.patient$patientNumber@clinic.local"
        $patientPassword = New-RandomPassword
        $response = Invoke-JsonRequest 'POST' "$script:apiBase/auth/register" '' @{
            name     = "Demo Patient $patientNumber"
            email    = $email
            password = $patientPassword
            phone    = "555010$patientNumber"
        }
        if ($response.Status -eq 201) {
            Write-Host "Created demo patient: $email"
            Write-Host "  Random password (shown once): $patientPassword"
        } elseif ($response.Status -eq 409) {
            Write-Host "Demo patient already exists: $email (not changed)."
        } else {
            $patientPassword = $null
            throw "Patient registration for demo patient $patientNumber returned HTTP $($response.Status)."
        }
        $patientPassword = $null
    }
    Write-Host 'Demo-data seeding completed. Existing profiles, slots, and patient accounts were preserved.'
} finally {
    $adminPassword = $null
    $secureAdminPassword.Dispose()
}
