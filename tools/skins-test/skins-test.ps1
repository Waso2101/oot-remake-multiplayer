# Custom models TEST build: puts this test's files into a Squadala kit, and takes them out again.
# Unofficial (Waso2101's fork, issue 250), for testing only. Never part of an official kit.
#
#   powershell -ExecutionPolicy Bypass -File skins-test.ps1 -Install [-Kit <kit folder>]
#   powershell -ExecutionPolicy Bypass -File skins-test.ps1 -Remove  [-Kit <kit folder>]
#   powershell -ExecutionPolicy Bypass -File skins-test.ps1 -Status  [-Kit <kit folder>]
#
# The folder this script is in holds payload\ (files at their kit paths) and BUILD.txt (which kit release it is
# for). The kit is the folder given, else the one this folder sits in, else this folder itself (the one with
# VERSION.txt and "Start OoT Co-op.bat").
#
# Install: checks the kit's release is the one this test was built for and that the game and server are closed;
# keeps a copy of every kit file it replaces (backup\ here, with state.json), copies payload\ in, turns the kit's
# auto_update off (an update would overwrite the test, and a newer kit does not fit it), makes
# hookshot\game\coop-models with a shortcut in the kit folder, and has the next start make the puppet pack again.
# Remove: puts every kept file back, deletes the files the test added, puts auto_update back, removes the
# shortcut and has the next start make the puppet pack again. The models in coop-models stay (said, not deleted).
param(
    [switch]$Install,
    [switch]$Remove,
    [switch]$Status,
    [string]$Kit = '',
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$payload = Join-Path $here 'payload'
$backup = Join-Path $here 'backup'
$stateFile = Join-Path $backup 'state.json'
$shortcutName = 'Custom models folder (put model mods here).lnk'
$packManifestRel = 'hookshot\game\mods\contents\0400486024DEC000\coop-puppet\coop_puppet.json'

function Say([string]$Text, [string]$Color = '') {
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}

function Stop-With([string]$Text) {
    Say ''
    Say $Text 'Red'
    Done 1
}

function Done([int]$Code) {
    if (-not $NoPause) {
        Say ''
        Read-Host 'Press Enter to close' | Out-Null
    }
    exit $Code
}

function Test-KitFolder([string]$Dir) {
    return $Dir -and (Test-Path -LiteralPath (Join-Path $Dir 'VERSION.txt')) -and
        (Test-Path -LiteralPath (Join-Path $Dir 'hookshot'))
}

function Find-Kit {
    if ($Kit) {
        if (Test-KitFolder $Kit) { return (Resolve-Path -LiteralPath $Kit).Path }
        Stop-With "No Squadala kit in $Kit (no VERSION.txt and hookshot folder there)."
    }
    $parent = Split-Path -Parent $here
    foreach ($d in @($parent, $here)) {
        if (Test-KitFolder $d) { return (Resolve-Path -LiteralPath $d).Path }
    }
    Stop-With ("This folder is not inside a Squadala kit.`n" +
        "Unzip it into your kit folder (the one with 'Start OoT Co-op.bat' and VERSION.txt), then run it again.")
}

# "release v0.11.4" from the kit's VERSION.txt ('kit: Squadala-v0.11.4 (release v0.11.4)').
function Get-KitRelease([string]$KitDir) {
    $text = [System.IO.File]::ReadAllText((Join-Path $KitDir 'VERSION.txt'))
    if ($text -match '\(release (v[0-9][0-9A-Za-z._-]*)\)') { return $Matches[1] }
    return ''
}

function Get-BuildInfo {
    $f = Join-Path $here 'BUILD.txt'
    if (-not (Test-Path -LiteralPath $f)) { Stop-With 'BUILD.txt is missing from this folder: unzip the whole test zip again.' }
    $info = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($f)) {
        if ($line -match '^([a-z_]+):\s*(.*)$') { $info[$Matches[1]] = $Matches[2].Trim() }
    }
    return $info
}

function Get-PayloadFiles {
    if (-not (Test-Path -LiteralPath $payload)) { Stop-With 'payload\ is missing from this folder: unzip the whole test zip again.' }
    $root = [System.IO.Path]::GetFullPath($payload).TrimEnd('\') + '\'
    return @(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length) } | Sort-Object)
}

