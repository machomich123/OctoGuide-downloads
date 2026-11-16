param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$native = Join-Path (Split-Path $PSScriptRoot -Parent) 'native'
$fixture = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/native-login-fixture.c'
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$lua = [IO.File]::ReadAllBytes((Join-Path $native 'CrewLogin.lua'))
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'CrewLoginLua.h'), 'static const unsigned char crew_login_lua[] = {' + (($lua + 0) -join ',') + '};')
if ($env:CREW_NATIVE_COMPILER) {
    & $env:CREW_NATIVE_COMPILER -std=c11 -O2 -Wall -Wextra -Werror -shared '-Wl,--no-insert-timestamp' -I $OutputDirectory -o (Join-Path $OutputDirectory 'CrewLogin.dll') (Join-Path $native 'CrewLogin.c') -lcrypt32
    if ($LASTEXITCODE -ne 0) { throw 'Native login module compilation failed.' }
    & $env:CREW_NATIVE_COMPILER -std=c11 -O2 -Wall -Wextra -Werror '-Wl,--image-base,0x400000,--disable-dynamicbase' -o (Join-Path $OutputDirectory 'native-login-fixture.exe') $fixture -lcrypt32
    if ($LASTEXITCODE -ne 0) { throw 'Native fixture compilation failed.' }
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Visual C++ x86 build tools are required.' }
    $batch = Join-Path $OutputDirectory 'compile-native.cmd'
    $lines = @('@echo off', "call `"$vs\Common7\Tools\VsDevCmd.bat`" -arch=x86 -host_arch=x64 >nul", 'if errorlevel 1 exit /b 1',
        "cd /d `"$OutputDirectory`"",
        "cl /nologo /std:c11 /O2 /W3 /LD /I `"$OutputDirectory`" /Fe:`"$OutputDirectory\CrewLogin.dll`" `"$native\CrewLogin.c`" crypt32.lib",
        'if errorlevel 1 exit /b 1',
        "cl /nologo /std:c11 /O2 /W3 /Fe:`"$OutputDirectory\native-login-fixture.exe`" `"$fixture`" crypt32.lib /link /BASE:0x400000 /DYNAMICBASE:NO",
        'if errorlevel 1 exit /b 1')
    [IO.File]::WriteAllLines($batch, $lines, [Text.Encoding]::ASCII)
    & $env:ComSpec /d /c $batch
    if ($LASTEXITCODE -ne 0) { throw 'Visual C++ native build failed.' }
}
