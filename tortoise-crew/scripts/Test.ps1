param([string]$SignedSample = 'C:\Program Files\Git\cmd\git.exe')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach ($test in @('LauncherUpdateTests', 'AddonImportSafetyTests', 'LoginRegressionTests')) {
    if ($test -eq 'LauncherUpdateTests') { & (Join-Path $repo "out\$test.exe") $SignedSample }
    elseif ($test -eq 'LoginRegressionTests') {
        & (Join-Path $repo "out\$test.exe") (Join-Path $repo 'out/login-native/native-login-fixture.exe') (Join-Path $repo 'out/login-native/CrewLogin.dll')
    }
    else { & (Join-Path $repo "out\$test.exe") }
    if ($LASTEXITCODE -ne 0) { throw "$test failed." }
}
