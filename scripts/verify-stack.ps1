$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
$resultsPath = Join-Path $projectRoot 'docs\TEST_RESULTS.md'
$script:runResults = New-Object System.Collections.Generic.List[object]
$script:envPath = $envPath

function Read-EnvFile([string]$Path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
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

function New-RandomPassword([int]$Length = 28) {
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

function Invoke-JsonRequest([string]$Method, [string]$Url, [string]$Token, $Body) {
    $headers = @{}
    if ($Token) { $headers.Authorization = "Bearer $Token" }
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
    $script:lastApiObservation = "$Method $Path expected HTTP $($AllowedStatus -join ' or '); observed HTTP $($response.Status)"
    if ($response.Status -notin $AllowedStatus) {
        throw $script:lastApiObservation
    }
    return $response.Data
}

function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $script:runResults.Add([pscustomobject]@{
        Name   = $Name
        Passed = $Passed
        Detail = $Detail
    })
    Write-Host "$status - $Name`: $Detail"
}

function Invoke-Compose([string[]]$Arguments) {
    Push-Location $script:projectRoot
    $savedEnvironment = @{}
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        foreach ($name in $script:composeEnvironmentNames) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            $value = $script:envValues[$name]
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
        $ErrorActionPreference = 'Continue'
        $output = & docker compose --env-file $script:envPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $plainOutput = @($output | ForEach-Object { "$_" })
        return [pscustomobject]@{ ExitCode = $exitCode; Output = $plainOutput }
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
        foreach ($name in $script:composeEnvironmentNames) {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
        }
        Pop-Location
    }
}

function Get-ContainerEnvValue([string]$Container, [string]$Key) {
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = & docker inspect --format '{{json .Config.Env}}' $Container 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($exitCode -ne 0 -or -not $raw) { return $null }
    $raw = @($raw | ForEach-Object { "$_" })
    $entries = ConvertFrom-Json ($raw -join '')
    $entry = $entries | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1
    if (-not $entry) { return $null }
    return $entry.Substring($Key.Length + 1)
}

function Get-ContainerHostPort([string]$Container, [string]$ContainerPort) {
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = & docker inspect --format '{{json .NetworkSettings.Ports}}' $Container 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($exitCode -ne 0 -or -not $raw) { return $null }
    $raw = @($raw | ForEach-Object { "$_" })
    $publishedPorts = ConvertFrom-Json ($raw -join '')
    $binding = $publishedPorts.PSObject.Properties[$ContainerPort]
    if (-not $binding -or -not $binding.Value) { return $null }
    return [string]$binding.Value[0].HostPort
}

function Test-PersistentComposeCredentials {
    $checks = @(
        [pscustomobject]@{ Container = 'clinic-booking-phase2-mysql-1'; Key = 'MYSQL_ROOT_PASSWORD'; Expected = $script:envValues.MYSQL_ROOT_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-mysql-1'; Key = 'MYSQL_USER'; Expected = $script:envValues.MYSQL_APP_USER },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-mysql-1'; Key = 'MYSQL_PASSWORD'; Expected = $script:envValues.MYSQL_APP_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-rabbitmq-1'; Key = 'RABBITMQ_DEFAULT_USER'; Expected = $script:envValues.RABBITMQ_USERNAME },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-rabbitmq-1'; Key = 'RABBITMQ_DEFAULT_PASS'; Expected = $script:envValues.RABBITMQ_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-auth-service-1'; Key = 'DB_USERNAME'; Expected = $script:envValues.MYSQL_APP_USER },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-auth-service-1'; Key = 'DB_PASSWORD'; Expected = $script:envValues.MYSQL_APP_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-auth-service-1'; Key = 'JWT_SECRET'; Expected = $script:envValues.JWT_SECRET },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-slot-service-1'; Key = 'DB_USERNAME'; Expected = $script:envValues.MYSQL_APP_USER },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-slot-service-1'; Key = 'DB_PASSWORD'; Expected = $script:envValues.MYSQL_APP_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-slot-service-1'; Key = 'RABBITMQ_USERNAME'; Expected = $script:envValues.RABBITMQ_USERNAME },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-slot-service-1'; Key = 'RABBITMQ_PASSWORD'; Expected = $script:envValues.RABBITMQ_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-slot-service-1'; Key = 'JWT_SECRET'; Expected = $script:envValues.JWT_SECRET },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-appointment-service-1'; Key = 'DB_USERNAME'; Expected = $script:envValues.MYSQL_APP_USER },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-appointment-service-1'; Key = 'DB_PASSWORD'; Expected = $script:envValues.MYSQL_APP_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-appointment-service-1'; Key = 'RABBITMQ_USERNAME'; Expected = $script:envValues.RABBITMQ_USERNAME },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-appointment-service-1'; Key = 'RABBITMQ_PASSWORD'; Expected = $script:envValues.RABBITMQ_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-appointment-service-1'; Key = 'JWT_SECRET'; Expected = $script:envValues.JWT_SECRET },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-notification-service-1'; Key = 'DB_USERNAME'; Expected = $script:envValues.MYSQL_APP_USER },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-notification-service-1'; Key = 'DB_PASSWORD'; Expected = $script:envValues.MYSQL_APP_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-notification-service-1'; Key = 'RABBITMQ_USERNAME'; Expected = $script:envValues.RABBITMQ_USERNAME },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-notification-service-1'; Key = 'RABBITMQ_PASSWORD'; Expected = $script:envValues.RABBITMQ_PASSWORD },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-notification-service-1'; Key = 'JWT_SECRET'; Expected = $script:envValues.JWT_SECRET },
        [pscustomobject]@{ Container = 'clinic-booking-phase2-api-gateway-1'; Key = 'JWT_SECRET'; Expected = $script:envValues.JWT_SECRET }
    )
    $differences = New-Object System.Collections.Generic.List[string]
    foreach ($check in $checks) {
        if (-not $check.Expected) {
            $differences.Add("$($check.Key) missing from .env")
            continue
        }
        $runningValue = Get-ContainerEnvValue $check.Container $check.Key
        if ($null -eq $runningValue -or $runningValue -cne [string]$check.Expected) {
            $envKey = switch ($check.Key) {
                'MYSQL_ROOT_PASSWORD' { 'MYSQL_ROOT_PASSWORD' }
                'MYSQL_USER' { 'MYSQL_APP_USER' }
                'MYSQL_PASSWORD' { 'MYSQL_APP_PASSWORD' }
                'RABBITMQ_DEFAULT_USER' { 'RABBITMQ_USERNAME' }
                'RABBITMQ_DEFAULT_PASS' { 'RABBITMQ_PASSWORD' }
                'DB_USERNAME' { 'MYSQL_APP_USER' }
                'DB_PASSWORD' { 'MYSQL_APP_PASSWORD' }
                'RABBITMQ_USERNAME' { 'RABBITMQ_USERNAME' }
                'RABBITMQ_PASSWORD' { 'RABBITMQ_PASSWORD' }
                'JWT_SECRET' { 'JWT_SECRET' }
                default { $check.Key }
            }
            $message = "$envKey differs from running container configuration (value redacted)"
            if (-not $differences.Contains($message)) { $differences.Add($message) }
        }
    }
    $httpHostPort = Get-ContainerHostPort 'clinic-booking-phase2-frontend-nginx-1' '80/tcp'
    if ($script:envValues.HTTP_PORT -notmatch '^\d{1,5}$' -or
        $script:envValues.HTTP_PORT -cne $httpHostPort) {
        $differences.Add("HTTP_PORT differs from running Nginx mapping (expected .env port=$httpHostPort; observed .env setting=$($script:envValues.HTTP_PORT))")
    }
    $rabbitHostPort = Get-ContainerHostPort 'clinic-booking-phase2-rabbitmq-1' '15672/tcp'
    if ($script:envValues.RABBITMQ_MANAGEMENT_PORT -notmatch '^\d{1,5}$' -or
        $script:envValues.RABBITMQ_MANAGEMENT_PORT -cne $rabbitHostPort) {
        $differences.Add("RABBITMQ_MANAGEMENT_PORT differs from running RabbitMQ mapping (expected .env port=$rabbitHostPort; observed .env setting=$($script:envValues.RABBITMQ_MANAGEMENT_PORT))")
    }
    return [pscustomobject]@{ Matches = ($differences.Count -eq 0); Differences = @($differences) }
}