function Get-Sha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-GameRunning([string]$KitDir) {
    $kitFull = [System.IO.Path]::GetFullPath($KitDir).TrimEnd('\') + '\'
    foreach ($name in @('longshot', 'coop_server', 'hookshot')) {
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            $path = ''
            try { $path = $p.Path } catch { }
            if (-not $path -or $path.StartsWith($kitFull, [StringComparison]::OrdinalIgnoreCase)) { return $p.ProcessName }
        }
    }
    return ''
}

function Read-State {
    if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
    return ([System.IO.File]::ReadAllText($stateFile) | ConvertFrom-Json)
}

# auto_update in coop-options.ini: its current line ('' when absent), and setting it.
function Get-OptionLine([string]$Ini, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Ini)) { return '' }
    foreach ($l in [System.IO.File]::ReadAllLines($Ini)) {
        if ($l -match "^\s*$([regex]::Escape($Key))\s*=") { return $l }
    }
    return ''
}
function Set-OptionLine([string]$Ini, [string]$Key, [string]$Line) {
    $lines = @()
    if (Test-Path -LiteralPath $Ini) { $lines = @([System.IO.File]::ReadAllLines($Ini)) }
    $out = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach ($l in $lines) {
        if ($l -match "^\s*$([regex]::Escape($Key))\s*=") {
            if (-not $done -and $Line) { $out.Add($Line) }
            $done = $true
        } else { $out.Add($l) }
    }
    if (-not $done -and $Line) { $out.Add($Line) }
    [System.IO.File]::WriteAllLines($Ini, $out.ToArray())
}

function New-Shortcut([string]$Lnk, [string]$Target) {
    try {
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($Lnk)
        $s.TargetPath = $Target
        $s.Save()
    } catch {
        Say "  (could not make the shortcut: $($_.Exception.Message); the folder is $Target)" 'Yellow'
    }
}

function Invoke-PackRemake([string]$KitDir) {
    # The next start makes the puppet pack again (the kit sees no manifest), with or without the test's tool.
    $m = Join-Path $KitDir $packManifestRel
    if (Test-Path -LiteralPath $m) { Remove-Item -LiteralPath $m -Force }
}

function Do-Install([string]$KitDir) {
    $info = Get-BuildInfo
    $want = $info['kit_release']
    $have = Get-KitRelease $KitDir
    Say "Kit:   $KitDir ($(if ($have) { $have } else { 'release unknown' }))"
    Say "Test:  $($info['name']) ($($info['commit']), for kit $want)"
    if (Read-State) { Stop-With 'The test is already installed in this kit. Run Remove-CustomModels.bat first to install it again.' }
    if (-not $want) { Stop-With 'BUILD.txt names no kit release.' }
    if ($have -ne $want) {
        Stop-With ("This test is for kit $want, and this kit is $(if ($have) { $have } else { 'of an unknown release' }).`n" +
            "Update the kit first (Update.bat, or say yes when 'Start OoT Co-op.bat' offers it), then run this again.`n" +
            "Nothing was changed.")
    }
    $running = Test-GameRunning $KitDir
    if ($running) { Stop-With "Close the game and the server first ($running is running). Nothing was changed." }

    $files = Get-PayloadFiles
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    $kept = @()
    $added = @()
    foreach ($rel in $files) {
        $dst = Join-Path $KitDir $rel
        if (Test-Path -LiteralPath $dst) {
            $b = Join-Path $backup $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $b) | Out-Null
            Copy-Item -LiteralPath $dst -Destination $b -Force
            $kept += $rel
        } else {
            $added += $rel
        }
    }
    $ini = Join-Path $KitDir 'coop-options.ini'
    $state = [ordered]@{
        name = $info['name']; commit = $info['commit']; kit = $KitDir; kit_release = $have
        installed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        kept = $kept; added = $added
        installed_sha = @{}
        auto_update_line = (Get-OptionLine $ini 'auto_update')
    }
    # (the state first: a copy that stops half way can still be taken back by Remove)
    [System.IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Depth 4))
    foreach ($rel in $files) {
        $dst = Join-Path $KitDir $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Copy-Item -LiteralPath (Join-Path $payload $rel) -Destination $dst -Force
        $state.installed_sha[$rel] = Get-Sha $dst
        Say "  put in  $rel"
    }
    Set-OptionLine $ini 'auto_update' 'auto_update = no'
    Say '  auto_update = no in coop-options.ini (an update would overwrite the test)'
    $models = Join-Path $KitDir 'hookshot\game\coop-models'
    New-Item -ItemType Directory -Force -Path $models | Out-Null
    New-Shortcut (Join-Path $KitDir $shortcutName) $models
    Invoke-PackRemake $KitDir
    [System.IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Depth 4))
    Say ''
    Say 'Installed.' 'Green'
    Say "Custom models: put each model mod's folder (the one holding romfs) into"
    Say "  $models"
    Say "  (or open '$shortcutName' in the kit folder). Name each folder with letters/digits only, e.g. Malon."
    Say "Then start the kit as usual: the first start makes the puppet pack again (a minute or two)."
    Say "In the game: pause menu > Multiplayer > Customize Link > Characters."
    Say "Everyone you play with needs this same test build and the same model folders."
}

