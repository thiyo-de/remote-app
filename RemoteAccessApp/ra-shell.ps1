# =========================
# RemoteAccess PS Mini Shell (PowerShell 5 compatible)
# =========================
$global:raApiBase = "http://localhost:8080/api"
$global:raDeviceId = $null
$global:raCurrentPath = "/storage/emulated/0"

function Get-RaDevices {
    try {
        $resp = Invoke-RestMethod -Method Get -Uri "$($global:raApiBase)/devices"
        $dev = $resp.devices
        if ($null -eq $dev) { return @() }
        if ($dev -is [System.Array]) { return $dev }
        return @($dev)  # coerce single string to array
    }
    catch {
        Write-Error "Cannot reach server at $($global:raApiBase). $_"
        return @()
    }
}

function Set-RaDevice([string]$DeviceId) {
    if (-not $DeviceId) { throw "DeviceId cannot be empty." }
    $global:raDeviceId = $DeviceId
    Write-Host "Active device: $DeviceId" -ForegroundColor Green
}

function Initialize-RaSession {
    if ($global:raDeviceId) { return }
    $devices = Get-RaDevices
    if ($devices.Count -eq 0) { throw "No devices connected. Ensure APK WS is open." }
    Set-RaDevice -DeviceId ([string]$devices[0])
}