function Get-QueueStats {
    $script:rabbitLastStatus = 0
    $uri = "http://localhost:$script:rabbitPort/api/queues/%2F/notification.appointment-events"
    $pair = '{0}:{1}' -f $script:rabbitUser, $script:rabbitPassword
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Authorization = "Basic $encoded" } -UseBasicParsing -TimeoutSec 15
        $script:rabbitLastStatus = 200
        return [pscustomobject]@{
            Status = 200
            Ready = [int]$response.messages_ready
            Unacked = [int]$response.messages_unacknowledged
        }
    } catch {
        if ($_.Exception.Response) {
            $script:rabbitLastStatus = [int]$_.Exception.Response.StatusCode
        }
        return [pscustomobject]@{ Status = $script:rabbitLastStatus; Ready = -1; Unacked = -1 }
    }
}

function Get-NotificationHealth {
    $ps = Invoke-Compose @('ps', '--all', '--format', '{{.Service}}|{{.State}}|{{.Health}}')
    if ($ps.ExitCode -ne 0) {
        return [pscustomobject]@{ Running = $false; Healthy = $false; Observed = "docker compose ps exit code $($ps.ExitCode)" }
    }
    $row = $ps.Output | Where-Object { "$_" -match '^notification-service\|' } | Select-Object -First 1
    if (-not $row) {
        return [pscustomobject]@{ Running = $false; Healthy = $false; Observed = 'notification-service row missing from docker compose ps' }
    }
    $parts = "$row" -split '\|'
    $isRunning = $parts.Count -ge 2 -and $parts[1] -eq 'running'
    $isHealthy = $parts.Count -ge 3 -and $parts[2] -eq 'healthy'
    return [pscustomobject]@{ Running = $isRunning; Healthy = $isHealthy; Observed = "$($parts[1])/$($parts[2])" }
}

function Wait-NotificationHealthy([int]$TimeoutSeconds = 120) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $observed = 'not checked'
    while ([DateTime]::UtcNow -lt $deadline) {
        $health = Get-NotificationHealth
        $observed = $health.Observed
        if ($health.Healthy) {
            return [pscustomobject]@{ Healthy = $true; Observed = $observed }
        }
        Start-Sleep -Seconds 2
    }
    return [pscustomobject]@{ Healthy = $false; Observed = $observed }
}

function Get-FreshAvailableSlots([long]$DoctorId, [int]$RequiredCount, [string]$AdminToken) {
    $available = New-Object System.Collections.Generic.List[object]
    $now = [DateTime]::Now.AddMinutes(3)
    for ($offset = 1; $offset -le 7 -and $available.Count -lt $RequiredCount; $offset++) {
        $dateText = [DateTime]::Now.Date.AddDays($offset).ToString('yyyy-MM-dd')
        $slots = @(Invoke-Api 'GET' "/doctors/$DoctorId/slots?date=$dateText&status=AVAILABLE" $AdminToken $null)
        foreach ($slot in ($slots | Sort-Object startTime)) {
            if ([DateTime]::Parse($slot.startTime) -gt $now -and
                -not ($available | Where-Object { [long]$_.id -eq [long]$slot.id })) {
                $available.Add($slot)
                if ($available.Count -ge $RequiredCount) { break }
            }
        }
    }

    for ($offset = 1; $offset -le 7 -and $available.Count -lt $RequiredCount; $offset++) {
        $date = [DateTime]::Now.Date.AddDays($offset)
        $dateText = $date.ToString('yyyy-MM-dd')
        $slots = @(Invoke-Api 'GET' "/doctors/$DoctorId/slots?date=$dateText" $AdminToken $null)
        for ($minute = 9 * 60; $minute -lt 17 * 60 -and $available.Count -lt $RequiredCount; $minute += 30) {
            $start = $date.AddMinutes($minute)
            $overlapsExisting = $false
            foreach ($slot in $slots) {
                $existingStart = [DateTime]::Parse($slot.startTime)
                $existingEnd = [DateTime]::Parse($slot.endTime)
                if ($existingStart -lt $start.AddMinutes(30) -and $existingEnd -gt $start) {
                    $overlapsExisting = $true
                    break
                }
            }
            if ($overlapsExisting) { continue }
            $created = Invoke-Api 'POST' "/doctors/$DoctorId/slots" $AdminToken @{
                startTime = $start.ToString('yyyy-MM-ddTHH:mm:ss')
                endTime   = $start.AddMinutes(30).ToString('yyyy-MM-ddTHH:mm:ss')
            } 201
            $available.Add($created)
            $slots += $created
        }
    }
    if ($available.Count -lt $RequiredCount) {
        throw "Could not find or create $RequiredCount distinct future available slots."
    }
    return @($available | Select-Object -First $RequiredCount)
}