function Do-Remove([string]$KitDir) {
    $state = Read-State
    if (-not $state) { Stop-With 'The test is not installed in this kit (no backup\state.json here). Nothing to remove.' }
    $running = Test-GameRunning $KitDir
    if ($running) { Stop-With "Close the game and the server first ($running is running). Nothing was changed." }
    Say "Kit:   $KitDir"
    foreach ($rel in @($state.kept)) {
        $b = Join-Path $backup $rel
        if (Test-Path -LiteralPath $b) {
            Copy-Item -LiteralPath $b -Destination (Join-Path $KitDir $rel) -Force
            Say "  put back  $rel"
        } else {
            Say "  (no copy kept of ${rel}: left as it is)" 'Yellow'
        }
    }
    foreach ($rel in @($state.added)) {
        $dst = Join-Path $KitDir $rel
        if (Test-Path -LiteralPath $dst) {
            Remove-Item -LiteralPath $dst -Force
            Say "  removed   $rel"
        }
    }
    $ini = Join-Path $KitDir 'coop-options.ini'
    Set-OptionLine $ini 'auto_update' "$($state.auto_update_line)"
    Say "  auto_update back to: $(if ($state.auto_update_line) { $state.auto_update_line.Trim() } else { '(not set: the kit default, ask)' })"
    $lnk = Join-Path $KitDir $shortcutName
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
    Invoke-PackRemake $KitDir
    Remove-Item -LiteralPath $backup -Recurse -Force
    $models = Join-Path $KitDir 'hookshot\game\coop-models'
    Say ''
    Say 'Removed: the kit is the official one again. The next start makes the puppet pack again.' 'Green'
    if (Test-Path -LiteralPath $models) {
        Say "Your model folders are still in $models (the official kit ignores them). Delete them yourself if you like."
    }
}

function Do-Status([string]$KitDir) {
    $state = Read-State
    $info = Get-BuildInfo
    Say "Kit:   $KitDir ($(Get-KitRelease $KitDir))"
    Say "Test:  $($info['name']) ($($info['commit']), for kit $($info['kit_release']))"
    if (-not $state) { Say 'Installed: no'; return }
    Say "Installed: yes, $($state.installed)"
    $changed = @()
    foreach ($p in @($state.installed_sha.PSObject.Properties)) {
        $dst = Join-Path $KitDir $p.Name
        if (-not (Test-Path -LiteralPath $dst) -or (Get-Sha $dst) -ne $p.Value) { $changed += $p.Name }
    }
    if ($changed) { Say "Changed since (an update?): $($changed -join ', ')" 'Yellow' } else { Say 'All test files in place.' }
}

if ((@($Install, $Remove, $Status) | Where-Object { $_ }).Count -ne 1) {
    Say 'Use one of -Install, -Remove or -Status.'
    Done 2
}
$kitDir = Find-Kit
try {
    if ($Install) { Do-Install $kitDir }
    elseif ($Remove) { Do-Remove $kitDir }
    else { Do-Status $kitDir }
} catch {
    Stop-With "Stopped: $($_.Exception.Message)`nIf files were already copied, Remove-CustomModels.bat puts the kit back."
}
Done 0
