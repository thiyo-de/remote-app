# =========================
# RemoteAccess PS Mini Shell (PowerShell 5 compatible)
# =========================
$global:raApiBase = "http://localhost:8080/api"
$global:raDeviceId = $null
$global:raCurrentPath = "/storage/emulated/0"

# ---------------- Core plumbing ----------------

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
        if ($p -eq "..") {
            if ($parts.Count -gt 0) { $parts = $parts[0..($parts.Count - 2)] }
            continue
        }
        $parts += $p
    }
    return "/" + ($parts -join "/")
}

# Build a safe local path under $BaseDir using a *remote* child path (sanitize Windows-illegal chars)
function New-RaSafeChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDir,
        [Parameter(Mandatory = $true)][string]$ChildRelativeUnix  # e.g. "Pictures/foo.jpg" or "/storage/emulated/0/Pictures/foo.jpg"
    )
    $rel = $ChildRelativeUnix -replace '^[\\/]+', '' -replace '/', '\'
    $segments = $rel -split '\\'

    $sanitized = @()
    foreach ($seg in $segments) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        $seg = ($seg -replace '[<>:"/\\|?*]', '_')  # illegal on Windows
        $seg = $seg.TrimEnd('.', ' ')                # trailing dot/space not allowed
        if ($seg.Length -eq 0) { $seg = '_' }
        $sanitized += $seg
    }

    $path = $BaseDir
    foreach ($s in $sanitized) { $path = [System.IO.Path]::Combine($path, $s) }
    return $path
}

function Save-RaBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
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

    $target = if ($Path) {
        if ($Path.StartsWith("/")) { $Path } else { Join-PathUnix $global:raCurrentPath $Path }
    }
    else {
        $global:raCurrentPath
    }

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

# ---------------- File viewing/downloading ----------------

function ra-cat {
    param([Parameter(Mandatory = $true)][string]$Path)

    Initialize-RaSession
    $target = if ($Path.StartsWith("/")) { $Path } else { Join-PathUnix $global:raCurrentPath $Path }
    $resp = Send-DeviceCommand -Action "read_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "cat: $($resp.error)" -ForegroundColor Red; return }

    try {
        $bytes = [Convert]::FromBase64String([string]$resp.result.base64)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        Write-Output $text
    }
    catch {
        Write-Host "(binary file)" -ForegroundColor DarkGray
    }
}

function ra-get {
    param(
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [string]$OutFile
    )

    Initialize-RaSession
    $target = if ($RemotePath.StartsWith("/")) { $RemotePath } else { Join-PathUnix $global:raCurrentPath $RemotePath }
    $resp = Send-DeviceCommand -Action "read_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "get: $($resp.error)" -ForegroundColor Red; return }

    # --- Choose output filename ---
    $finalPath = if ($OutFile) { $OutFile } else { $resp.result.name }

    # --- Ensure directory exists ---
    $dirOnly = [System.IO.Path]::GetDirectoryName($finalPath)
    if ($dirOnly -and -not (Test-Path -LiteralPath $dirOnly)) {
        New-Item -ItemType Directory -Path $dirOnly -Force | Out-Null
    }

    # --- Write file safely ---
    $bytes = [Convert]::FromBase64String($resp.result.base64)
    [IO.File]::WriteAllBytes($finalPath, $bytes)
    Write-Host ("saved → {0} ({1} bytes)" -f $finalPath, $bytes.Length) -ForegroundColor Green
}

function ra-getdir {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteDir,
        [Parameter(Mandatory = $true)][string]$OutDir,
        [switch]$SkipAndroid
    )

    Initialize-RaSession
    $resp = Send-DeviceCommand -Action "list_files" -Params @{ path = $RemoteDir }
    if ($resp.error) { Write-Host "ls: $($resp.error)" -ForegroundColor Red; return }

    foreach ($item in $resp.result) {
        $localPath = Join-Path $OutDir $item.name
        $remotePath = Join-PathUnix $RemoteDir $item.name

        if ($item.isDir) {
            if ($SkipAndroid -and $item.name -eq "Android") { continue }
            if (-not (Test-Path -LiteralPath $localPath)) {
                New-Item -ItemType Directory -Path $localPath -Force | Out-Null
            }
            ra-getdir $remotePath $localPath -SkipAndroid:$SkipAndroid
        }
        else {
            try {
                ra-get $remotePath $localPath
            }
            catch {
                Write-Host "save failed → $localPath" -ForegroundColor Red
            }
        }
    }
}