function Send-DeviceCommand {
    param(
        [string]$DeviceId,
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$Params
    )
    if (-not $DeviceId) { $DeviceId = $global:raDeviceId }
    if (-not $DeviceId) { throw "No active device. Run ra-connect first." }

    $body = @{ action = $Action }
    if ($Params) { $body.params = $Params }

    try {
        return Invoke-RestMethod -Method Post `
            -Uri "$($global:raApiBase)/command/$DeviceId" `
            -ContentType "application/json" `
            -Body ($body | ConvertTo-Json -Depth 10)
    }
    catch {
        throw "Command failed ($Action): $_"
    }
}

function Join-PathUnix([string]$Base, [string]$Child) {
    if ([string]::IsNullOrWhiteSpace($Base)) { return $Child }
    if ([string]::IsNullOrWhiteSpace($Child)) { return $Base }
    if ($Child.StartsWith("/")) { return $Child }
    if ($Base.EndsWith("/")) { return "$Base$Child" }
    return "$Base/$Child"
}
function Normalize-PathUnix([string]$Path) {
    if (-not $Path) { return "/" }
    $parts = @()
    foreach ($p in $Path -split "/") {
        if ($p -eq "" -or $p -eq ".") { continue }
        if ($p -eq "..") {
            if ($parts.Count -gt 0) { $parts = $parts[0..($parts.Count - 2)] }
            continue
        }
        $parts += $p
    }
    return "/" + ($parts -join "/")
}

function ra-status {
    $list = Get-RaDevices
    Write-Host "Server devices:" -ForegroundColor Cyan
    if ($list.Count -eq 0) { Write-Host "  (none)"; return }
    foreach ($d in $list) {
        $mark = " "
        if ($d -eq $global:raDeviceId) { $mark = "*" }
        Write-Host (" {0} {1}" -f $mark, $d)
    }
    if ($global:raDeviceId) { Write-Host ("Active: {0}" -f $global:raDeviceId) -ForegroundColor Green }
}

function ra-connect {
    param([string]$DeviceId)
    $devices = Get-RaDevices
    if ($devices.Count -eq 0) { throw "No devices connected." }
    if (-not $DeviceId) { $DeviceId = [string]$devices[0] }
    Set-RaDevice -DeviceId $DeviceId
    ra-pwd
}

function ra-pwd {
    Initialize-RaSession
    Write-Host $global:raCurrentPath -ForegroundColor Yellow
}

function ra-cd {
    param([string]$Dir)
    Initialize-RaSession
    if (-not $Dir) { return }

    $candidate = if ($Dir.StartsWith("/")) { $Dir } else { Join-PathUnix $global:raCurrentPath $Dir }
    $candidate = Normalize-PathUnix $candidate

    $resp = Send-DeviceCommand -Action "list_files" -Params @{ path = $candidate }
    if ($resp.error) { Write-Host "cd: $($resp.error)" -ForegroundColor Red; return }

    $global:raCurrentPath = $candidate
    Write-Host $global:raCurrentPath -ForegroundColor Yellow
}

function ra-ls {
    param([string]$Path)
    Initialize-RaSession

    $target = if ($Path) {
        if ($Path.StartsWith("/")) { $Path } else { Join-PathUnix $global:raCurrentPath $Path }
    }
    else { $global:raCurrentPath }

    $resp = Send-DeviceCommand -Action "list_files" -Params @{ path = $target }
    if ($resp.error) { Write-Host "ls: $($resp.error)" -ForegroundColor Red; return }

    $items = $resp.result
    if (-not $items -or $items.Count -eq 0) { Write-Host "(empty)"; return }

    $items |
    Sort-Object @{Expression = "isDir"; Descending = $true }, @{Expression = "name"; Descending = $false } |
    ForEach-Object {
        if ($_.isDir) {
            Write-Host ("[DIR] {0}" -f $_.name) -ForegroundColor Cyan
        }
        else {
            $kb = [math]::Round(($_.size / 1KB), 1)
            Write-Host ("      {0}  ({1} KB)" -f $_.name, $kb)
        }
    }
}

Set-Alias rpwd ra-pwd -Force
Set-Alias rcd  ra-cd  -Force
Set-Alias rls  ra-ls  -Force

Write-Host "RA shell loaded. Commands: ra-status, ra-connect [deviceId], ra-pwd, ra-cd <dir>, ra-ls [path]" -ForegroundColor Green
Write-Host "Tip: adb reverse tcp:8080 tcp:8080" -ForegroundColor DarkGray

function ra-cat {
    param([Parameter(Mandatory = $true)][string]$Path)

    Initialize-RaSession
    $target = if ($Path.StartsWith("/")) { $Path } else { Join-PathUnix $global:raCurrentPath $Path }
    $resp = Send-DeviceCommand -Action "read_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "cat: $($resp.error)" -ForegroundColor Red; return }

    # Try to print as UTF-8 text; if it fails, say it's binary-ish
    try {
        $bytes = [Convert]::FromBase64String($resp.result.base64)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        Write-Output $text
    }
    catch {
        Write-Host "(binary file)" -ForegroundColor DarkGray
    }
}

function ra-get {
    param(
        [Parameter(Mandatory=$true)][string]$RemotePath,
        [string]$OutFile
    )

    Initialize-RaSession

    # Build absolute remote path
    $target = if ($RemotePath.StartsWith("/")) { $RemotePath } else { Join-PathUnix $global:raCurrentPath $RemotePath }

    # Ask device to read file (should return { name, size, base64 } )
    $resp = Send-DeviceCommand -Action "read_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "get: $($resp.error)" -ForegroundColor Red; return }

    # Decide local file path
    $leafName = if ($resp.result.name) { [string]$resp.result.name } else { [System.IO.Path]::GetFileName($RemotePath) }
    if ([string]::IsNullOrWhiteSpace($leafName)) { $leafName = "download.bin" }

    $finalPath = $OutFile
    if ([string]::IsNullOrWhiteSpace($finalPath)) {
        # No OutFile → save in current directory with remote filename
        $finalPath = Join-Path -Path (Get-Location) -ChildPath $leafName
    } else {
        # If OutFile is a directory (exists OR ends with \ or /), append the leaf name
        $looksLikeDir = (Test-Path -LiteralPath $finalPath -PathType Container) -or ($finalPath -match '[\\/]\s*$')
        if ($looksLikeDir) {
            # Trim trailing slash if present and join
            $trimmed = $finalPath.TrimEnd('\','/')
            if (-not (Test-Path -LiteralPath $trimmed -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $trimmed | Out-Null
            }
            $finalPath = Join-Path -Path $trimmed -ChildPath $leafName
        } else {
            # Ensure parent directory exists
            $parent = Split-Path -LiteralPath $finalPath -Parent
            if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
            }
        }
    }

    # Decode + write (no Resolve-Path, write exactly to the path you gave)
    try {
        $b64   = [string]$resp.result.base64
        if ([string]::IsNullOrWhiteSpace($b64)) {
            Write-Warning "Device returned empty data. (base64 was empty)"
            return
        }
        $bytes = [Convert]::FromBase64String($b64)
        [System.IO.File]::WriteAllBytes($finalPath, $bytes)
        Write-Host ("saved → {0} ({1} bytes)" -f $finalPath, $bytes.Length) -ForegroundColor Green
    } catch {
        Write-Host "get: failed to write file: $($_.Exception.Message)" -ForegroundColor Red
    }
}


Set-Alias rcat ra-cat -Force
Set-Alias rget ra-get -Force
