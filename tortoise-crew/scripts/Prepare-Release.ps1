param(
    [Parameter(Mandatory)][string]$Executable,
    [switch]$AllowUnsigned,
    [string]$LocallyTestedSha256,
    [long]$WindowsCiRunId,
    [string]$WindowsPolicyVerifiedSha256
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
$windowsCiUrl = $null
if ($signature.Status -eq 'NotSigned' -and $AllowUnsigned) {
    # An operator must record successful execution of this exact artifact on
    # the affected PC with its existing application-control policy intact.
    # CI provenance alone does not satisfy this release condition.
    if ($WindowsPolicyVerifiedSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $WindowsPolicyVerifiedSha256 -ne $hash) {
        throw 'Release blocked: unsigned publication requires the exact SHA-256 verified running on the affected Windows PC with protection unchanged. CI alone is insufficient.'
    }
    if ($WindowsCiRunId) {
        # Verify exact artifact provenance and real Windows startup, rather than
        # treating a local compile or a supplied checksum as execution evidence.
        $repository = 'machomich123/OctoGuide-downloads'
        $run = & gh api "repos/$repository/actions/runs/$WindowsCiRunId" | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or $run.conclusion -ne 'success' -or
            $run.path -ne '.github/workflows/build-tortoise-crew.yml' -or
            $run.head_repository.full_name -ne $repository) {
            throw 'Release blocked: successful trusted Windows CI run required.'
        }
        & git -C $repo merge-base --is-ancestor $run.head_sha HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Release blocked: CI source is not an ancestor of this checkout.' }
        & git -C $repo diff --quiet $run.head_sha -- tortoise-crew/src tortoise-crew/native tortoise-crew/scripts/Build.ps1 tortoise-crew/scripts/Build-Native.ps1
        if ($LASTEXITCODE -ne 0) { throw 'Release blocked: application source differs from the Windows-tested build.' }
        $jobs = & gh api "repos/$repository/actions/runs/$WindowsCiRunId/jobs" | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Release blocked: cannot inspect Windows CI checks.' }
        $required = @('Compile launcher and regression suites', 'Run update and addon regression suites',
            'Test real desktop shortcut on the disposable runner')
        foreach ($step in $required) {
            if (-not @($jobs.jobs | Where-Object conclusion -eq 'success' | ForEach-Object steps |
                Where-Object { $_.name -eq $step -and $_.conclusion -eq 'success' }).Count) {
                throw "Release blocked: Windows CI check missing: $step"
            }
        }
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('crew-release-proof-' + [guid]::NewGuid().ToString('N'))
        try {
        & gh run download $WindowsCiRunId --repo $repository --name 'TortoiseCrewLauncher-v1.0.13-UNSIGNED-DO-NOT-INSTALL' --dir $temporary
            if ($LASTEXITCODE -ne 0 -or
                (Get-FileHash -LiteralPath (Join-Path $temporary 'TortoiseCrewLauncher.exe') -Algorithm SHA256).Hash -ne $hash) {
                throw 'Release blocked: executable differs from the Windows-tested CI artifact.'
            }
        } finally {
            # Delete only the two exact files/directories created for this proof.
            if (Test-Path -LiteralPath (Join-Path $temporary 'TortoiseCrewLauncher.exe')) {
                Remove-Item -LiteralPath (Join-Path $temporary 'TortoiseCrewLauncher.exe')
            }
            if (Test-Path -LiteralPath $temporary) { [IO.Directory]::Delete($temporary) }
        }
        $windowsCiUrl = $run.html_url
    } elseif ($LocallyTestedSha256 -notmatch '^[0-9a-fA-F]{64}$' -or $LocallyTestedSha256 -ne $hash) {
        throw 'Release blocked: unsigned publication requires exact Windows execution evidence.'
    }
    $signatureMode = 'unsigned'
} elseif ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
    throw "Release blocked: Windows-trusted Authenticode signature required ($($signature.Status)). Public files unchanged."
}
$version = [Reflection.AssemblyName]::GetAssemblyName($Executable).Version
if ($version.ToString() -ne '1.0.13.0') { throw "Release blocked: expected 1.0.13.0, got $version" }
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
$manifest.message = 'v1.0.13: migrate to Tortoise Crew Next with local Node UI and guarded shortcuts; keep the previous launcher for recovery.'
$manifest | Add-Member -NotePropertyName updatesPaused -NotePropertyValue $false -Force
$manifest | Add-Member -NotePropertyName releaseSignature -NotePropertyValue $signatureMode -Force
if ($signatureMode -eq 'unsigned') {
    $manifest | Add-Member -NotePropertyName windowsPolicyVerifiedSha256 -NotePropertyValue $hash -Force
    if ($windowsCiUrl) {
        $manifest.PSObject.Properties.Remove('locallyTestedSha256')
        $manifest | Add-Member -NotePropertyName windowsTestedSha256 -NotePropertyValue $hash -Force
        $manifest | Add-Member -NotePropertyName windowsTestRun -NotePropertyValue $windowsCiUrl -Force
    } else {
        $manifest | Add-Member -NotePropertyName locallyTestedSha256 -NotePropertyValue $hash -Force
    }
} else { $manifest.PSObject.Properties.Remove('locallyTestedSha256') }
$publicExe = Join-Path $repo 'tortoise-crew\TortoiseCrewLauncher.exe'
if ($Executable -ne $publicExe) { Copy-Item -LiteralPath $Executable -Destination $publicExe -Force }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "Prepared $signatureMode release $($manifest.launcherVersion), SHA256 $hash."