# Recursive directory pull (any file types). Optional filters.
function ra-getdir {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteDir,
        [Parameter(Mandatory = $true)][string]$LocalDir,
        [string[]]$Include,      # e.g. '*.jpg','*.mp4'
        [string[]]$Exclude,      # e.g. '*.tmp','*.nomedia'
        [switch]$SkipAndroid,    # skip /Android subtree
        [int]$MaxDepth = 99
    )

    Initialize-RaSession

    $rootRemote = if ($RemoteDir.StartsWith("/")) { $RemoteDir } else { Join-PathUnix $global:raCurrentPath $RemoteDir }
    $LocalDir = [System.IO.Path]::GetFullPath($LocalDir)
    if (-not [System.IO.Directory]::Exists($LocalDir)) { [System.IO.Directory]::CreateDirectory($LocalDir) | Out-Null }

    function Test-Match {
        param([string]$Name, [string[]]$Patterns)
        if (-not $Patterns -or $Patterns.Count -eq 0) { return $true }
        foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
        return $false
    }

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
                # depth check
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
            }
            catch {
                Write-Host ("save failed → {0}: {1}" -f $remoteChild, $_) -ForegroundColor Red
                $errors++
            }
        }
    }

    Write-Host ("Done. Dirs: {0}, Files: {1}, Errors: {2}" -f $dirs, $files, $errors) -ForegroundColor Cyan
}

# ---------------- Shortcuts & banner ----------------

Set-Alias rpwd    ra-pwd    -Force
Set-Alias rcd     ra-cd     -Force
Set-Alias rls     ra-ls     -Force
Set-Alias rcat    ra-cat    -Force
Set-Alias rget    ra-get    -Force
Set-Alias rgetdir ra-getdir -Force

Write-Host "RA shell loaded. Commands: ra-status, ra-connect [deviceId], ra-pwd, ra-cd <dir>, ra-ls [path], ra-cat <file>, ra-get <remote> [local], ra-getdir <remoteDir> <localDir> [-SkipAndroid] [-Include ...] [-Exclude ...]" -ForegroundColor Green
Write-Host "Tip: ensure ADB reverse is set:  adb reverse tcp:8080 tcp:8080" -ForegroundColor DarkGray

# --- NEW helper: make any Android filename safe for Windows/NTFS
function Sanitize-Name([string]$name) {
    if ($null -eq $name) { return "_" }
    # Replace invalid NTFS characters with underscore
    $bad = [IO.Path]::GetInvalidFileNameChars() -join ''
    $re = "[{0}]" -f [regex]::Escape($bad)
    $clean = [regex]::Replace($name, $re, "_")

    # Strip trailing spaces and dots (not allowed on NTFS)
    $clean = $clean.TrimEnd(" ", ".")

    # Avoid reserved device names
    if ($clean -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        $clean = "_$clean"
    }
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "_" }
    return $clean
}

