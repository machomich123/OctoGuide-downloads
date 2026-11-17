param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pkg = Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw | ConvertFrom-Json
$version = [string]$pkg.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Node launcher version.' }
$bundle = Join-Path $root "crew-next-$version.zip"
$manifest = Join-Path $root 'update.json'
$temp = Join-Path $env:TEMP ('crew-next-check-' + [guid]::NewGuid().ToString('N'))
if (-not $VerifyOnly) {
    if (Test-Path -LiteralPath $bundle) { Remove-Item -LiteralPath $bundle }
    Compress-Archive -Path (Join-Path $root 'package.json'),
        (Join-Path $root 'src'),(Join-Path $root 'public') -DestinationPath $bundle
    $release = [ordered]@{
        version = $version
        bundleUrl = "https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/crew-next-$version.zip"
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $bundle).Hash
        bootstrapSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'bootstrap.mjs')).Hash
        extractorSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'src\safe-zip.mjs')).Hash
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
if ((Get-FileHash (Join-Path $root 'bootstrap.mjs')).Hash -ne $published.bootstrapSha256 -or
    (Get-FileHash (Join-Path $root 'src\safe-zip.mjs')).Hash -ne $published.extractorSha256) {
    throw 'Bootstrap or extraction module differs from the release metadata.'
}
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    Expand-Archive -LiteralPath $bundle -DestinationPath $temp
    $expected = @(Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'public') -File -Recurse) +
        @(Get-Item (Join-Path $root 'package.json'))
    foreach ($file in $expected) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\','/')
        $archiveFile = Join-Path $temp $relative
        if (-not (Test-Path -LiteralPath $archiveFile) -or
            (Get-FileHash $archiveFile).Hash -ne (Get-FileHash $file.FullName).Hash) {
            throw "Release bundle contains missing/stale file: $relative"
        }
    }
    Write-Host "PASS: Crew Next $version bundle and source hashes match ($($expected.Count) files)."
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
