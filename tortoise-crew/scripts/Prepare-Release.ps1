param(
    [Parameter(Mandatory)][string]$Executable,
    [switch]$AllowUnsigned,
    [string]$LocallyTestedSha256,
    [long]$WindowsCiRunId
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Executable = (Resolve-Path -LiteralPath $Executable).Path
# Windows blocked the exact CI-tested unsigned artifact. Neither CI provenance
# nor a matching hash substitutes for a publicly trusted publisher signature.
if ($AllowUnsigned) {
    throw 'Release blocked: Windows-trusted signature required; unsigned publication is disabled even with Windows CI evidence. Public files unchanged.'
}
$hash = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
$signature = Get-AuthenticodeSignature -LiteralPath $Executable
$signatureMode = 'signed'
if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
    throw "Release blocked: Windows-trusted Authenticode signature required ($($signature.Status)). Public files unchanged."
}
$version = [Reflection.AssemblyName]::GetAssemblyName($Executable).Version
if ($version.ToString() -ne '1.0.12.0') { throw "Release blocked: expected 1.0.12.0, got $version" }
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
$manifest.message = 'v1.0.12: correct Vanilla/Turtle addon import and Repair addons with backups and dependency checks.'
$manifest | Add-Member -NotePropertyName updatesPaused -NotePropertyValue $false -Force
$manifest | Add-Member -NotePropertyName releaseSignature -NotePropertyValue $signatureMode -Force
foreach ($name in @('locallyTestedSha256','windowsTestedSha256','windowsTestRun')) { $manifest.PSObject.Properties.Remove($name) }
$publicExe = Join-Path $repo 'tortoise-crew\TortoiseCrewLauncher.exe'
if ($Executable -ne $publicExe) { Copy-Item -LiteralPath $Executable -Destination $publicExe -Force }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "Prepared $signatureMode release $($manifest.launcherVersion), SHA256 $hash."
