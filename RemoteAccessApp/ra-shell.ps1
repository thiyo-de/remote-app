# =========================
# RemoteAccess PS Mini Shell (PowerShell 5 compatible)
# =========================
$global:raApiBase     = "http://localhost:8080/api"
$global:raDeviceId    = $null
$global:raCurrentPath = "/storage/emulated/0"

# ---------------- Core plumbing ----------------

function Get-RaDevices {
    try {
        $resp = Invoke-RestMethod -Method Get -Uri "$($global:raApiBase)/devices"
        $dev = $resp.devices
        if ($null -eq $dev) { return @() }
        if ($dev -is [System.Array]) { return $dev }
        return @($dev)
    } catch {
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
        [Parameter(Mandatory=$true)][string]$Action,
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
    } catch {
        throw "Command failed ($Action): $_"
    }
}

# --------------- Path helpers (UNIX-style remote, Windows local) ---------------

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
        if ($p -eq "..") { if ($parts.Count -gt 0) { $parts = $parts[0..($parts.Count-2)] }; continue }
        $parts += $p
    }
    return "/" + ($parts -join "/")
}

# Build a safe local path under $BaseDir using a remote child path (sanitize Windows-illegal chars)
function New-RaSafeChildPath {
    param(
        [Parameter(Mandatory=$true)][string]$BaseDir,
        [Parameter(Mandatory=$true)][string]$ChildRelativeUnix
    )
    $rel = $ChildRelativeUnix -replace '^[\\/]+', '' -replace '/', '\'
    $segments = $rel -split '\\'

    $sanitized = @()
    foreach ($seg in $segments) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        $seg = ($seg -replace '[<>:"/\\|?*]', '_')
        $seg = $seg.TrimEnd('.', ' ')
        if ($seg.Length -eq 0) { $seg = '_' }
        $sanitized += $seg
    }

    $path = $BaseDir
    foreach ($s in $sanitized) { $path = [System.IO.Path]::Combine($path, $s) }
    return $path
}

function Save-RaBytes {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][byte[]]$Bytes
    )
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

# --- Windows filename sanitizer (for downloads)
function Sanitize-Name([string]$name) {
    if ($null -eq $name) { return "_" }
    $bad = [IO.Path]::GetInvalidFileNameChars() -join ''
    $re = "[{0}]" -f [regex]::Escape($bad)
    $clean = [regex]::Replace($name, $re, "_")
    $clean = $clean.TrimEnd(" ", ".")
    if ($clean -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { $clean = "_$clean" }
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "_" }
    return $clean
}

# ---------------- Shell-like UX ----------------

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
    if ($Path) {
        if ($Path.StartsWith("/")) { $target = $Path } else { $target = Join-PathUnix $global:raCurrentPath $Path }
    } else {
        $target = $global:raCurrentPath
    }
    $resp = Send-DeviceCommand -Action "list_files" -Params @{ path = $target }
    if ($resp.error) { Write-Host "ls: $($resp.error)" -ForegroundColor Red; return }
    $items = $resp.result
    if (-not $items -or $items.Count -eq 0) { Write-Host "(empty)"; return }
    $items |
      Sort-Object @{Expression="isDir";Descending=$true}, @{Expression="name";Descending=$false} |
      ForEach-Object {
        if ($_.isDir) {
            Write-Host ("[DIR] {0}" -f $_.name) -ForegroundColor Cyan
        } else {
            $kb = [math]::Round(($_.size / 1KB), 1)
            Write-Host ("      {0}  ({1} KB)" -f $_.name, $kb)
        }
      }
}

# ---------------- File viewing/downloading ----------------

function ra-cat {
    param([Parameter(Mandatory=$true)][string]$Path)
    Initialize-RaSession
    if ($Path.StartsWith("/")) { $target = $Path } else { $target = Join-PathUnix $global:raCurrentPath $Path }
    $resp = Send-DeviceCommand -Action "read_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "cat: $($resp.error)" -ForegroundColor Red; return }
    try {
        $bytes = [Convert]::FromBase64String([string]$resp.result.base64)
        $text  = [System.Text.Encoding]::UTF8.GetString($bytes)
        Write-Output $text
    } catch {
        Write-Host "(binary file)" -ForegroundColor DarkGray
    }
}

