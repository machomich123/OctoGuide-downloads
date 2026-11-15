param([string]$SignedSample = 'C:\Program Files\Git\cmd\git.exe')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach ($test in @('LauncherUpdateTests', 'AddonImportSafetyTests')) {
    if ($test -eq 'LauncherUpdateTests') { & (Join-Path $repo "out\$test.exe") $SignedSample }
    else { & (Join-Path $repo "out\$test.exe") }
    if ($LASTEXITCODE -ne 0) { throw "$test failed." }
}