function Get-BaselineDoctor([string]$AdminToken) {
    $doctors = @(Invoke-Api 'GET' '/doctors' $AdminToken $null)
    if ($doctors.Count -gt 0) {
        return $doctors[0]
    }

    for ($userId = 1; $userId -le 256; $userId++) {
        $userResponse = Invoke-JsonRequest 'GET' "$script:apiBase/auth/users/$userId" $AdminToken $null
        if ($userResponse.Status -eq 404) { continue }
        if ($userResponse.Status -ne 200) {
            throw "Expected GET /auth/users/$userId HTTP 200 or 404; observed HTTP $($userResponse.Status)."
        }
        if ($userResponse.Data.role -eq 'DOCTOR') {
            return Invoke-Api 'POST' '/doctors' $AdminToken @{
                userId        = [long]$userResponse.Data.id
                name          = $userResponse.Data.name
                specialization = 'General Practice'
            } 201
        }
    }
    throw 'Expected an existing seeded doctor profile or doctor user; observed none among user IDs 1 through 256.'
}

function New-BaselineSlot([long]$DoctorId, [string]$AdminToken) {
    for ($offset = 1; $offset -le 7; $offset++) {
        $date = [DateTime]::Now.Date.AddDays($offset)
        $dateText = $date.ToString('yyyy-MM-dd')
        $existing = @(Invoke-Api 'GET' "/doctors/$DoctorId/slots?date=$dateText" $AdminToken $null)
        for ($minute = 8 * 60; $minute -lt 20 * 60; $minute += 30) {
            $start = $date.AddMinutes($minute)
            $end = $start.AddMinutes(30)
            $overlap = $false
            foreach ($slot in $existing) {
                if ([DateTime]::Parse($slot.startTime) -lt $end -and
                    [DateTime]::Parse($slot.endTime) -gt $start) {
                    $overlap = $true
                    break
                }
            }
            if ($overlap) { continue }
            return Invoke-Api 'POST' "/doctors/$DoctorId/slots" $AdminToken @{
                startTime = $start.ToString('yyyy-MM-ddTHH:mm:ss')
                endTime   = $end.ToString('yyyy-MM-ddTHH:mm:ss')
            } 201
        }
    }
    throw 'Expected an unoccupied 30-minute baseline slot within seven days; observed no free interval.'
}

function Get-PatientAppointments([string]$PatientToken) {
    return @(Invoke-Api 'GET' '/appointments/my' $PatientToken $null)
}

function Find-AppointmentForSlot([object[]]$Appointments, [long]$SlotId) {
    return $Appointments | Where-Object { [long]$_.slotId -eq $SlotId } | Select-Object -First 1
}

$script:projectRoot = $projectRoot
$script:envPath = $envPath
$script:envValues = $envValues
$script:composeEnvironmentNames = @(
    'MYSQL_ROOT_PASSWORD', 'MYSQL_APP_USER', 'MYSQL_APP_PASSWORD',
    'RABBITMQ_USERNAME', 'RABBITMQ_PASSWORD', 'RABBITMQ_MANAGEMENT_PORT',
    'HTTP_PORT', 'AUTH_SERVICE_PORT', 'SLOT_SERVICE_PORT',
    'APPOINTMENT_SERVICE_PORT', 'NOTIFICATION_SERVICE_PORT', 'GATEWAY_PORT',
    'MYSQL_DOCKER_HOST', 'REDIS_DOCKER_HOST', 'RABBITMQ_DOCKER_HOST',
    'SLOT_SERVICE_DOCKER_URL', 'AUTH_SERVICE_DOCKER_URL',
    'APPOINTMENT_SERVICE_DOCKER_URL', 'NOTIFICATION_SERVICE_DOCKER_URL',
    'JWT_SECRET', 'JWT_EXPIRATION_MS', 'INITIAL_ADMIN_NAME', 'INITIAL_ADMIN_EMAIL',
    'INITIAL_ADMIN_PASSWORD_HASH', 'INITIAL_DOCTOR_ONE_NAME', 'INITIAL_DOCTOR_ONE_EMAIL',
    'INITIAL_DOCTOR_ONE_PASSWORD_HASH', 'INITIAL_DOCTOR_TWO_NAME', 'INITIAL_DOCTOR_TWO_EMAIL',
    'INITIAL_DOCTOR_TWO_PASSWORD_HASH', 'FRONTEND_ORIGIN_DOCKER', 'REMINDER_INTERVAL_MS'
)
$script:notificationStopped = $false
$script:composeWasTakenDown = $false
$script:persistencePrecheckFailed = $false
$script:adminPromptUnavailable = $false
$script:rabbitPromptUnavailable = $false
$adminPassword = $null
$secureAdminPassword = $null
$testPassword = $null
$nodeEnvironment = @{}
$nodeEnvironmentNames = @('GATEWAY_URL', 'PATIENT_EMAIL', 'PATIENT_PASSWORD', 'CONCURRENCY_SLOT_ID')
$envValues = Read-EnvFile $envPath
$port = 80
if ($envValues.HTTP_PORT) {
    if ($envValues.HTTP_PORT -notmatch '^\d{1,5}$' -or [int]$envValues.HTTP_PORT -lt 1 -or [int]$envValues.HTTP_PORT -gt 65535) {
        $port = 80
    } else {
        $port = [int]$envValues.HTTP_PORT
    }
}
$script:origin = "http://localhost:$port"
$script:apiBase = "$script:origin/api"
$script:rabbitPort = 15672
if ($envValues.RABBITMQ_MANAGEMENT_PORT -match '^\d{1,5}$' -and [int]$envValues.RABBITMQ_MANAGEMENT_PORT -ge 1) {
    $script:rabbitPort = [int]$envValues.RABBITMQ_MANAGEMENT_PORT
}
$script:rabbitUser = $envValues.RABBITMQ_USERNAME
$script:rabbitPassword = $envValues.RABBITMQ_PASSWORD
$adminEmail = $envValues.INITIAL_ADMIN_EMAIL
$adminToken = $null
$patientEmail = $null
$patientToken = $null
$doctor = $null
$testSlots = @()
$queueAppointmentId = $null
$docProfileIds = @()

