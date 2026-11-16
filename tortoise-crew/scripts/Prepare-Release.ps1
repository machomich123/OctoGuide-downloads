param(
    [Parameter(Mandatory)][string]$Executable,
    [switch]$AllowUnsigned,
    [string]$LocallyTestedSha256
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Executable = (Resolve-Path -LiteralPath $Executable).Path
# CI defaults to signed publication. An explicitly requested unsigned release
# requires the exact hash of the artifact successfully launched on Windows.
# This is release evidence, not an override of Windows application control.
$hash = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
$signature = Get-AuthenticodeSignature -LiteralPath $Executable
$signatureMode = 'signed'
if ($signature.Status -eq 'NotSigned' -and $AllowUnsigned) {
    if ($LocallyTestedSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $LocallyTestedSha256 -ne $hash) {
        throw 'Release blocked: unsigned publication requires the exact locally tested SHA-256.'
    }
    $signatureMode = 'unsigned'
} elseif ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
    throw "Release blocked: Windows-trusted Authenticode signature required ($($signature.Status)). Public files unchanged."
}
$version = [Reflection.AssemblyName]::GetAssemblyName($Executable).Version
if ($version.ToString() -ne '1.0.10.0') { throw "Release blocked: expected 1.0.10.0, got $version" }
if ($signatureMode -eq 'signed') {
    $eku = @($signature.SignerCertificate.EnhancedKeyUsageList | ForEach-Object { [string]$_.ObjectId })
    if ('1.3.6.1.5.5.7.3.3' -notin $eku) { throw 'Release certificate does not permit code signing.' }
    if (-not $signature.TimeStamperCertificate) { throw 'Signed release requires an Authenticode timestamp.' }
}
$manifestPath = Join-Path $repo 'tortoise-crew\manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.launcherUrl -ne 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/TortoiseCrewLauncher.exe') {
    throw 'Unexpected distribution URL.'
}
$manifest.launcherVersion = $version.ToString(3)
$manifest.launcherSha256 = $hash
$manifest.message = 'v1.0.10: corrected version detection, safe update handoff and desktop activation. Windows decides whether unsigned builds may run.'
$manifest | Add-Member -NotePropertyName updatesPaused -NotePropertyValue $false -Force
$manifest | Add-Member -NotePropertyName releaseSignature -NotePropertyValue $signatureMode -Force
if ($signatureMode -eq 'unsigned') {
    $manifest | Add-Member -NotePropertyName locallyTestedSha256 -NotePropertyValue $hash -Force
} else { $manifest.PSObject.Properties.Remove('locallyTestedSha256') }
$publicExe = Join-Path $repo 'tortoise-crew\TortoiseCrewLauncher.exe'
if ($Executable -ne $publicExe) { Copy-Item -LiteralPath $Executable -Destination $publicExe -Force }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "Prepared $signatureMode release $($manifest.launcherVersion), SHA256 $hash."
