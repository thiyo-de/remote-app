# --- config ---
$ServerBase = "http://localhost:8080"
$Api = "$ServerBase/api"
$DeviceId = (adb shell settings get secure android_id).Trim()

Write-Host "DeviceId: $DeviceId" -ForegroundColor Cyan

# Ensure device is connected & reverse is set
$devs = (& adb devices) -join "`n"
if ($devs -notmatch "device`r?$") {
  Write-Host "No adb device connected (or unauthorized). Check USB debugging." -ForegroundColor Red
  exit 1
}
adb reverse tcp:8080 tcp:8080 | Out-Null

# Start service via SetupActivity
adb shell am start -n com.remoteaccess/.SetupActivity | Out-Null

# Wait until server lists the device (timeout ~20s)
$found = $false
1..20 | ForEach-Object {
  try {
    $resp = Invoke-RestMethod "$Api/devices" -TimeoutSec 2
    if ($resp.devices -contains $DeviceId) { $found = $true; break }
  } catch {}
  Start-Sleep -Milliseconds 800
}
if (-not $found) {
  Write-Host "Device not connected to server yet." -ForegroundColor Yellow
  Write-Host "Check: adb logcat -s RemoteAccess:I *:S" -ForegroundColor Yellow
  exit 2
}

Write-Host "Connected: $DeviceId" -ForegroundColor Green

# Ping
$p = Invoke-RestMethod -Method Post -Uri "$Api/command/$DeviceId" `
  -ContentType "application/json" -Body '{"action":"ping"}'
Write-Host "Ping response:" -ForegroundColor Cyan
$p | ConvertTo-Json -Depth 5

# Device info
$info = Invoke-RestMethod -Method Post -Uri "$Api/command/$DeviceId" `
  -ContentType "application/json" -Body '{"action":"get_device_info"}'
Write-Host "Device info:" -ForegroundColor Cyan
$info | ConvertTo-Json -Depth 5