if (-not (Test-Path -LiteralPath $envPath)) {
    foreach ($name in @(
        'a. docker compose container health',
        'b. login through Nginx /api',
        'c. patient hold-confirm-cancel',
        'd. 20-parallel booking concurrency',
        'e. notification queue downtime recovery',
        'f. data persistence after down/up'
    )) {
        Add-Check $name $false 'Expected a repository .env file with the stack settings; observed that .env is missing, so this check could not run.'
    }
} else {
    if (-not $adminEmail -or $adminEmail -match 'example\.invalid|replace-with') {
        try {
            $adminEmail = Read-Host 'Seeded administrator email'
        } catch {
            $script:adminPromptUnavailable = $true
        }
    }
    try {
        $secureAdminPassword = Read-Host "Seeded administrator password for $adminEmail" -AsSecureString
    } catch {
        $secureAdminPassword = New-Object Security.SecureString
        $script:adminPromptUnavailable = $true
    }

    if (-not $script:rabbitUser) {
        try {
            $script:rabbitUser = Read-Host 'RabbitMQ management username'
        } catch {
            $script:rabbitPromptUnavailable = $true
        }
    }
    if (-not $script:rabbitPassword) {
        try {
            $secureRabbitPassword = Read-Host 'RabbitMQ management password' -AsSecureString
            $script:rabbitPassword = Convert-SecureStringToPlainText $secureRabbitPassword
            $secureRabbitPassword.Dispose()
        } catch {
            $script:rabbitPassword = ''
            $script:rabbitPromptUnavailable = $true
        }
    }

    try {
        try {
            $composePs = Invoke-Compose @('ps', '--all', '--format', '{{.Service}}|{{.State}}|{{.Health}}')
        } catch {
            $composePs = [pscustomobject]@{ ExitCode = $null; Output = @() }
        }
        $expectedServices = @('mysql', 'redis', 'rabbitmq', 'auth-service', 'slot-service', 'appointment-service', 'notification-service', 'api-gateway', 'frontend-nginx')
        $services = @()
        if ($composePs.ExitCode -eq 0) {
            foreach ($line in $composePs.Output) {
                $parts = "$line" -split '\|'
                if ($parts.Count -eq 3) {
                    $services += [pscustomobject]@{ Name = $parts[0]; State = $parts[1]; Health = $parts[2] }
                }
            }
        }
        $healthy = $composePs.ExitCode -eq 0 -and $services.Count -eq $expectedServices.Count
        foreach ($expected in $expectedServices) {
            $service = $services | Where-Object { $_.Name -eq $expected } | Select-Object -First 1
            if (-not $service -or $service.State -ne 'running' -or $service.Health -ne 'healthy') {
                $healthy = $false
            }
        }
        $observedServiceStates = if ($services.Count -gt 0) {
            ($services | ForEach-Object { "$($_.Name)=$($_.State)/$($_.Health)" }) -join ', '
        } else {
            "docker compose ps exit code $($composePs.ExitCode); no service rows parsed"
        }
        Add-Check 'a. docker compose ps shows all containers healthy' $healthy "Expected nine services running/healthy; observed $($services.Count) rows: $observedServiceStates."

        $login = $null
        $loginResponse = $null
        if ($script:adminPromptUnavailable) {
            $loginResponse = [pscustomobject]@{ Status = 0; Data = $null }
            Add-Check 'b. login works through Nginx at /api' $false 'Expected HTTP 200 with a token; observed no request because secure credential input was unavailable in this noninteractive shell.'
        } else {
            try {
                $adminPassword = Convert-SecureStringToPlainText $secureAdminPassword
                $loginResponse = Invoke-JsonRequest 'POST' "$script:apiBase/auth/login" '' @{
                    email = $adminEmail
                    password = $adminPassword
                }
                if ($loginResponse.Status -ne 200) { throw "Expected HTTP 200; observed HTTP $($loginResponse.Status)." }
                $login = $loginResponse.Data
                $adminToken = $login.token
                if (-not $adminToken) { throw "Expected HTTP 200 with a bearer token; observed HTTP $($loginResponse.Status) with no token." }
                Add-Check 'b. login works through Nginx at /api' $true "Expected HTTP 200; observed HTTP $($loginResponse.Status) and a token."
            } catch {
                $observedStatus = if ($loginResponse) { $loginResponse.Status } else { 0 }
                Add-Check 'b. login works through Nginx at /api' $false "Expected HTTP 200 with a token; observed HTTP $observedStatus."
            } finally {
                $adminPassword = $null
            }
        }

        if ($adminToken) {
            $cStage = 'register verification patient'
            $cObserved = 'no HTTP response'
            try {
                $randomId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
                $patientEmail = "stack-verify-$randomId@example.test"
                $testPassword = New-RandomPassword
                $cStage = 'register verification patient'
                $null = Invoke-Api 'POST' '/auth/register' '' @{
                    name     = 'Stack Verification Patient'
                    email    = $patientEmail
                    password = $testPassword
                    phone    = '5550199'
                } 201
                $cObserved = 'HTTP 201'
                $cStage = 'login verification patient'
                $patientLogin = Invoke-Api 'POST' '/auth/login' '' @{ email = $patientEmail; password = $testPassword } 200
                $patientToken = $patientLogin.token
                if (-not $patientToken) { $cObserved = 'HTTP 200 without token'; throw 'Patient login returned no token.' }
                $cObserved = 'patient login HTTP 200'

                $cStage = 'list doctors'
                $doctors = @(Invoke-Api 'GET' '/doctors' $adminToken $null)
                if ($doctors.Count -lt 1) {
                    $cObserved = 'GET /doctors returned HTTP 200 with zero doctor profiles'
                    throw 'No doctor profiles are available.'
                }
                $doctor = $doctors | Select-Object -First 1
                $docProfileIds = @($doctors | ForEach-Object { [long]$_.id })
                $cStage = 'find or create three future slots'
                $testSlots = @(Get-FreshAvailableSlots ([long]$doctor.id) 3 $adminToken)

                $cStage = 'hold slot'
                $null = Invoke-Api 'POST' '/appointments/hold' $patientToken @{ slotId = [long]$testSlots[0].id } 200
                $cObserved = 'hold HTTP 200'
                $cStage = 'confirm appointment'
                $appointment = Invoke-Api 'POST' '/appointments/confirm' $patientToken @{ slotId = [long]$testSlots[0].id } 201
                $cObserved = 'hold HTTP 200; confirmation HTTP 201'
                $cStage = 'cancel appointment'
                $canceled = Invoke-Api 'POST' "/appointments/$($appointment.id)/cancel" $patientToken $null 200
                if ($canceled.status -ne 'CANCELLED') {
                    $cObserved = "hold HTTP 200; confirmation HTTP 201; cancellation HTTP 200 with status $($canceled.status)"
                    throw 'Cancellation returned an unexpected appointment status.'
                }
                $cObserved = 'hold HTTP 200; confirmation HTTP 201; cancellation HTTP 200/status CANCELLED'
                Add-Check 'c. patient can hold, confirm, and cancel a slot' $true "Expected hold/confirm/cancel HTTP 200/201/200 and CANCELLED; observed $cObserved."
            } catch {
                if ($script:lastApiObservation) { $cObserved = $script:lastApiObservation }
                Add-Check 'c. patient can hold, confirm, and cancel a slot' $false "Expected successful $cStage (hold/confirm/cancel HTTP 200/201/200); observed $cObserved."
            }

            if ($patientToken -and $testSlots.Count -ge 2) {
                $summary = $null
                $dObserved = 'concurrency test did not produce a result summary'
                try {
                    foreach ($name in $nodeEnvironmentNames) {
                        $nodeEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                    }
                    $env:GATEWAY_URL = "$script:origin/api"
                    $env:PATIENT_EMAIL = $patientEmail
                    $env:PATIENT_PASSWORD = $testPassword
                    $env:CONCURRENCY_SLOT_ID = [string]$testSlots[1].id
                    $nodeExitCode = -1
                    Push-Location $projectRoot
                    try {
                        $nodeOutput = & node 'scripts\test-booking-concurrency.mjs' 2>&1
                        $nodeExitCode = $LASTEXITCODE
                    } finally {
                        Pop-Location
                    }
                    $resultLine = @($nodeOutput | ForEach-Object { "$_" } | Where-Object { $_ -match '^RESULT_JSON:' }) | Select-Object -Last 1
                    $summary = $null
                    if ($resultLine) {
                        $summary = $resultLine.Substring('RESULT_JSON:'.Length) | ConvertFrom-Json
                        $dObserved = "holds=$($summary.holds), confirmations=$($summary.confirmed), HTTP 409 conflicts=$($summary.conflicts) of $($summary.contenders) contenders"
                    } else {
                        $dObserved = "node exit code=$nodeExitCode; RESULT_JSON absent; HTTP outcome totals unavailable"
                    }
                    $passed = $nodeExitCode -eq 0 -and $summary -and
                        $summary.contenders -eq 20 -and $summary.holds -eq 1 -and
                        $summary.confirmed -eq 1 -and $summary.conflicts -eq 19
                    if (-not $passed) { throw 'Concurrency results did not equal one hold, one confirmation, and 19 HTTP 409 conflicts.' }
                    $appointments = Get-PatientAppointments $patientToken
                    $confirmedConcurrencyAppointment = Find-AppointmentForSlot $appointments ([long]$testSlots[1].id)
                    if (-not $confirmedConcurrencyAppointment -or $confirmedConcurrencyAppointment.status -ne 'CONFIRMED') {
                        $dObserved = 'HTTP results matched expected counts, but the winning appointment was not found as CONFIRMED'
                        throw 'The concurrency winner appointment was not found as CONFIRMED.'
                    }
                    Add-Check 'd. 20 parallel contenders produce one success and 19 HTTP 409s' $true "Expected 1 hold, 1 confirmation and 19 HTTP 409 responses; observed $dObserved."
                } catch {
                    Add-Check 'd. 20 parallel contenders produce one success and 19 HTTP 409s' $false "Expected 20 contenders: 1 hold, 1 confirmation, 19 HTTP 409s; observed $dObserved."
                } finally {
                    foreach ($name in $nodeEnvironmentNames) {
                        [Environment]::SetEnvironmentVariable($name, $nodeEnvironment[$name], 'Process')
                    }
                }
            } else {
                Add-Check 'd. 20 parallel contenders produce one success and 19 HTTP 409s' $false "Expected 20 contenders with 1 hold, 1 confirmation and 19 HTTP 409s; observed no run, patient token=$([bool]$patientToken), available test slots=$($testSlots.Count)."
            }

            if ($patientToken -and $testSlots.Count -ge 3) {
                $ePassed = $false
                $eObserved = 'no queue/API observations yet'
                $eStage = 'initial queue state'
                $eQueueAppointmentId = $null
                $eStartExit = -1
                $healthAfterRestart = [pscustomobject]@{ Healthy = $false; Observed = 'restart not attempted' }
                try {
                    $before = Get-QueueStats
                    if ($before.Status -eq 401) {
                        $secureRabbitPassword = Read-Host 'RabbitMQ management password was rejected; enter the correct password' -AsSecureString
                        $script:rabbitPassword = Convert-SecureStringToPlainText $secureRabbitPassword
                        $secureRabbitPassword.Dispose()
                        $before = Get-QueueStats
                    }
                    $eObserved = "management HTTP $($before.Status), ready=$($before.Ready), unacked=$($before.Unacked)"
                    if ($before.Status -ne 200 -or $before.Ready -ne 0 -or $before.Unacked -ne 0) {
                        throw 'Initial queue state did not match the empty-queue precondition.'
                    }
                    $eStage = 'stop notification-service'
                    $script:notificationStopped = $true
                    $stop = Invoke-Compose @('stop', 'notification-service')
                    if ($stop.ExitCode -ne 0) {
                        $eObserved = "docker compose stop exit code $($stop.ExitCode)"
                        throw 'Could not stop notification-service.'
                    }
                    $eObserved = 'notification-service stop exit code 0'
                    $eStage = 'hold test slot'
                    $null = Invoke-Api 'POST' '/appointments/hold' $patientToken @{ slotId = [long]$testSlots[2].id } 200
                    $eObserved = 'hold HTTP 200'
                    $eStage = 'confirm test appointment'
                    $queueAppointment = Invoke-Api 'POST' '/appointments/confirm' $patientToken @{ slotId = [long]$testSlots[2].id } 201
                    $eQueueAppointmentId = [long]$queueAppointment.id
                    $eObserved = 'hold HTTP 200; confirmation HTTP 201'

                    $eStage = 'poll notification queue for up to 30 seconds'
                    $queueDuring = [pscustomobject]@{ Status = 0; Ready = -1; Unacked = -1 }
                    $deadline = [DateTime]::UtcNow.AddSeconds(30)
                    while ([DateTime]::UtcNow -lt $deadline) {
                        $queueDuring = Get-QueueStats
                        if ($queueDuring.Status -eq 200 -and $queueDuring.Ready -eq 1 -and $queueDuring.Unacked -eq 0) {
                            break
                        }
                        Start-Sleep -Seconds 2
                    }
                    $eObserved = "management HTTP $($queueDuring.Status), ready=$($queueDuring.Ready), unacked=$($queueDuring.Unacked) after polling up to 30 seconds"
                    if ($queueDuring.Status -ne 200 -or $queueDuring.Ready -ne 1 -or $queueDuring.Unacked -ne 0) {
                        throw 'Queue did not reach the expected single-ready-message state.'
                    }
                    $eStage = 'queue drain and notification delivery'
                } catch {
                    $failureObservation = $_.Exception.Message
                    if ($failureObservation -match 'expected HTTP .*observed HTTP') {
                        $eObserved = "$eObserved; $failureObservation"
                    } else {
                        $eObserved = "$eObserved; detail=$failureObservation"
                    }
                    $eObserved = "$eObserved; stage=$eStage"
                } finally {
                    try {
                        $start = Invoke-Compose @('start', 'notification-service')
                        $eStartExit = $start.ExitCode
                    } catch {
                        $eStartExit = 127
                        $eObserved = "$eObserved; docker compose start raised an error"
                    }
                    try {
                        $healthAfterRestart = Wait-NotificationHealthy 120
                    } catch {
                        $healthAfterRestart = [pscustomobject]@{ Healthy = $false; Observed = 'health polling raised an error' }
                    }
                    $script:notificationStopped = -not $healthAfterRestart.Healthy
                }

                if ($eStartExit -ne 0 -or -not $healthAfterRestart.Healthy) {
                    $eObserved = "$eObserved; docker compose start exit code=$eStartExit; health=$($healthAfterRestart.Observed)"
                } elseif ($eQueueAppointmentId) {
                    $drained = $false
                    $sent = $false
                    $queueAfter = [pscustomobject]@{ Status = 0; Ready = -1; Unacked = -1 }
                    $notificationStatus = 'not found'
                    $deadline = [DateTime]::UtcNow.AddSeconds(90)
                    try {
                        while ([DateTime]::UtcNow -lt $deadline) {
                            $queueAfter = Get-QueueStats
                            if ($queueAfter.Status -eq 200 -and $queueAfter.Ready -eq 0 -and $queueAfter.Unacked -eq 0) {
                                $drained = $true
                            }
                            $notifications = @(Invoke-Api 'GET' '/notifications/my' $patientToken $null)
                            $sentNotification = $notifications | Where-Object {
                                [long]$_.appointmentId -eq $eQueueAppointmentId
                            } | Select-Object -First 1
                            if ($sentNotification) { $notificationStatus = [string]$sentNotification.status }
                            if ($drained -and $notificationStatus -eq 'SENT') { $sent = $true; break }
                            Start-Sleep -Seconds 2
                        }
                    } catch {
                        $notificationStatus = "lookup error: $($_.Exception.Message)"
                    }
                    $eObserved = "after restart health=$($healthAfterRestart.Observed); management HTTP $($queueAfter.Status), ready=$($queueAfter.Ready), unacked=$($queueAfter.Unacked); notification status=$notificationStatus"
                    $ePassed = $drained -and $sent
                }
                if ($ePassed) {
                    Add-Check 'e. notification queue buffers and delivers during service downtime' $true "Expected stopped queue ready=1/unacked=0, then healthy service, queue ready=0/unacked=0 and notification SENT; observed $eObserved."
                } else {
                    Add-Check 'e. notification queue buffers and delivers during service downtime' $false "Expected stopped queue ready=1/unacked=0, then healthy service, queue ready=0/unacked=0 and notification SENT; observed $eObserved."
                }
            } else {
                $health = Wait-NotificationHealthy 120
                Add-Check 'e. notification queue buffers and delivers during service downtime' $false "Expected patient token, three available test slots and healthy notification-service; observed patient token=$([bool]$patientToken), slots=$($testSlots.Count), health=$($health.Observed)."
            }
        } else {
            $health = Wait-NotificationHealthy 120
            Add-Check 'c. patient can hold, confirm, and cancel a slot' $false "Expected admin login HTTP 200 then patient flow; observed admin login HTTP $($loginResponse.Status)."
            Add-Check 'd. 20 parallel contenders produce one success and 19 HTTP 409s' $false "Expected 20 contenders with 1 hold, 1 confirmation and 19 HTTP 409s; observed no run because admin login HTTP $($loginResponse.Status)."
            Add-Check 'e. notification queue buffers and delivers during service downtime' $false "Expected stopped queue ready=1/unacked=0, then healthy restart and ready=0/unacked=0; observed no run because admin login HTTP $($loginResponse.Status), notification-service health=$($health.Observed)."
        }

        $fPassed = $false
        $fStage = 'create independent baseline'
        $fObserved = 'no baseline observations yet'
        $baselineDoctor = $null
        $baselineSlot = $null
        $baselineAppointment = $null
        $baselinePatientEmail = $null
        $baselinePatientPassword = $null
        try {
            if (-not $adminToken) {
                $script:persistencePrecheckFailed = $true
                $fObserved = "admin login HTTP $($loginResponse.Status); no baseline objects created"
                throw 'Administrator login unavailable for persistence baseline.'
            }

            $baselineDoctor = Get-BaselineDoctor $adminToken
            $fObserved = "baseline doctor profile id=$($baselineDoctor.id) available"

            $fStage = 'create independent baseline slot'
            $baselineSlot = New-BaselineSlot ([long]$baselineDoctor.id) $adminToken
            $fObserved = "baseline doctor id=$($baselineDoctor.id), baseline slot id=$($baselineSlot.id)"

            $fStage = 'register and login independent baseline patient'
            $baselinePatientEmail = "stack-persistence-$([Guid]::NewGuid().ToString('N').Substring(0,12))@example.test"
            $baselinePatientPassword = New-RandomPassword
            $baselinePatientRegistration = Invoke-JsonRequest 'POST' "$script:apiBase/auth/register" '' @{
                name = 'Persistence Baseline Patient'
                email = $baselinePatientEmail
                password = $baselinePatientPassword
                phone = '5550198'
            }
            if ($baselinePatientRegistration.Status -ne 201) {
                $fObserved = "baseline patient registration expected HTTP 201; observed HTTP $($baselinePatientRegistration.Status)"
                throw 'Could not create independent persistence-baseline patient.'
            }
            $baselinePatientLogin = Invoke-JsonRequest 'POST' "$script:apiBase/auth/login" '' @{
                email = $baselinePatientEmail
                password = $baselinePatientPassword
            }
            if ($baselinePatientLogin.Status -ne 200 -or -not $baselinePatientLogin.Data.token) {
                $fObserved = "baseline patient login expected HTTP 200 with token; observed HTTP $($baselinePatientLogin.Status)"
                throw 'Could not authenticate independent persistence-baseline patient.'
            }
            $baselinePatientToken = $baselinePatientLogin.Data.token

            $fStage = 'create independent baseline appointment'
            $baselineHold = Invoke-JsonRequest 'POST' "$script:apiBase/appointments/hold" $baselinePatientToken @{
                slotId = [long]$baselineSlot.id
            }
            if ($baselineHold.Status -ne 200) {
                $fObserved = "baseline hold expected HTTP 200; observed HTTP $($baselineHold.Status)"
                throw 'Could not hold baseline slot.'
            }
            $baselineConfirm = Invoke-JsonRequest 'POST' "$script:apiBase/appointments/confirm" $baselinePatientToken @{
                slotId = [long]$baselineSlot.id
            }
            if ($baselineConfirm.Status -ne 201) {
                $fObserved = "baseline confirmation expected HTTP 201; observed HTTP $($baselineConfirm.Status)"
                throw 'Could not confirm baseline appointment.'
            }
            $baselineAppointment = $baselineConfirm.Data
            $fObserved = "doctor id=$($baselineDoctor.id), slot id=$($baselineSlot.id), appointment id=$($baselineAppointment.id), confirmation HTTP 201"

            $appointmentsBeforeRestart = @(Invoke-Api 'GET' '/appointments/my' $baselinePatientToken $null)
            if (-not (Find-AppointmentForSlot $appointmentsBeforeRestart ([long]$baselineSlot.id))) {
                $fObserved = "baseline appointment id=$($baselineAppointment.id) not returned by GET /appointments/my before restart"
                throw 'Baseline appointment is missing before restart.'
            }

            $fStage = 'validate .env against running Compose settings'
            $composeSettings = Test-PersistentComposeCredentials
            if (-not $composeSettings.Matches) {
                $script:persistencePrecheckFailed = $true
                $fObserved = "mismatched settings: $($composeSettings.Differences -join '; ')"
                throw 'Compose settings do not match the current runtime configuration.'
            }

            $fStage = 'docker compose down/up without deleting volumes'
            $script:composeWasTakenDown = $true
            $down = Invoke-Compose @('down')
            if ($down.ExitCode -ne 0) {
                $fObserved = "docker compose down expected exit code 0; observed $($down.ExitCode)"
                throw 'docker compose down failed.'
            }
            $up = Invoke-Compose @('up', '-d', '--wait')
            if ($up.ExitCode -ne 0) {
                $fObserved = "docker compose up -d --wait expected exit code 0; observed $($up.ExitCode)"
                throw 'docker compose up -d --wait failed.'
            }
            $script:composeWasTakenDown = $false

            $fStage = 'verify all containers healthy after restart'
            $psAfter = Invoke-Compose @('ps', '--all', '--format', '{{.Service}}|{{.State}}|{{.Health}}')
            $badServices = New-Object System.Collections.Generic.List[string]
            foreach ($expected in @('mysql', 'redis', 'rabbitmq', 'auth-service', 'slot-service', 'appointment-service', 'notification-service', 'api-gateway', 'frontend-nginx')) {
                $row = $psAfter.Output | Where-Object { "$_" -match ("^{0}\|" -f [regex]::Escape($expected)) } | Select-Object -First 1
                if (-not $row -or "$row" -notmatch '^\w[\w-]*\|running\|healthy$') {
                    $badServices.Add("$expected=$row")
                }
            }
            if ($psAfter.ExitCode -ne 0 -or $badServices.Count -gt 0) {
                $fObserved = "compose ps exit=$($psAfter.ExitCode); unhealthy/missing rows=$($badServices -join ', ')"
                throw 'Not all services recovered healthy.'
            }

            $fStage = 'verify baseline doctor persisted'
            $adminPassword = Convert-SecureStringToPlainText $secureAdminPassword
            try {
                $newAdminLogin = Invoke-JsonRequest 'POST' "$script:apiBase/auth/login" '' @{
                    email = $adminEmail
                    password = $adminPassword
                }
            } finally {
                $adminPassword = $null
            }
            if ($newAdminLogin.Status -ne 200 -or -not $newAdminLogin.Data.token) {
                $fObserved = "admin relogin expected HTTP 200; observed HTTP $($newAdminLogin.Status)"
                throw 'Administrator login failed after restart.'
            }
            $adminToken = $newAdminLogin.Data.token
            $baselineDoctorAfter = @(Invoke-Api 'GET' '/doctors' $adminToken $null) |
                Where-Object { [long]$_.id -eq [long]$baselineDoctor.id } | Select-Object -First 1
            if (-not $baselineDoctorAfter) {
                $fObserved = "baseline doctor profile id=$($baselineDoctor.id) missing from GET /doctors after restart"
                throw 'Baseline doctor profile did not persist.'
            }

            $fStage = 'verify baseline slot persisted'
            $slotDate = ([DateTime]::Parse($baselineSlot.startTime)).ToString('yyyy-MM-dd')
            $slotsAfter = @(Invoke-Api 'GET' "/doctors/$($baselineDoctor.id)/slots?date=$slotDate" $adminToken $null)
            if (-not ($slotsAfter | Where-Object { [long]$_.id -eq [long]$baselineSlot.id })) {
                $fObserved = "baseline slot id=$($baselineSlot.id) missing from doctor $($baselineDoctor.id) on $slotDate"
                throw 'Baseline slot did not persist.'
            }

            $fStage = 'verify baseline appointment persisted'
            $patientLoginAfter = Invoke-JsonRequest 'POST' "$script:apiBase/auth/login" '' @{
                email = $baselinePatientEmail
                password = $baselinePatientPassword
            }
            if ($patientLoginAfter.Status -ne 200 -or -not $patientLoginAfter.Data.token) {
                $fObserved = "baseline patient relogin expected HTTP 200; observed HTTP $($patientLoginAfter.Status)"
                throw 'Baseline patient could not log in after restart.'
            }
            $appointmentsAfter = @(Invoke-Api 'GET' '/appointments/my' $patientLoginAfter.Data.token $null)
            if (-not (Find-AppointmentForSlot $appointmentsAfter ([long]$baselineSlot.id))) {
                $fObserved = "baseline appointment id=$($baselineAppointment.id) for slot $($baselineSlot.id) missing after restart"
                throw 'Baseline appointment did not persist.'
            }
            $fObserved = "baseline doctor id=$($baselineDoctor.id), slot id=$($baselineSlot.id), appointment id=$($baselineAppointment.id) all found after restart"
            $fPassed = $true
        } catch {
            $failureObservation = $_.Exception.Message
            if ($failureObservation -match 'expected HTTP .*observed HTTP') {
                $fObserved = $failureObservation
            } elseif ($fObserved -eq 'no baseline observations yet' -and $script:lastApiObservation) {
                $fObserved = $script:lastApiObservation
            }
            $fObserved = "stage=$fStage; $fObserved; detail=$failureObservation"
        } finally {
            $baselinePatientPassword = $null
            if ($script:composeWasTakenDown) {
                try {
                    $restore = Invoke-Compose @('up', '-d', '--wait')
                    if ($restore.ExitCode -eq 0) {
                        $script:composeWasTakenDown = $false
                    } else {
                        $fPassed = $false
                        $fObserved += "; recovery expected docker compose up -d --wait exit code 0; observed $($restore.ExitCode)"
                    }
                } catch {
                    $fPassed = $false
                    $fObserved += '; recovery expected docker compose up -d --wait success; observed command error'
                }
            }
        }

        if ($fPassed) {
            Add-Check 'f. down/up preserves doctors, slots, and appointments' $true "Expected the independent baseline doctor, slot and appointment to exist after down/up; observed $fObserved."
        } else {
            Add-Check 'f. down/up preserves doctors, slots, and appointments' $false "Expected the independent baseline doctor, slot and appointment to persist after down/up; observed $fObserved."
        }
    } finally {
        $finalRestartError = $null
        if ($script:notificationStopped) {
            try {
                $finalStart = Invoke-Compose @('start', 'notification-service')
                if ($finalStart.ExitCode -ne 0) { $finalRestartError = "docker compose start exit code=$($finalStart.ExitCode)" }
            } catch {
                $finalRestartError = 'docker compose start raised an error'
            }
        }
        if ($script:composeWasTakenDown) {
            try {
                $finalUp = Invoke-Compose @('up', '-d', '--wait')
                if ($finalUp.ExitCode -ne 0) {
                    $finalRestartError = "docker compose up -d --wait exit code=$($finalUp.ExitCode)"
                } else {
                    $script:composeWasTakenDown = $false
                }
            } catch {
                $finalRestartError = 'docker compose up -d --wait raised an error'
            }
        }
        try {
            $finalNotificationHealth = Wait-NotificationHealthy 120
            $finalHealthDetail = "Expected notification-service running/healthy; observed $($finalNotificationHealth.Observed)."
            if ($finalRestartError) { $finalHealthDetail += " Recovery attempt: $finalRestartError." }
            Add-Check 'notification-service is healthy before verifier exit' $finalNotificationHealth.Healthy $finalHealthDetail
        } catch {
            Add-Check 'notification-service is healthy before verifier exit' $false 'Expected notification-service running/healthy; observed health polling error.'
        }
        $adminPassword = $null
        if ($secureAdminPassword) { $secureAdminPassword.Dispose() }
        $testPassword = $null
        $script:rabbitPassword = $null
    }
}

$timestamp = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz')
if (-not (Test-Path -LiteralPath $resultsPath)) {
    throw 'docs\TEST_RESULTS.md is missing; cannot persist verification results.'
}
$document = Get-Content -LiteralPath $resultsPath -Raw
if ($document -notmatch '(?m)^## Phase 2 - containerized verification\s*$') {
    Add-Content -LiteralPath $resultsPath -Value "`r`n## Phase 2 - containerized verification`r`n" -Encoding UTF8
}
Add-Content -LiteralPath $resultsPath -Value "`r`n### Run: $timestamp`r`n" -Encoding UTF8
foreach ($result in $script:runResults) {
    $status = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    Add-Content -LiteralPath $resultsPath -Value "- **$status** - $($result.Name): $($result.Detail)" -Encoding UTF8
}

$failedChecks = @($script:runResults | Where-Object { -not $_.Passed })
if ($failedChecks.Count -gt 0) { exit 1 }
exit 0
