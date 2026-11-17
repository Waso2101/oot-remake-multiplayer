# Tests skins-test.ps1 on a made-up kit: install, status, remove, a wrong kit version, a second install.
#   powershell -ExecutionPolicy Bypass -File tools\skins-test\test_skins_test.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("skins-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fails = 0
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Host "ok   $What" } else { Write-Host "FAIL $What" -ForegroundColor Red; $script:fails++ }
}
function Put([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text)
}
function Text([string]$Path) { if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path) } else { '<none>' } }
function Run([string]$Mode) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $test 'skins-test.ps1') "-$Mode" -NoPause 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $out }
}
try {
    $kit = Join-Path $root 'Squadala-v0.11.4'
    Put (Join-Path $kit 'VERSION.txt') "kit: Squadala-v0.11.4 (release v0.11.4)`nkind: hookshot`n"
    Put (Join-Path $kit 'hookshot\hookshot_coop.dll') 'official dll'
    Put (Join-Path $kit 'scripts\kit-paths.ps1') 'official kit-paths'
    Put (Join-Path $kit 'coop-options.ini') "[co-op]`nauto_update = ask`ncolor = red`n"
    $manifest = Join-Path $kit 'hookshot\game\mods\contents\0400486024DEC000\coop-puppet\coop_puppet.json'
    Put $manifest '{}'
    $test = Join-Path $kit 'custom-models-test'
    foreach ($f in 'skins-test.ps1', 'README.txt') { Put (Join-Path $test $f) (Text (Join-Path $here $f)) }
    Put (Join-Path $test 'BUILD.txt') "name: t`nkit_release: v0.11.4`ncommit: abc`n"
    Put (Join-Path $test 'payload\hookshot\hookshot_coop.dll') 'test dll'
    Put (Join-Path $test 'payload\scripts\kit-paths.ps1') 'test kit-paths'
    Put (Join-Path $test 'payload\tools\puppet_pack\skin.py') 'test skin'

    $r = Run 'Install'
    Check ($r.Code -eq 0) "install: exit 0 ($($r.Code))"
    Check ((Text "$kit\hookshot\hookshot_coop.dll") -eq 'test dll') 'install: dll replaced'
    Check ((Text "$kit\tools\puppet_pack\skin.py") -eq 'test skin') 'install: new file added'
    Check ((Text "$kit\coop-options.ini") -match '(?m)^auto_update = no\r?$') 'install: auto_update = no'
    Check ((Text "$kit\coop-options.ini") -match 'color = red') 'install: other options kept'
    Check (Test-Path "$kit\hookshot\game\coop-models") 'install: coop-models made'
    Check (-not (Test-Path $manifest)) 'install: the pack is made again at the next start'
    Check ((Text "$test\backup\hookshot\hookshot_coop.dll") -eq 'official dll') 'install: original kept'

    $r = Run 'Install'
    Check ($r.Code -ne 0 -and $r.Out -match 'already installed') 'install twice: refused'
    $r = Run 'Status'
    Check ($r.Code -eq 0 -and $r.Out -match 'All test files in place') 'status: in place'
    Put "$kit\hookshot\hookshot_coop.dll" 'updated by someone'
    $r = Run 'Status'
    Check ($r.Out -match 'Changed since') 'status: a changed file is named'

    Put $manifest '{}'
    Put "$kit\hookshot\game\coop-models\Malon\romfs\a.txt" 'model'
    $r = Run 'Remove'
    Check ($r.Code -eq 0) "remove: exit 0 ($($r.Code))"
    Check ((Text "$kit\hookshot\hookshot_coop.dll") -eq 'official dll') 'remove: dll back'
    Check ((Text "$kit\scripts\kit-paths.ps1") -eq 'official kit-paths') 'remove: script back'
    Check (-not (Test-Path "$kit\tools\puppet_pack\skin.py")) 'remove: added file gone'
    Check ((Text "$kit\coop-options.ini") -match '(?m)^auto_update = ask\r?$') 'remove: auto_update back'
    Check (-not (Test-Path $manifest)) 'remove: the pack is made again at the next start'
    Check (-not (Test-Path "$test\backup")) 'remove: backup cleaned up'
    Check (Test-Path "$kit\hookshot\game\coop-models\Malon\romfs\a.txt") 'remove: the models stay'
    $r = Run 'Remove'
    Check ($r.Code -ne 0 -and $r.Out -match 'not installed') 'remove twice: nothing to remove'

    # No auto_update line before: removed again after.
    Put (Join-Path $kit 'coop-options.ini') "[co-op]`ncolor = red`n"
    [void](Run 'Install')
    [void](Run 'Remove')
    Check ((Text "$kit\coop-options.ini") -notmatch 'auto_update') 'no auto_update before: none after'

    Put (Join-Path $kit 'VERSION.txt') "kit: Squadala-v0.11.3 (release v0.11.3)`n"
    $r = Run 'Install'
    Check ($r.Code -ne 0 -and $r.Out -match 'for kit v0.11.4' -and $r.Out -match 'Nothing was changed') 'wrong kit: refused'
    Check ((Text "$kit\hookshot\hookshot_coop.dll") -eq 'official dll') 'wrong kit: nothing changed'

    Move-Item $test (Join-Path $root 'elsewhere')
    $test = Join-Path $root 'elsewhere'
    $r = Run 'Install'
    Check ($r.Code -ne 0 -and $r.Out -match 'not inside a Squadala kit') 'outside a kit: refused'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fails) { Write-Host "$fails failed" -ForegroundColor Red; exit 1 }
Write-Host 'all passed'