function ra-get {
    param(
        [Parameter(Mandatory=$true)][string]$RemotePath,
        [string]$OutFile
    )
    Initialize-RaSession
    if ($RemotePath.StartsWith("/")) { $target = $RemotePath } else { $target = Join-PathUnix $global:raCurrentPath $RemotePath }
    $resp = Send-DeviceCommand -Action "read_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "get: $($resp.error)" -ForegroundColor Red; return }

    $leafFromDevice = if ($resp.result.name) { [string]$resp.result.name } else { [IO.Path]::GetFileName($RemotePath) }
    if ([string]::IsNullOrWhiteSpace($leafFromDevice)) { $leafFromDevice = "download.bin" }
    $safeLeaf = Sanitize-Name $leafFromDevice

    if ($OutFile) { $finalPath = $OutFile } else { $finalPath = (Join-Path -Path (Get-Location) -ChildPath $safeLeaf) }
    $looksLikeDir = (Test-Path -LiteralPath $finalPath -PathType Container) -or ($finalPath -match '[\\/]\s*$')
    if ($looksLikeDir) {
        $trimmed = $finalPath.TrimEnd('\','/')
        if (-not (Test-Path -LiteralPath $trimmed -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $trimmed | Out-Null
        }
        $finalPath = Join-Path -Path $trimmed -ChildPath $safeLeaf
    } else {
        $parent = [IO.Path]::GetDirectoryName($finalPath)
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    $b64 = [string]$resp.result.base64
    if ([string]::IsNullOrWhiteSpace($b64)) { Write-Warning "Device returned empty data for $target"; return }
    $bytes = [Convert]::FromBase64String($b64)
    [IO.File]::WriteAllBytes($finalPath, $bytes)
    Write-Host ("saved → {0} ({1} bytes)" -f $finalPath, $bytes.Length) -ForegroundColor Green
}

# ---------------- Writing / Uploading / Deleting ----------------
# (These match Android actions: mkdirs, write_file, delete_file, delete_dir)

function ra-mkdir {
    param([Parameter(Mandatory=$true)][string]$RemoteDir)
    Initialize-RaSession
    if ($RemoteDir.StartsWith("/")) { $target = $RemoteDir } else { $target = Join-PathUnix $global:raCurrentPath $RemoteDir }
    $resp = Send-DeviceCommand -Action "mkdirs" -Params @{ path = $target }
    if ($resp.error) { Write-Host "mkdir: $($resp.error)" -ForegroundColor Red; return }
    Write-Host "created → $target" -ForegroundColor Green
}

function ra-write {
    param(
        [Parameter(Mandatory=$true)][string]$RemoteFile,
        [Parameter(Mandatory=$true)][string]$Text,
        [switch]$Append
    )
    Initialize-RaSession
    if ($RemoteFile.StartsWith("/")) { $target = $RemoteFile } else { $target = Join-PathUnix $global:raCurrentPath $RemoteFile }
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $b64    = [Convert]::ToBase64String($bytes)
    $resp = Send-DeviceCommand -Action "write_file" -Params @{ path = $target; base64 = $b64; append = [bool]$Append }
    if ($resp.error) { Write-Host "write: $($resp.error)" -ForegroundColor Red; return }
    Write-Host ("wrote → {0} ({1} bytes)" -f $target, $bytes.Length) -ForegroundColor Green
}

function ra-put {
    param(
        [Parameter(Mandatory=$true)][string]$LocalFile,
        [string]$RemotePath
    )
    Initialize-RaSession
    if (-not (Test-Path -LiteralPath $LocalFile -PathType Leaf)) { Write-Host "put: local file not found" -ForegroundColor Red; return }
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $LocalFile))
    $b64   = [Convert]::ToBase64String($bytes)

    $leaf = [IO.Path]::GetFileName($LocalFile)

    if ($RemotePath) {
        $rp = $RemotePath
        $isDirHint = ($rp -match '[\\/]\s*$')
        if ($isDirHint) { $rp = $rp.TrimEnd('\','/') }
        if ($rp.StartsWith("/")) { $baseRemote = $rp } else { $baseRemote = Join-PathUnix $global:raCurrentPath $rp }
        if ($isDirHint) { $target = Join-PathUnix $baseRemote $leaf } else { $target = $baseRemote }
    } else {
        $target = Join-PathUnix $global:raCurrentPath $leaf
    }

    $resp = Send-DeviceCommand -Action "write_file" -Params @{ path = $target; base64 = $b64; append = $false }
    if ($resp.error) { Write-Host "put: $($resp.error)" -ForegroundColor Red; return }
    Write-Host ("uploaded → {0} ({1} bytes)" -f $target, $bytes.Length) -ForegroundColor Green
}

function ra-rm {
    param([Parameter(Mandatory=$true)][string]$RemoteFile)
    Initialize-RaSession
    if ($RemoteFile.StartsWith("/")) { $target = $RemoteFile } else { $target = Join-PathUnix $global:raCurrentPath $RemoteFile }
    $resp = Send-DeviceCommand -Action "delete_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "rm: $($resp.error)" -ForegroundColor Red; return }
    Write-Host "deleted file → $target" -ForegroundColor Green
}

function ra-rmdir {
    param(
        [Parameter(Mandatory=$true)][string]$RemoteDir,
        [switch]$Recursive
    )
    Initialize-RaSession
    if ($RemoteDir.StartsWith("/")) { $target = $RemoteDir } else { $target = Join-PathUnix $global:raCurrentPath $RemoteDir }
    $resp = Send-DeviceCommand -Action "delete_dir" -Params @{ path = $target; recursive = [bool]$Recursive }
    if ($resp.error) { Write-Host "rmdir: $($resp.error)" -ForegroundColor Red; return }
    Write-Host ("deleted dir → {0}" -f $target) -ForegroundColor Green
}

# ---------------- Recursive directory pull (any file types) ----------------
function ra-getdir {
    param(
        [Parameter(Mandatory=$true)][string]$RemoteDir,
        [Parameter(Mandatory=$true)][string]$LocalDir,
        [string[]]$Include,
        [string[]]$Exclude,
        [switch]$SkipAndroid,
        [int]$MaxDepth = 99
    )

    Initialize-RaSession

    function Test-Match { param([string]$Name, [string[]]$Patterns)
        if (-not $Patterns -or $Patterns.Count -eq 0) { return $true }
        foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
        return $false
    }

    if ($RemoteDir.StartsWith("/")) { $rootRemote = $RemoteDir } else { $rootRemote = Join-PathUnix $global:raCurrentPath $RemoteDir }
    $LocalDir = [System.IO.Path]::GetFullPath($LocalDir)
    if (-not [System.IO.Directory]::Exists($LocalDir)) { [System.IO.Directory]::CreateDirectory($LocalDir) | Out-Null }

    $probe = Send-DeviceCommand -Action "list_files" -Params @{ path = $rootRemote }
    if ($probe.error) { Write-Host "getdir: $($probe.error)" -ForegroundColor Red; return }

    $q = New-Object System.Collections.Generic.Queue[System.String]
    $q.Enqueue($rootRemote)

    $files = 0; $dirs = 0; $errors = 0

    while ($q.Count -gt 0) {
        $cur = $q.Dequeue()
        $dirs++

        if ($SkipAndroid -and ($cur -like "*/Android*" -or $cur -eq "/storage/emulated/0/Android")) {
            Write-Host ("skip → {0}" -f $cur) -ForegroundColor DarkGray
            continue
        }

        $ls = Send-DeviceCommand -Action "list_files" -Params @{ path = $cur }
        if ($ls.error) { Write-Host ("skip {0}: {1}" -f $cur, $ls.error) -ForegroundColor DarkYellow; $errors++; continue }
        $items = $ls.result
        if (-not $items) { continue }

        foreach ($it in $items) {
            $remoteChild = Join-PathUnix $cur $it.name

            if ($it.isDir) {
                $relDepth = ($remoteChild -replace [regex]::Escape($rootRemote), '') -split '/' | Where-Object { $_ -ne '' }
                if ($relDepth.Count -le $MaxDepth) { $q.Enqueue($remoteChild) }
                continue
            }

            if (-not (Test-Match -Name $it.name -Patterns $Include)) { continue }
            if ($Exclude -and (Test-Match -Name $it.name -Patterns $Exclude)) { continue }

            $rf = Send-DeviceCommand -Action "read_file" -Params @{ path = $remoteChild }
            if ($rf.error) { Write-Host ("get: {0} → {1}" -f $rf.error, $remoteChild) -ForegroundColor Red; $errors++; continue }

            try {
                $bytes = [Convert]::FromBase64String([string]$rf.result.base64)
                $relative = $remoteChild.Substring($rootRemote.Length).TrimStart('/')
                $dest = New-RaSafeChildPath -BaseDir $LocalDir -ChildRelativeUnix $relative
                Save-RaBytes -Path $dest -Bytes $bytes
                $files++
                if (($files % 25) -eq 0) { Write-Host ("… {0} files" -f $files) -ForegroundColor DarkGray }
            } catch {
                Write-Host ("save failed → {0}: {1}" -f $remoteChild, $_) -ForegroundColor Red
                $errors++
            }
        }
    }

    Write-Host ("Done. Dirs: {0}, Files: {1}, Errors: {2}" -f $dirs, $files, $errors) -ForegroundColor Cyan
}

# ---------------- Roots helpers ----------------

function ra-roots {
    Initialize-RaSession
    $resp = Send-DeviceCommand -Action "list_storage_roots"
    if ($resp.error) { Write-Host "roots: $($resp.error)" -ForegroundColor Red; return }
    $roots = $resp.result.roots
    if (-not $roots -or $roots.Count -eq 0) { Write-Host "(no roots reported)"; return }
    foreach ($r in $roots) { Write-Host ("{0}`t{1}" -f $r.name, $r.path) -ForegroundColor Cyan }
}

function ra-getall-storage {
    param(
        [Parameter(Mandatory=$true)][string]$LocalBase,
        [switch]$SkipAndroid
    )
    Initialize-RaSession
    if (-not (Test-Path -LiteralPath $LocalBase)) {
        New-Item -ItemType Directory -Force -Path $LocalBase | Out-Null
    }
    $resp = Send-DeviceCommand -Action "list_storage_roots"
    if ($resp.error) { Write-Host "roots: $($resp.error)" -ForegroundColor Red; return }
    $roots = $resp.result.roots
    if (-not $roots) { Write-Host "(no roots)"; return }

    foreach ($r in $roots) {
        $name = if ($r.name) { $r.name } else { ($r.path -replace '.*/', 'root') }
        $dest = Join-Path -Path $LocalBase -ChildPath $name
        Write-Host ("== Dumping {0} → {1}" -f $r.path, $dest) -ForegroundColor Yellow
        if ($SkipAndroid) { ra-getdir -RemoteDir $r.path -LocalDir $dest -SkipAndroid }
        else { ra-getdir -RemoteDir $r.path -LocalDir $dest }
    }
}

# ---------------- Shortcuts & banner ----------------

Set-Alias rpwd    ra-pwd    -Force
Set-Alias rcd     ra-cd     -Force
Set-Alias rls     ra-ls     -Force
Set-Alias rcat    ra-cat    -Force
Set-Alias rget    ra-get    -Force
Set-Alias rput    ra-put    -Force
Set-Alias rwrite  ra-write  -Force
Set-Alias rmkdir  ra-mkdir  -Force
Set-Alias rrm     ra-rm     -Force
Set-Alias rrmdir  ra-rmdir  -Force
Set-Alias rgetdir ra-getdir -Force

Write-Host "RA shell loaded. Commands:" -ForegroundColor Green
Write-Host "  ra-status, ra-connect [deviceId], ra-pwd, ra-cd <dir>, ra-ls [path]" -ForegroundColor Green
Write-Host "  ra-cat <file>, ra-get <remote> [local], ra-put <local> [remote|dir/]" -ForegroundColor Green
Write-Host "  ra-mkdir <remoteDir>, ra-write <remoteFile> <text> [-Append], ra-rm <file>, ra-rmdir <dir> [-Recursive]" -ForegroundColor Green
Write-Host "  ra-getdir <remoteDir> <localDir> [-SkipAndroid] [-Include ...] [-Exclude ...]" -ForegroundColor Green
Write-Host "  ra-roots, ra-getall-storage <localBase> [-SkipAndroid]" -ForegroundColor Green
Write-Host "Tip: ensure ADB reverse is set:  adb reverse tcp:8080 tcp:8080" -ForegroundColor DarkGray
