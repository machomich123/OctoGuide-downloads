param([Parameter(Mandatory)][string]$Executable)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Executable = (Resolve-Path -LiteralPath $Executable).Path
# All checks precede writes to the public EXE/manifest pair. Never publish an
# unsigned build just because compilation or a checksum test succeeded.
$signature = Get-AuthenticodeSignature -LiteralPath $Executable
if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
    throw "Release blocked: Windows-trusted Authenticode signature required ($($signature.Status)). Public files unchanged."
}
$version = [Reflection.AssemblyName]::GetAssemblyName($Executable).Version
if ($version.ToString() -ne '1.0.9.0') { throw "Release blocked: expected 1.0.9.0, got $version" }
$eku = @($signature.SignerCertificate.EnhancedKeyUsageList | ForEach-Object { [string]$_.ObjectId })
if ('1.3.6.1.5.5.7.3.3' -notin $eku) { throw 'Release certificate does not permit code signing.' }
if (-not $signature.TimeStamperCertificate) { throw 'Release requires an Authenticode timestamp.' }
$manifestPath = Join-Path $repo 'tortoise-crew\manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.launcherUrl -ne 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/TortoiseCrewLauncher.exe') {
    throw 'Unexpected distribution URL.'
}
$hash = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash
$manifest.launcherVersion = $version.ToString(3)
$manifest.launcherSha256 = $hash
$manifest.message = 'v1.0.9: signed updates, corrected version detection, serialized installation and desktop activation.'
$manifest | Add-Member -NotePropertyName updatesPaused -NotePropertyValue $false -Force
$publicExe = Join-Path $repo 'tortoise-crew\TortoiseCrewLauncher.exe'
if ($Executable -ne $publicExe) { Copy-Item -LiteralPath $Executable -Destination $publicExe -Force }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "Prepared signed release $($manifest.launcherVersion), SHA256 $hash."
