param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pkg = Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json
$version = [string]$pkg.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Node launcher version.' }
$bundle = Join-Path $root "crew-next-$version.zip"
$manifest = Join-Path $root 'update.json'
$temp = Join-Path $env:TEMP ('crew-next-check-' + [guid]::NewGuid().ToString('N'))
$expected = @(Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'public') -File -Recurse) +
    @(Get-Item (Join-Path $root 'package.json'))
$utf8 = New-Object Text.UTF8Encoding($false)
function CanonicalBytes([string]$file) {
    $value = [IO.File]::ReadAllText($file).Replace(([string][char]13 + [char]10), [string][char]10)
    return ,($utf8.GetBytes($value))
}
function CanonicalSha256([string]$file) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash((CanonicalBytes $file))).Replace('-', '') }
    finally { $sha.Dispose() }
}
if (-not $VerifyOnly) {
    $stage = Join-Path $env:TEMP ('crew-next-stage-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        foreach ($file in $expected) {
            $relative = $file.FullName.Substring($root.Length).TrimStart('\','/')
            $dest = Join-Path $stage $relative
            New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
            [IO.File]::WriteAllBytes($dest, (CanonicalBytes $file.FullName))
        }
        if (Test-Path -LiteralPath $bundle) { Remove-Item -LiteralPath $bundle }
        Compress-Archive -Path (Join-Path $stage 'package.json'),
            (Join-Path $stage 'src'),(Join-Path $stage 'public') -DestinationPath $bundle
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    $release = [ordered]@{
        version = $version
        bundleUrl = "https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/crew-next-$version.zip"
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $bundle).Hash
        bootstrapSha256 = CanonicalSha256 (Join-Path $root 'bootstrap.mjs')
        extractorSha256 = CanonicalSha256 (Join-Path $root 'src\safe-zip.mjs')
        format = 'crew-next-v1'
    }
    [IO.File]::WriteAllText($manifest,
        (($release | ConvertTo-Json -Depth 4) + [Environment]::NewLine),
        (New-Object Text.UTF8Encoding($false)))
}
$published = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
if ($published.version -ne $version) { throw 'Release metadata version mismatch.' }
if ((Get-FileHash -LiteralPath $bundle).Hash -ne $published.sha256) {
    throw 'Release ZIP does not match published SHA256.'
}
if ((CanonicalSha256 (Join-Path $root 'bootstrap.mjs')) -ne $published.bootstrapSha256 -or
    (CanonicalSha256 (Join-Path $root 'src\safe-zip.mjs')) -ne $published.extractorSha256) {
    throw 'Bootstrap or extraction module differs from the release metadata.'
}
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    Expand-Archive -LiteralPath $bundle -DestinationPath $temp
    foreach ($file in $expected) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\','/')
        $archiveFile = Join-Path $temp $relative
        if (-not (Test-Path -LiteralPath $archiveFile) -or
            (Get-FileHash $archiveFile).Hash -ne (CanonicalSha256 $file.FullName)) {
            throw "Release bundle contains missing/stale file: $relative"
        }
    }
    Write-Host "PASS: Crew Next $version bundle and source hashes match ($($expected.Count) files)."
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