# --- REPLACE your ra-get with this version
function ra-get {
    param(
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [string]$OutFile
    )

    Initialize-RaSession

    # Remote absolute path
    $target = if ($RemotePath.StartsWith("/")) { $RemotePath } else { Join-PathUnix $global:raCurrentPath $RemotePath }

    # Read the file from device
    $resp = Send-DeviceCommand -Action "read_file" -Params @{ path = $target }
    if ($resp.error) { Write-Host "get: $($resp.error)" -ForegroundColor Red; return }

    # Decide local target path
    $leafFromDevice = if ($resp.result.name) { [string]$resp.result.name } else { [IO.Path]::GetFileName($RemotePath) }
    if ([string]::IsNullOrWhiteSpace($leafFromDevice)) { $leafFromDevice = "download.bin" }
    $safeLeaf = Sanitize-Name $leafFromDevice

    $finalPath = if ($OutFile) { $OutFile } else { (Join-Path -Path (Get-Location) -ChildPath $safeLeaf) }

    # If $OutFile points to an existing directory OR ends with \ or /, append filename
    $looksLikeDir = (Test-Path -LiteralPath $finalPath -PathType Container) -or ($finalPath -match '[\\/]\s*$')
    if ($looksLikeDir) {
        $trimmed = $finalPath.TrimEnd('\', '/')
        if (-not (Test-Path -LiteralPath $trimmed -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $trimmed | Out-Null
        }
        $finalPath = Join-Path -Path $trimmed -ChildPath $safeLeaf
    }
    else {
        $parent = [IO.Path]::GetDirectoryName($finalPath)
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    # Decode & write bytes
    $b64 = [string]$resp.result.base64
    if ([string]::IsNullOrWhiteSpace($b64)) {
        Write-Warning "Device returned empty data (base64 was empty) for $target"
        return
    }
    $bytes = [Convert]::FromBase64String($b64)
    [IO.File]::WriteAllBytes($finalPath, $bytes)
    Write-Host ("saved → {0} ({1} bytes)" -f $finalPath, $bytes.Length) -ForegroundColor Green
}

# --- REPLACE your ra-getdir with this version
function ra-getdir {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteDir,
        [Parameter(Mandatory = $true)][string]$OutDir,
        [string[]]$Include,      # optional filters, e.g. '*.jpg','*.mp4'
        [string[]]$Exclude,      # optional excludes
        [switch]$SkipAndroid,    # skip /Android subtree entirely
        [int]$MaxDepth = 99
    )

    Initialize-RaSession

    function Test-Match {
        param([string]$Name, [string[]]$Patterns)
        if (-not $Patterns -or $Patterns.Count -eq 0) { return $true }
        foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
        return $false
    }

    $rootRemote = if ($RemoteDir.StartsWith("/")) { $RemoteDir } else { Join-PathUnix $global:raCurrentPath $RemoteDir }

    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    }

    function Download-Tree([string]$remotePath, [string]$localPath, [int]$depth) {
        if ($depth -gt $MaxDepth) { return }

        if ($SkipAndroid -and ($remotePath -like "*/Android" -or $remotePath -like "*/Android/*")) {
            Write-Host ("skip → {0}" -f $remotePath) -ForegroundColor DarkGray
            return
        }

        $list = Send-DeviceCommand -Action "list_files" -Params @{ path = $remotePath }
        if ($list.error) { Write-Host ("getdir: {0}" -f $list.error) -ForegroundColor Red; return }
        $items = $list.result
        if (-not $items) { return }

        # Ensure current local directory exists
        if (-not (Test-Path -LiteralPath $localPath)) {
            New-Item -ItemType Directory -Force -Path $localPath | Out-Null
        }

        foreach ($it in $items) {
            $safeName = Sanitize-Name $it.name
            $rChild = Join-PathUnix $remotePath $it.name
            $lChild = Join-Path $localPath $safeName

            if ($it.isDir) {
                Download-Tree -remotePath $rChild -localPath $lChild -depth ($depth + 1)
                continue
            }

            # filters
            if (-not (Test-Match -Name $it.name -Patterns $Include)) { continue }
            if ($Exclude -and (Test-Match -Name $it.name -Patterns $Exclude)) { continue }

            $fileResp = Send-DeviceCommand -Action "read_file" -Params @{ path = $rChild }
            if ($fileResp.error) {
                Write-Host ("get: {0} → {1}" -f $fileResp.error, $rChild) -ForegroundColor Red
                continue
            }

            try {
                $b64 = [string]$fileResp.result.base64
                if ([string]::IsNullOrWhiteSpace($b64)) {
                    Write-Warning ("empty data → {0}" -f $rChild)
                    continue
                }
                $bytes = [Convert]::FromBase64String($b64)
                $parent = [IO.Path]::GetDirectoryName($lChild)
                if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory -Force -Path $parent | Out-Null
                }
                [IO.File]::WriteAllBytes($lChild, $bytes)
                Write-Host ("saved → {0} ({1} bytes)" -f $lChild, $bytes.Length) -ForegroundColor Green
            }
            catch {
                Write-Host ("save failed → {0}: {1}" -f $lChild, $_.Exception.Message) -ForegroundColor Red
            }
        }
    }

    Download-Tree -remotePath $rootRemote -localPath $OutDir -depth 0
}

function ra-roots {
    Initialize-RaSession
    $resp = Send-DeviceCommand -Action "list_storage_roots"
    if ($resp.error) { Write-Host "roots: $($resp.error)" -ForegroundColor Red; return }
    $roots = $resp.result.roots
    if (-not $roots -or $roots.Count -eq 0) { Write-Host "(no roots reported)"; return }
    foreach ($r in $roots) {
        Write-Host ("{0}`t{1}" -f $r.name, $r.path) -ForegroundColor Cyan
    }
}

function ra-getall-storage {
    param(
        [Parameter(Mandatory = $true)][string]$LocalBase,
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
        ra-getdir $r.path $dest @(@{SkipAndroid = $SkipAndroid }).Where({ $_.Value }).ForEach({ $_ })
    }
}
