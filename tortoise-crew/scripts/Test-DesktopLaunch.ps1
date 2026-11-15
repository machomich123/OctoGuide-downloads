# Integration fixture on an ephemeral GitHub runner. Never run this against a
# user's installed launcher, and never change Windows application-control policy.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Desktop integration test is restricted to the disposable Windows CI runner.'
}
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$root = Join-Path $env:LOCALAPPDATA 'TortoiseCrewLauncher'
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$shortcut = Join-Path $desktop 'Tortoise Crew Launcher.lnk'
if ((Test-Path -LiteralPath $root) -or (Test-Path -LiteralPath $shortcut)) {
    throw 'Refusing to replace an existing launcher fixture.'
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$exe = Join-Path $root 'TortoiseCrewLauncher.exe'
Copy-Item -LiteralPath (Join-Path $repo 'out\TortoiseCrewLauncher.exe') -Destination $exe
function Wait-ForLauncher {
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $found = @(Get-Process -Name TortoiseCrewLauncher -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $exe -and $_.MainWindowHandle -ne 0 -and
                $_.MainWindowTitle -eq 'Tortoise Crew · Realm Launcher' })
        if ($found.Count -eq 1) { return $found[0] }
        Start-Sleep -Milliseconds 100
    }
    throw 'Expected launcher window did not open.'
}
try {
    # First run creates the same shortcut used by a real installed launcher.
    $startupId = [Guid]::NewGuid().ToString('N')
    Start-Process -FilePath $exe -ArgumentList @('--updated', $startupId) | Out-Null
    $first = Wait-ForLauncher
    $marker = Join-Path $root "update-started-$startupId.ready"
    if (-not (Test-Path -LiteralPath $marker)) { throw 'Real UI did not acknowledge updater startup.' }
    if (-not (Test-Path -LiteralPath $shortcut)) { throw 'Desktop shortcut was not created.' }
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    if ($link.TargetPath -ne $exe -or $link.WorkingDirectory -ne $root) { throw 'Incorrect desktop shortcut target.' }
    Stop-Process -Id $first.Id -Force
    $first.WaitForExit()

    Start-Process -FilePath $shortcut | Out-Null
    $opened = Wait-ForLauncher
    Start-Process -FilePath $shortcut | Out-Null
    Start-Sleep -Milliseconds 1000
    $instances = @(Get-Process -Name TortoiseCrewLauncher -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $exe })
    if ($instances.Count -ne 1 -or $instances[0].Id -ne $opened.Id) {
        throw 'Repeated desktop launch created a second instance.'
    }
    Write-Host 'PASS: startup acknowledgment, real desktop shortcut, window opening and repeated shortcut activation.'
}
finally {
    Get-Process -Name TortoiseCrewLauncher -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $exe } | Stop-Process -Force
}
