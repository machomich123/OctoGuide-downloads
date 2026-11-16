param([string]$Compiler)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $Compiler) {
    $Compiler = 'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\Roslyn\csc.exe'
}
if (-not (Test-Path -LiteralPath $Compiler)) { throw 'A Roslyn C# compiler is required.' }
$out = Join-Path $repo 'out'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$sources = @(Get-ChildItem (Join-Path $repo 'tortoise-crew\src\*.cs') | ForEach-Object FullName)
$refs = @('/reference:System.Xml.dll','/reference:System.dll','/reference:System.Core.dll','/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll',
    '/reference:System.Net.Http.dll','/reference:Microsoft.CSharp.dll','/reference:System.Security.dll',
    '/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll')
$native = Join-Path $repo 'tortoise-crew\native'
$nativeOut = Join-Path $out 'login-native'
New-Item -ItemType Directory -Path $nativeOut -Force | Out-Null
& (Join-Path $PSScriptRoot 'Build-Native.ps1') -OutputDirectory $nativeOut
$resources = @('/resource:' + (Join-Path $nativeOut 'CrewLogin.dll') + ',CrewLogin.CrewLogin.dll')
foreach ($file in @('wowreeb32.exe','wowreeb32.dll','LICENSE.txt')) {
    $resources += '/resource:' + (Join-Path $native "vendor\$file") + ",CrewLogin.$file"
}
$base = @('/nologo','/langversion:latest','/platform:anycpu','/optimize+') + $refs + $sources + $resources
$launcher = Join-Path $out 'TortoiseCrewLauncher.exe'
& $Compiler @base /target:winexe "/out:$launcher"
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
$version = [Reflection.AssemblyName]::GetAssemblyName($launcher).Version.ToString()
if ($version -ne '1.0.10.0') { throw "Unexpected assembly version: $version" }
foreach ($test in @('LauncherUpdateTests', 'AddonImportSafetyTests', 'LoginRegressionTests')) {
    $testSource = Join-Path $repo "tortoise-crew\tests\$test.cs"
    & $Compiler @base /target:exe "/main:TortoiseCrew.$test" "/out:$out\$test.exe" $testSource
    if ($LASTEXITCODE -ne 0) { throw "$test compilation failed." }
}
Write-Host "Built Tortoise Crew $version, native login module and regression suites."
