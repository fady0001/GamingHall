# Computes the same device code that the Gaming Hall lock screen shows.
# Mirrors lib/core/security/hardware_fingerprint_service.dart:
#   sha256("GL1|" + lowercase(MachineGuid)) -> first 32 hex chars, upper-case, XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX

$guid = $null
try {
    $guid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction Stop).MachineGuid
} catch {}
if ([string]::IsNullOrWhiteSpace($guid)) {
    try { $guid = (Get-CimInstance Win32_ComputerSystemProduct).UUID } catch {}
}
if ([string]::IsNullOrWhiteSpace($guid)) {
    Write-Host "Could not read the device identifier." -ForegroundColor Red
    exit 1
}

$guid = $guid.Trim().ToLower()
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("GL1|$guid"))
$hex = (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 32).ToUpper()
$code = @($hex.Substring(0,8), $hex.Substring(8,8), $hex.Substring(16,8), $hex.Substring(24,8)) -join '-'

Write-Host ""
Write-Host "Device code:" -ForegroundColor Cyan
Write-Host $code -ForegroundColor Green
try { Set-Clipboard -Value $code; Write-Host "(copied to clipboard)" } catch {}
Write-Host ""
