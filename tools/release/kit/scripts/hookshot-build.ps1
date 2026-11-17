# Builds a co-op Longshot game on this PC from your own copy of the game, then puts co-op in it.
# Build-Hookshot-Coop.bat runs this. Longshot (git.magicbean.dev/MagicBeanDev/Longshot, Team MagicBean, GPL-3.0) is a static
# recompilation of the game: it is built here, from your files, and never leaves this PC.
#
#   Build-Hookshot-Coop.bat                         finds your .nup (as make-puppet-pack.cmd does), else asks
#   Build-Hookshot-Coop.bat -Game <your .nup>       no questions
#   Build-Hookshot-Coop.bat -Game <romfs folder> -Exefs <exefs folder>
#   Build-Hookshot-Coop.bat -Out <folder>           where the game goes (default: hookshot\game in this kit)
#   Build-Hookshot-Coop.bat -Language en-US         the game's language (Hookshot's codes; default en-US)
#   Build-Hookshot-Coop.bat -Rebuild                build again even when nothing changed
#   Build-Hookshot-Coop.bat -Jobs <n>               at most n compilers at once
#   Build-Hookshot-Coop.bat -CheckOnly              get the tools and check your game files; build nothing
#   Build-Hookshot-Coop.bat -PackOnly               only make the puppet pack again (make-puppet-pack.cmd)
#   (for tools\hookshot\hs.py) -Tools <folder> -Work <folder>: Hookshot's tools and source, and its work folder,
#   somewhere else than this kit's hookshot\ (one of each per pin, shared by every kit: hs-build-speed)
#
# What it does:
# 1. Hookshot's own build tools: the parts of the Hookshot release named in hookshot\TOOLS.txt (its
#    Python, llvm-mingw, the Vulkan/FFmpeg headers and the prebuilt third-party files),
#    downloaded from Longshot's release (git.magicbean.dev) and checked against the SHA-256 in that release's
#    hookshot-setup.txt (whose own SHA-256 is in TOOLS.txt). About 400 MB, once. Each download is tried several
#    times, then with curl.exe, then from the co-op mirror (TOOLS.txt mirror=); nothing unverified is used.
# 2. Hookshot's source at the commit in hookshot\PIN (GitHub's source archive), with our patches
#    from hookshot\patches applied (scripts\apply_patch.py: no git needed).
# 3. Hookshot's own builder, nx2\make_game.py, on your .nup (or romfs + exefs): 10 to 45 minutes and
#    about 60 GB free while it runs. Its work folder is hookshot\work in this kit (kept: the next
#    build after a co-op update compiles only what changed).
# 4. Co-op into the game folder: hookshot_coop.dll beside longshot.exe, coop.ini (server and name,
#    from this kit's emulator\user\config\coop.ini when you have one), coop-options.ini, and the
#    puppet pack (built from your game, with the custom character models in coop-models beside the mods folder)
#    in the game's mods folder.
# Steps 1 to 3 are skipped when the tools, pin and patches are the ones the game was built with,
# so after Update.bat a run only does step 4 (a few minutes) unless the update moved the pin.
# When only the patches changed, step 2 puts the files the old ones changed back and applies the new
# ones (apply_patch.py --refresh), and step 3 is Hookshot's own incremental build: no new translation
# unless a lift file changed, and only the changed files compiled.
#
# Nothing in the kit holds the game: the tools are Hookshot's, the patches and the module are ours.
param(
    [string]$Game = '',
    [string]$Exefs = '',
    [string]$Out = '',
    [ValidatePattern('^[A-Za-z]{2}(-[A-Za-z]{2})?$')][string]$Language = 'en-US',
    [ValidateRange(0, 256)][int]$Jobs = 0,
    [string]$Tools = '',
    [string]$Work = '',
    [string]$RomfsFrom = '',   # (tools/hookshot/hs.py: another game folder of the same .nup, its game files hard-linked)
    [switch]$Rebuild,
    [switch]$CheckOnly,
    [switch]$PackOnly,
    # A Longshot game folder of the player's own (kit-friction): its saves and, through its builder, Longshot's downloads
    # (and compiled objects, same release only) are copied from it. 'none': do not ask. Asked once before a first build.
    [string]$Longshot = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # (Invoke-WebRequest's progress bar makes big downloads many times slower)

$kit = Split-Path -Parent $PSScriptRoot
$hs = Join-Path $kit 'hookshot'
. (Join-Path $PSScriptRoot 'kit-paths.ps1')   # (Test-KitOtherKitGame, Find-KitHookshotGameToCopy)
. (Join-Path $PSScriptRoot 'coop-ini.ps1')
. (Join-Path $PSScriptRoot 'console-mode.ps1')   # (Read-KitPath: the questions for a path, pasted, dragged or typed)
Set-KitTls   # (kit-mirror: Tls12 added to what Windows enables, and Tls13 where .NET has it; was Tls12 alone)

function Fail([string]$Text) { Write-Host ''; Write-Host "Longshot build: $Text" -ForegroundColor Red; exit 1 }
# (kit-friction) Anything this script did not expect: the step it was at, in plain words, and for "access denied" or a
# held file, who holds it (a 0.10.1 player saw only PowerShell's red error at a Move-Item, with no way to tell why).
trap {
    $m = $_.Exception.Message
    $at = $_.InvocationInfo
    Write-Host ''
    Write-Host "Longshot build: stopped at hookshot-build.ps1 line $($at.ScriptLineNumber) ($("$($at.Line)".Trim())):" -ForegroundColor Red
    Write-Host "  $m" -ForegroundColor Red
    if ($m -match '(?i)denied|being used by another process|cannot access the file') {
        $path = if ($m -match "'([A-Za-z]:\\[^']+)'") { $Matches[1] } else { '' }
        # (no path in the message: no holder scan, which over a built kit's game\ would open thousands of files)
        if ($path) {
            $folder = if (Test-Path -LiteralPath $path -PathType Container) { $path } else { Split-Path -Parent $path }
            Write-Host (Get-KitHeldFolderText $folder 'access denied') -ForegroundColor Yellow
        } else {
            Write-Host (Get-KitHeldFolderText $kit 'access denied' @() '') -ForegroundColor Yellow
        }
    } elseif ($m -match '(?i)application control|blocked by|virus|potentially unwanted') {
        Write-Host '  Windows or the antivirus blocked a program of the build: Windows Security > Protection history says which; allow it, or add this kit''s folder under Exclusions. Smart App Control (Windows 11) blocks it whatever Defender''s settings (SETUP.md, "If something goes wrong").' -ForegroundColor Yellow
    }
    Write-Host '  Start again once that is done; what was downloaded is kept. Still stuck: scripts\collect-logs.cmd, and attach its zip to /bugreport on the Discord.'
    exit 1
}
function Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Read-KeyFile([string]$Path) {
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.+?)\s*$') { $map[$Matches[1]] = $Matches[2] }
    }
    return $map
}
function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
# $Urls are tried in order (tools.lock gives several), then the co-op mirror's copy ($MirrorName under TOOLS.txt's
# mirror=): each with retries and curl.exe, always checked against $Sha256 (kit-paths.ps1, Get-KitDownload).
function Get-Download([string[]]$Urls, [string]$To, [string]$Sha256, [string]$MirrorName = '') {
    $mirrors = if ($mirror -and $MirrorName) { @("$mirror/$MirrorName") } else { @() }
    $why = Get-KitDownload $Urls $To $Sha256 $mirrors
    if ($why) { Fail (Get-KitDownloadFailText (Split-Path -Leaf $To) $why $Urls[0] ([bool]$mirrors)) }
}
# -Member: only that folder of the zip, its path left out; -Keep: files already there are not overwritten.
function Expand-Zip([string]$Zip, [string]$To, [int]$Strip = 0, [string]$Member = '', [switch]$Keep) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    $tarArgs = @('-x', '-f', $Zip, '-C', $To)
    if ($Keep) { $tarArgs += '-k' }
    if ($Member) { $Strip = @($Member -split '/').Count }
    if ($Strip) { $tarArgs += "--strip-components=$Strip" }
    if ($Member) { $tarArgs += "$Member/" }
    & "$env:SystemRoot\System32\tar.exe" @tarArgs
    if ($LASTEXITCODE -ne 0) { Fail "Unpacking $(Split-Path -Leaf $Zip) failed (tar $LASTEXITCODE). Is the disk full?" }
}

# --- What this kit has ---------------------------------------------------------------------
if (-not [Environment]::Is64BitOperatingSystem) { Fail 'Longshot needs 64-bit Windows.' }
foreach ($need in 'PIN', 'TOOLS.txt') {
    if (-not (Test-Path -LiteralPath (Join-Path $hs $need))) { Fail "This kit has no hookshot\$need. Get a kit with Hookshot support (Update.bat)." }
}
$patches = @(Get-ChildItem -LiteralPath (Join-Path $hs 'patches') -Filter '*.patch' -File -ErrorAction SilentlyContinue | Sort-Object Name)
if (-not $patches) { Fail 'This kit has no hookshot\patches\*.patch.' }
$pin = Read-KeyFile (Join-Path $hs 'PIN')
$toolsPin = Read-KeyFile (Join-Path $hs 'TOOLS.txt')
foreach ($k in 'repo', 'commit') { if (-not $pin[$k]) { Fail "hookshot\PIN has no $k=." } }
foreach ($k in 'release', 'lock_sha256', 'source_commit', 'source_sha256') { if (-not $toolsPin[$k]) { Fail "hookshot\TOOLS.txt has no $k=." } }
if ($pin.commit -notmatch '^[0-9a-f]{40}$') { Fail "hookshot\PIN: commit=$($pin.commit) is not a full commit id." }
# (Longshot lives on Team MagicBean's Forgejo; its release files and source archive come from there)
if ($pin.repo -notmatch '^(https://git\.magicbean\.dev)/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(\.git)?$') { Fail "hookshot\PIN: repo=$($pin.repo) is not a git.magicbean.dev repository." }
$repoUrl = "$($Matches[1])/$($Matches[2])"
# (Forgejo's API archive: the web /archive/ path answers 404 since 2026-11-13; same bytes, so it is tried first)
$apiUrl = "$($Matches[1])/api/v1/repos/$($Matches[2])"
# The co-op mirror (kit-mirror): a GitHub release of ours with the same pinned files (tools/release/mirror_longshot.ps1),
# tried after Longshot's own servers. OOT_COOP_MIRROR (tests) points it elsewhere.
$mirror = if ($env:OOT_COOP_MIRROR) { $env:OOT_COOP_MIRROR } else { "$($toolsPin.mirror)" }
$mirror = $mirror.TrimEnd('/')
if ($mirror -and $mirror -notmatch '^(https|file)://') { Fail "hookshot\TOOLS.txt: mirror=$mirror is not an https:// address." }
# The source archive's SHA-256 in TOOLS.txt is for one commit: it must be PIN's.
if ($toolsPin.source_commit -ne $pin.commit) {
    Fail "hookshot\TOOLS.txt pins the source archive of $($toolsPin.source_commit), but hookshot\PIN says $($pin.commit). This kit is broken: tell the co-op testers."
}
$patchHash = (($patches | ForEach-Object { Get-Sha256 $_.FullName }) -join ',')
# What the tools folder and the game are made from: when this is unchanged, steps 1 to 3 are done.
$stamp = "release=$($toolsPin.release)`ncommit=$($pin.commit)`npatches=$patchHash"

$sharedWork = [bool]$Work
$tools = if ($Tools) { [System.IO.Path]::GetFullPath($Tools) } else { Join-Path $hs 'tools' }
$work = if ($Work) { [System.IO.Path]::GetFullPath($Work) } else { Join-Path $hs 'work' }
# (beside a shared tools folder, so its 400 MB of parts are fetched once for every kit)
$downloads = if ($Tools) { Join-Path (Split-Path -Parent $tools) 'downloads' } else { Join-Path $hs 'downloads' }
if (-not $Out) {
    # The game this kit built last (game-folder.txt, written below; a build with -Out puts it elsewhere): an update
    # puts the new co-op into THAT game. Only when that folder is gone does the default folder get a new build.
    # (Get-KitHookshotGame: a relative name is this kit's; another kit's hookshot\game is never used: kit-copy)
    $Out = Join-Path $hs 'game'
    $last = Get-KitHookshotGame $kit
    if ($last -and (Test-Path -LiteralPath $last -PathType Container)) { $Out = $last }
}
$Out = [System.IO.Path]::GetFullPath($Out)
$python = Join-Path $tools 'python\python.exe'

# --- A Longshot of the player's own (kit-friction) -----------------------------------------------
# Never played or written to: co-op is a separate build (the release in hookshot\PIN with co-op's patches in its source).
# Asked once, before the first build (hookshot\longshot-folder.txt keeps the answer; 'none' is a no).
# The puppet pack, from the same game files, where the co-op hook looks for it: its load folder
# (<exe dir>\mods\contents on Hookshot)\0400486024DEC000\coop-puppet, the emulator's layout, which Hookshot's
# host/mods.c also loads as a mod. A pack an earlier version of this script put in mods\coop-puppet goes.
# The pack step is a function: the end of every build and update runs it, and so does -PackOnly (make-puppet-pack.cmd,
# pack-retry). $true when the pack was made.
function Invoke-PuppetPackStep([string]$exeDir) {
    $code = 1
    $made = $false
    $packTool = Join-Path $kit 'tools\puppet_pack\build.py'
    $mod = Join-Path $exeDir 'mods\contents\0400486024DEC000\coop-puppet'
    $oldMod = Join-Path $exeDir 'mods\coop-puppet'
    if (Test-Path -LiteralPath (Join-Path $oldMod 'coop_puppet.json')) { Remove-Item -LiteralPath $oldMod -Recurse -Force }
    $packFrom = $Game
    if (-not $packFrom) {
        $last = Join-Path $hs 'game-files.txt'
        if (Test-Path -LiteralPath $last) { $packFrom = "$(Get-Content -LiteralPath $last -TotalCount 1)".Trim() }
    }
    if ($Game) { [System.IO.File]::WriteAllText((Join-Path $hs 'game-files.txt'), "$Game`n") }
    # The game file gone (moved, renamed, a drive not plugged in): said plainly, and in a window someone sits at, its new
    # place asked for 2 minutes (nothing typed: the game starts without the pack, and the next start asks again).
    if ((-not $packFrom -or -not (Test-Path -LiteralPath $packFrom)) -and (Test-Path -LiteralPath $packTool)) {
        # First the usual places (pack-retry: the .nup moved to Downloads or the Desktop, a kit unzipped beside it).
        $dumpCheck = Join-Path $kit 'tools\puppet_pack\dumpcheck.py'
        $isGame = {
            param($p)
            $ErrorActionPreference = 'Continue'
            & $python -I -B $dumpCheck --user-dir (Join-Path $kit 'emulator\user') --romfs $p *> $null
            return $LASTEXITCODE -eq 0
        }
        $found = if ((Test-Path -LiteralPath $dumpCheck) -and (Test-Path -LiteralPath $python)) { Find-KitGameNup $packFrom $kit $isGame } else { '' }
        if ($found) {
            Write-Host "  Found your game file: $found (saved in hookshot\game-files.txt)"
            $packFrom = $found
            [System.IO.File]::WriteAllText((Join-Path $hs 'game-files.txt'), "$packFrom`n")
        }
    }
    if (-not $packFrom -or -not (Test-Path -LiteralPath $packFrom)) {
        Write-Host ''
        foreach ($l in (Get-KitPackSourceText $packFrom)) { Write-Host $l -ForegroundColor Yellow }
        $canAsk = $true
        try { $canAsk = -not [Console]::IsInputRedirected } catch { $canAsk = $false }
        # Asked once, not on every start: hookshot\pack-asked.txt keeps what was asked about (the game file named and
        # the pack tool's hash), and a new game file or tool asks again; make-puppet-pack.cmd (-PackOnly) always asks.
        $askNote = Join-Path $hs 'pack-asked.txt'
        $askKey = Get-KitPackAskKey $packFrom (Join-Path $kit 'tools\puppet_pack')
        $askedBefore = -not $PackOnly -and (Test-KitPackAsked $askNote $askKey)
        if ($askedBefore) {
            Write-Host '  (Not asked again at every start. make-puppet-pack.cmd asks for your game file and makes the pack.)' -ForegroundColor Yellow
        } elseif ($canAsk -and -not $env:CI -and (Test-Path -LiteralPath $packTool)) {
            Write-Host '  Your game''s .nup file: paste its path with Ctrl+V or right-click, or drag the file here, then press Enter'
            Write-Host '  (Enter alone: start without the pack):'
            $given = Read-KitPath 120 { param($p) $p -like '*.nup' }
            if ($given -and (Test-Path -LiteralPath $given)) {
                $packFrom = (Resolve-Path -LiteralPath $given).Path
                [System.IO.File]::WriteAllText((Join-Path $hs 'game-files.txt'), "$packFrom`n")
                Remove-Item -LiteralPath $askNote -Force -ErrorAction SilentlyContinue
            } else {
                if ($given) { Write-Host "  Not found: $given" -ForegroundColor Yellow }
                try { [System.IO.File]::WriteAllText($askNote, "$askKey`n") } catch { }
            }
        }
    }
    if ($packFrom -and (Test-Path -LiteralPath $packFrom) -and (Test-Path -LiteralPath $packTool)) {
        Write-Host '  Making the puppet pack (how you see the other players; about a minute) ...'
        # Custom character models (coop-models beside the game's mods folder, never inside it): one --skin each. A model
        # the pack tool cannot build is left out (Invoke-KitPackBuild), so one bad import never stops the game.
        $models = Get-KitModelsDir $exeDir
        $found = Get-KitModelSkins $models
        foreach ($n in $found.Skipped) {
            Write-Host "  custom model folder ""$n"" left out: a model's folder name is 1 to 20 letters or digits ($models)" -ForegroundColor Yellow
        }
        if ($found.Skins) { Write-Host "  Custom models: $(@($found.Skins | ForEach-Object { $_.Id }) -join ', ')" }
        $modelsHash = Get-KitModelsHash $models
        Remove-Item -LiteralPath (Join-Path $mod 'coop-models.txt') -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = 'Continue'
        # (no --title-rows: the title stays the game's own; co-op is the pause menu's Multiplayer tab)
        $run = {
            param([string[]]$Extra)
            $lines = @(& $python -I -B $packTool --romfs $packFrom --mod-dir $mod @Extra 2>&1 | ForEach-Object { $l = "$_"; Write-Host "    $l"; $l })
            return @{ Code = $LASTEXITCODE; Lines = $lines }
        }
        $built = Invoke-KitPackBuild $run @($found.Skins)
        $code = $built.Code
        $made = $true
        $ErrorActionPreference = 'Stop'
        if ($code -eq 0) {
            # (every model folder there, also one left out: the pack is made again only when the models change)
            Save-KitModelsStamp $mod $modelsHash
            if ($built.Built) { Write-Host "  Custom models in the puppet pack: $($built.Built -join ', ')" }
        }
        if ($code -eq 0) { Remove-Item -LiteralPath (Join-Path $hs 'pack-asked.txt') -Force -ErrorAction SilentlyContinue }
        if ($code -ne 0) { Write-Host '  The puppet pack could not be made (the lines above say why): the game starts, and the other players show as names only until it is made. Every start tries again.' -ForegroundColor Yellow }
    } else {
        Write-Host '  No puppet pack this time: the other players show as names only.' -ForegroundColor Yellow
    }
    return ($code -eq 0 -and $made)
}

# -PackOnly (make-puppet-pack.cmd on a Longshot kit; boredhermit: "it can't build the puppet independently anymore"):
# only the puppet pack, made again in the game this kit built. Nothing is downloaded or built.
if ($PackOnly) {
    $exe = Get-KitHookshotExe $Out
    if (-not $exe) { Fail 'The co-op game is not built yet. Start "Start Squadala.bat": it builds the game and makes the puppet pack.' }
    if (-not (Test-Path -LiteralPath $python)) { Fail "The pack tool's Python is not in $tools. Start ""Start Squadala.bat"" once (it gets it), then this again." }
    $exeDir = Split-Path -Parent $exe
    if (Get-Process longshot, hookshot -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($exeDir, [StringComparison]::OrdinalIgnoreCase) }) {
        Fail 'The co-op game is running: close it first (it reads the pack when it starts).'
    }
    Step 'The puppet pack'
    $ok = Invoke-PuppetPackStep $exeDir
    foreach ($l in @(Update-KitRandoSeeds $exeDir)) { Write-Host "  $l" }
    if ($ok) { Write-Host ''; Write-Host 'Done: the puppet pack is made. Start "Start Squadala.bat" to play.' -ForegroundColor Green; exit 0 }
    exit 1
}

$lsNote = Join-Path $hs 'longshot-folder.txt'
$lsFresh = -not $CheckOnly -and -not $sharedWork -and -not (Test-Path -LiteralPath (Join-Path $Out 'coop-built-from.txt'))
if (-not $Longshot -and $lsFresh -and -not $env:OOT_COOP_NO_LONGSHOT_ASK) {
    if (Test-Path -LiteralPath $lsNote) { $Longshot = "$(Get-Content -LiteralPath $lsNote -TotalCount 1)".Trim() }
    else {
        Write-Host ''
        Write-Host 'Built Longshot yourself? The co-op game is a separate build (co-op is built into its source), but your own'
        Write-Host 'Longshot can lend it your saves and its downloads. Your Longshot game folder (the one with longshot.exe): paste'
        Write-Host 'its path with Ctrl+V or right-click, or drag the folder here, then press Enter; just Enter (or 60 s) for no.'
        Write-Host '(Asked once: hookshot\longshot-folder.txt keeps the answer; delete that file to be asked again before a build.)'
        $Longshot = Read-KitPath 60 { param($p) Test-Path -LiteralPath (Join-Path $p 'longshot.exe') }
        try { [System.IO.File]::WriteAllText($lsNote, "$(if ($Longshot) { $Longshot } else { 'none' })`n") } catch { }
    }
}
$lsImage = ''
$lsHomes = @()
$lsSameRelease = $false
if ($Longshot -and $Longshot -ne 'none' -and $lsFresh) {
    $lsImage = Get-KitLongshotImageDir $Longshot
    if (-not $lsImage) {
        Write-Host "  $Longshot is no Longshot game folder (no image.bin in it or in its bin\): nothing taken from it." -ForegroundColor Yellow
    } else {
        $lsInfo = Get-KitLongshotGameInfo $Longshot
        $lsVer = if ($lsInfo -and $lsInfo.version) { $lsInfo.version } else { 'of an unknown version' }
        $lsHomes = @(Get-KitLongshotHomes $(if ($lsInfo) { $lsInfo.home } else { '' }))
        $ourTag = if ($pin.tag) { $pin.tag } else { $toolsPin.release }
        # (the compiled objects only from the same release: another's compiler and headers make other objects anyway,
        # and a nightly is not a release co-op was tested on)
        $lsSameRelease = $lsInfo -and $lsInfo.version -eq $ourTag
        Write-Host "Found Longshot $lsVer at $Longshot."
        if ($lsSameRelease) {
            Write-Host "  The same release co-op is built on ($ourTag): its downloads and compiled files are copied (never changed) to save time;"
            Write-Host '  the game is still translated again with co-op in it. Your saves are copied in after the build.'
        } else {
            Write-Host "  Co-op is built on $ourTag, so it is built fresh; only downloaded tools that are the very same files are reused."
            Write-Host '  Your saves are copied in after the build (they are the game''s own files).'
        }
    }
}
# (no folder given: Longshot Builder's own home on this PC still lends its downloads, the same files by SHA-256)
if (-not $lsHomes -and $lsFresh -and -not $env:OOT_COOP_NO_LONGSHOT_ASK) {
    $lsHomes = @(Get-KitLongshotHomes)
    foreach ($h in $lsHomes) { Write-Host "Found Longshot Builder $(if ($h.version) { $h.version } else { '' }) at $($h.path): its downloads that are the same files are reused." }
}

# --- 1 and 2: the tools and the patched source ---------------------------------------------
$toolsStamp = Join-Path $tools 'coop-tools.txt'
$toolsReady = (Test-Path -LiteralPath $toolsStamp) -and ([System.IO.File]::ReadAllText($toolsStamp) -eq $stamp) -and (Test-Path -LiteralPath $python)
# The same release and pin with other patches: the source is refreshed in place (only what the patches touch).
$baseStamp = "release=$($toolsPin.release)`ncommit=$($pin.commit)`n"
$keep = Join-Path $tools '.coop-orig'
$samePin = -not $toolsReady -and (Test-Path -LiteralPath $toolsStamp) -and (Test-Path -LiteralPath $python) -and
    (Test-Path -LiteralPath (Join-Path $keep 'manifest.txt')) -and
    ([System.IO.File]::ReadAllText($toolsStamp).StartsWith($baseStamp))
if ($samePin) {
    Step "Longshot's source: the co-op patches changed ($($patches.Count) patch(es); the tools and pin stay)"
    & $python -I -B (Join-Path $PSScriptRoot 'apply_patch.py') --refresh $keep $tools @($patches | ForEach-Object FullName)
    if ($LASTEXITCODE -eq 0) {
        [System.IO.File]::WriteAllText($toolsStamp, $stamp)
        $toolsReady = $true
    } else {
        # (a refresh stopped half way, or a source changed by hand: the whole source again, once)
        Write-Host '  The source could not be refreshed in place: unpacking it again.' -ForegroundColor Yellow
        Remove-Item -LiteralPath $toolsStamp -Force -ErrorAction SilentlyContinue
    }
}
if ($toolsReady) {
    Step "Longshot's tools: ready ($($toolsPin.release) tools, Longshot $($pin.commit.Substring(0, 12)) with $($patches.Count) co-op patch(es))"
} else {
    Step "Longshot's build tools ($($toolsPin.release)) and source ($($pin.commit.Substring(0, 12)))"
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $lock = Join-Path $downloads "tools-$($toolsPin.release).lock"
    Get-Download "$repoUrl/releases/download/$($toolsPin.release)/tools.lock" $lock $toolsPin.lock_sha256 'tools.lock'
    # tools.lock: "tool <name> <version> <system> <sha256> <size> <dest> <prefix> <url> [<url> ...]"; the URLs are
    # tried in order (Longshot's Cloudflare copy, git.magicbean.dev, then upstream). Of the windows-x64 tools, emsdk
    # is not fetched (llvm-mingw builds the game; the builder sets EMSDK only when its folder is there).
    $wanted = @('llvm-mingw', 'python', 'cpm', 'third-party')
    $parts = @()
    foreach ($line in Get-Content -LiteralPath $lock) {
        $f = $line.Trim() -split '\s+'
        if ($f[0] -ne 'tool' -or $f.Count -lt 9 -or $f[3] -ne 'windows-x64' -or $wanted -notcontains $f[1]) { continue }
        if ($f[6] -notmatch '^LongshotBuilder/tools/([A-Za-z0-9_.-]+)$') { Fail "tools.lock puts $($f[1]) outside LongshotBuilder/tools: $($f[6])" }
        $folder = $Matches[1]
        $urls = @($f[8..($f.Count - 1)] | Where-Object { $_ -match '^https://' })
        if (-not $urls) { Fail "tools.lock has no https download for $($f[1])." }
        $parts += [pscustomobject]@{ Name = $f[1]; Sha = $f[4].ToLowerInvariant(); Folder = $folder; Prefix = $f[7]; Urls = $urls
                                      File = (Join-Path $downloads "$($f[1])-$($f[4].Substring(0, 12)).zip") }
    }
    if ($parts.Count -ne $wanted.Count) { Fail "tools.lock of $($toolsPin.release) does not list the $($wanted.Count) windows-x64 tools this script needs (found $($parts.Count))." }
    foreach ($p in $parts) {
        # (a tool zip your own Longshot's setup downloaded already: the same SHA-256, so the same file)
        $lent = if ($lsHomes) { Copy-KitLongshotDownload $lsHomes $p.Sha $p.File } else { '' }
        if ($lent) { Write-Host "  $($p.Name): copied from your Longshot's downloads ($lent)" }
        Get-Download $p.Urls $p.File $p.Sha "$($p.Sha)-$($p.Name).zip"
    }
    # Forgejo's source archive at PIN's commit, checked against TOOLS.txt's source_sha256 (a copy
    # already here is checked too, and fetched again when it differs).
    $sourceZip = Join-Path $downloads "longshot-$($pin.commit).zip"
    Get-Download @("$apiUrl/archive/$($pin.commit).zip", "$repoUrl/archive/$($pin.commit).zip") $sourceZip $toolsPin.source_sha256 "longshot-$($pin.commit).zip"

    Write-Host '  unpacking ...'
    $staging = "$tools.new"
    $why = Remove-KitFolderRetry $staging
    if ($why) { Fail (Get-KitHeldFolderText $staging $why) }
    # The source: the archive's one top folder (longshot/) left out.
    Expand-Zip $sourceZip $staging 1
    if (-not (Test-Path -LiteralPath (Join-Path $staging 'nx2\make_game.py'))) { Fail "Longshot's source archive has no nx2\make_game.py." }
    # Each tool as the builder's setup lays it out: <prefix> in the zip (or the whole zip) becomes tools\<folder>,
    # unpacked straight there (no copy of the deep HookshotBuilder\tools\... paths, which pass 260 characters).
    # Of third_party only the files the source lacks (the prebuilt .dll/.exe/.lib/.sha1), as Longshot's readme
    # says: tar -k keeps the source's own. (No play profile: it is optional.)
    foreach ($p in $parts) {
        $member = if ($p.Prefix -eq '-') { '' } else { $p.Prefix.TrimEnd('/') }
        Expand-Zip $p.File (Join-Path $staging $p.Folder) -Member $member -Keep:($p.Folder -eq 'third_party')
        if (-not (Get-ChildItem -LiteralPath (Join-Path $staging $p.Folder) -Force | Select-Object -First 1)) {
            Fail "The $($p.Name) archive of $($toolsPin.release) has no $($p.Prefix) folder."
        }
    }

    Write-Host "  applying $($patches.Count) co-op patch(es) ..."
    # (--refresh keeps the originals of what the patches change: a later patch change refreshes only those)
    & (Join-Path $staging 'python\python.exe') -I -B (Join-Path $PSScriptRoot 'apply_patch.py') --refresh (Join-Path $staging '.coop-orig') $staging @($patches | ForEach-Object FullName)
    if ($LASTEXITCODE -ne 0) { Fail "The co-op patches do not apply to Longshot $($pin.commit). This kit is broken: tell the co-op testers." }
    # (antivirus, Explorer or the indexer may hold a file of the fresh unzip for a moment: tried again, then robocopy)
    $held = $tools
    $why = Remove-KitFolderRetry $tools
    if (-not $why) { $held = $staging; $why = Move-KitFolderRetry $staging $tools }
    if ($why) { Fail (Get-KitHeldFolderText $held $why) }
    # (the stamp last: a move that stopped half way, a long path or a full disk, leaves no folder that looks ready)
    [System.IO.File]::WriteAllText($toolsStamp, $stamp)
    Write-Host '  ready.'
}

# --- 3: the game ---------------------------------------------------------------------------
function Find-HookshotExe([string]$Folder) {
    foreach ($p in (Join-Path $Folder 'bin\longshot.exe'), (Join-Path $Folder 'longshot.exe')) {
        if (Test-Path -LiteralPath $p) {
            # A builder's game folder has its launcher as longshot.exe and the game in bin\.
            return $p
        }
    }
    return $null
}
# A second kit on this PC (unzipped twice, or a Windows copy of a kit): another kit's game made from the same
# release, pin and patches is copied into this kit's own hookshot\game (a minute or two) instead of built again
# (10 to 45 minutes). A copy, never the other kit's folder itself: two kits never start one game. Its coop.ini,
# coop-options.ini and logs stay behind, so this kit gets its own name, server and controller below.
$defaultOut = [System.IO.Path]::GetFullPath((Join-Path $hs 'game'))
if (-not $Rebuild -and -not $CheckOnly -and $Out -ieq $defaultOut -and -not (Find-HookshotExe $Out)) {
    $others = @()
    $named = Join-Path $hs 'game-folder.txt'
    if (Test-Path -LiteralPath $named) {
        $n = "$(Get-Content -LiteralPath $named -TotalCount 1)".Trim()
        if ($n -and [System.IO.Path]::IsPathRooted($n) -and (Test-KitOtherKitGame $kit $n)) { $others += Split-Path -Parent (Split-Path -Parent $n) }
    }
    $list = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'OoT-Coop\kits.txt' } else { '' }
    if ($list -and (Test-Path -LiteralPath $list)) { $others += @(Get-Content -LiteralPath $list | Where-Object { $_ }) }
    $from = Find-KitHookshotGameToCopy $kit $stamp $others
    if ($from) {
        Step "The game: copying the one another kit on this PC built ($from), instead of building it again"
        Write-Host '  The copy starts with that kit''s saves (as they are now); from then on each kit has its own.'
        $outWas = Test-Path -LiteralPath $Out
        New-Item -ItemType Directory -Force -Path $Out | Out-Null
        & robocopy $from $Out /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XF coop.ini coop-options.ini *.log *_log.txt | Out-Null
        if ($LASTEXITCODE -ge 8 -or -not (Find-HookshotExe $Out)) {
            Write-Host "  Copying failed (robocopy $LASTEXITCODE): the game is built here instead." -ForegroundColor Yellow
            # (only a folder this copy made: one that was there before may hold the player's own files)
            if (-not $outWas) { Remove-Item -LiteralPath $Out -Recurse -Force -ErrorAction SilentlyContinue }
        } else {
            Write-Host "  Copied to $Out (this kit's own game from now on)."
        }
        $global:LASTEXITCODE = 0
    }
}
# The game built for another Longshot release or commit (a kit gone back to an older version, Revert.bat): when this
# PC's game cache (Find-KitHookshotCachedGame) holds a build made from exactly this kit's release, pin and patches,
# it is copied over the game instead of building it again (15 to 45 minutes). Never copied: the player's files
# (saves, user\, mods\ with the puppet pack, coop-models\, coop.ini, coop-options.ini, longshot_options.ini, logs) and the romfs link.
$oldStamp = Join-Path $Out 'coop-built-from.txt'
if (-not $Rebuild -and -not $CheckOnly -and (Find-HookshotExe $Out) -and (Test-Path -LiteralPath $oldStamp)) {
    $base = { param($s) (@("$s" -replace "`r", '' -split "`n") | Where-Object { $_ -match '^(release|commit)=' }) -join "`n" }
    if ((& $base ([System.IO.File]::ReadAllText($oldStamp))) -ne (& $base $stamp)) {
        $from = Find-KitHookshotCachedGame $stamp
        # (the same layout only: longshot.exe at the top, or in bin\ in both)
        $flat = { param($g) (Split-Path -Parent (Find-HookshotExe $g)).TrimEnd('\') -ieq ([System.IO.Path]::GetFullPath($g)).TrimEnd('\') }
        if ($from -and (& $flat $from) -ne (& $flat $Out)) { $from = '' }
        if ($from) {
            Step "The game: copying the build of this version from the game cache on this PC ($from), instead of building it again"
            # (and the player's custom character models, coop-models beside mods: never another game's)
            $xd = @('user', 'save', 'autotest-save', 'mods', 'coop-models', 'bin\coop-models') | ForEach-Object { Join-Path $from $_ }
            # (its build stamp last: a copy that stops half way leaves the old stamp, and the game is built again)
            $xf = @('hookshot_coop.dll', 'coop.ini', 'coop-options.ini', 'longshot_log.txt', 'longshot_log.old.txt', 'control.json', 'longshot_options.ini', 'language.txt',
                'coop-built-from.txt') | ForEach-Object { Join-Path $from $_ }
            & robocopy $from $Out /E /XJD /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD @xd /XF @xf | Out-Null
            if ($LASTEXITCODE -ge 8 -or -not (Find-HookshotExe $Out)) {
                Write-Host "  Copying failed (robocopy $LASTEXITCODE): the game is built again instead." -ForegroundColor Yellow
            } else {
                Copy-Item -LiteralPath (Join-Path $from 'coop-built-from.txt') -Destination $oldStamp -Force
                Write-Host "  Copied into $Out; your saves and settings there are as they were."
            }
            $global:LASTEXITCODE = 0
        }
    }
}
$gameStamp = Join-Path $Out 'coop-built-from.txt'
$exe = Find-HookshotExe $Out
$gameReady = $exe -and (Test-Path -LiteralPath $gameStamp) -and ([System.IO.File]::ReadAllText($gameStamp) -eq $stamp)

# Game files that could not be taken, with why: said at the next game question (hookshot\game-rejected.txt).
$gameRejected = Join-Path $hs 'game-rejected.txt'
function Save-KitGameRejected([string]$What, [string]$Why) {
    try { [System.IO.File]::WriteAllText($gameRejected, "$What`r`nWhy: $Why`r`n") } catch { }
}
if (-not $Game -and (-not $gameReady -or $Rebuild -or $CheckOnly)) {
    # As make-puppet-pack.cmd: the .nup in a folder of the emulator's game list.
    $check = Join-Path $kit 'tools\puppet_pack\dumpcheck.py'
    if (Test-Path -LiteralPath $check) {
        $ErrorActionPreference = 'Continue'
        $found = & $python -I -B $check --user-dir (Join-Path $kit 'emulator\user') 2>$null | Where-Object { $_ -like 'romfs=*.nup' } | Select-Object -First 1
        $ErrorActionPreference = 'Stop'
        if ($found) { $Game = $found.Substring(6); Write-Host "Found your game: $Game" }
    }
    # The game files given the last time (hookshot\game-files.txt, written once Longshot's check took them): asked only once.
    # Remembered files that cannot be taken any more are not used (the question comes, with the reason).
    $last = Join-Path $hs 'game-files.txt'
    if (-not $Game -and (Test-Path -LiteralPath $last)) {
        $remembered = "$(Get-Content -LiteralPath $last -TotalCount 1)".Trim()
        if ($remembered -and (Test-Path -LiteralPath $remembered)) {
            $a = Resolve-KitGameAnswer $remembered
            # (refused by Longshot's check before: asked again, with that reason)
            $refused = if (Test-Path -LiteralPath $gameRejected) { "$(Get-Content -LiteralPath $gameRejected -TotalCount 1)".Trim() } else { '' }
            if ($refused -and $refused -ieq $remembered) { $a = @{ Why = 'Longshot''s check refused it the last time.' } }
            if ($a.Why) { Write-Host "The game files from the last time cannot be taken: $($a.Why)" -ForegroundColor Yellow }
            else { $Game = $remembered; Write-Host "Your game (from the last time): $Game" }
        }
    }
    if (-not $Game) {
        # (the usual places first, as the puppet pack does: beside the kit, Downloads, the Desktop; the right game only)
        $dumpCheck = Join-Path $kit 'tools\puppet_pack\dumpcheck.py'
        if ((Test-Path -LiteralPath $dumpCheck) -and (Test-Path -LiteralPath $python)) {
            $isGame = {
                param($p)
                $ErrorActionPreference = 'Continue'
                & $python -I -B $dumpCheck --user-dir (Join-Path $kit 'emulator\user') --romfs $p *> $null
                return $LASTEXITCODE -eq 0
            }
            $found = Find-KitGameNup '' $kit $isGame
            if ($found -and -not (Resolve-KitGameAnswer $found).Why) { $Game = $found; Write-Host "Found your game: $Game" }
        }
    }
    if (-not $Game) {
        # Asked until the files can be taken, each refusal with its reason. What the last start refused
        # (hookshot\game-rejected.txt: a check that failed) is said first.
        Write-Host ''
        if (Test-Path -LiteralPath $gameRejected) {
            Write-Host 'Last time your game files were not taken:' -ForegroundColor Yellow
            Get-Content -LiteralPath $gameRejected | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        }
        $why = ''
        # In a window someone sits at: asked until given (an empty answer asks again). Input from a file: 3 tries.
        $redirected = $true
        try { $redirected = [Console]::IsInputRedirected } catch { }
        $tries = if ($redirected) { 3 } else { [int]::MaxValue }
        for ($try = 1; $try -le $tries -and -not $Game; $try++) {
            Write-Host 'Your game''s .nup file (or its romfs folder): paste its path with Ctrl+V or right-click, or drag it here, then press Enter:'
            $a = Resolve-KitGameAnswer (Read-KitPath 0 { param($p) $p -like '*.nup' -or (Test-Path -LiteralPath $p -PathType Container) })
            if ($a.Why) { $why = $a.Why; Write-Host "  Not taken: $why" -ForegroundColor Yellow; Write-Host '  (Asked again; close this window to stop.)'; Write-Host '' }
            else { $Game = $a.Path; if ($a.Note) { Write-Host "  $($a.Note)" } }
        }
        if (-not $Game) {
            Save-KitGameRejected '(what was given at the question)' $why
            Fail "No game files taken: $why Start again to give them (or run Build-Hookshot-Coop.bat -Game <your .nup>)."
        }
    }
}
if ($Game) {
    $a = Resolve-KitGameAnswer $Game
    if ($a.Why) { Save-KitGameRejected $Game $a.Why; Fail "Your game files cannot be taken: $($a.Why)" }
    if ($a.Note) { Write-Host $a.Note }
    $Game = $a.Path
    if ((Get-Item -LiteralPath $Game).PSIsContainer) {
        if (-not $Exefs) {
            $guess = Join-Path (Split-Path -Parent $Game) 'exefs'
            if (Test-Path -LiteralPath (Join-Path $guess 'main')) { $Exefs = $guess }
            else {
                Write-Host 'A romfs folder needs its exefs folder too. Paste its path with Ctrl+V or right-click, or drag it here, then press Enter:'
                $Exefs = Read-KitPath 0 { param($p) Test-Path -LiteralPath (Join-Path $p 'main') }
                if (-not $Exefs) { Fail 'No exefs folder given (nothing arrived: paste its path with Ctrl+V or right-click, or drag the folder in). A romfs folder is built with its exefs folder; or give the .nup file instead.' }
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Exefs 'main'))) {
            Save-KitGameRejected $Exefs 'it is not an exefs folder (no file named main in it).'
            Fail "$Exefs is not an exefs folder (no file named main in it). Give the exefs folder beside your romfs folder, or the game's .nup file instead."
        }
        $Exefs = (Resolve-Path -LiteralPath $Exefs).Path
        $gameArgs = @('--romfs', $Game, '--exefs', $Exefs)
    } else {
        $gameArgs = @('--nup', $Game)
    }
}

# make_game.py runs in Longshot's tools folder with the builder's own compiler, headers and
# libraries, as Longshot Builder runs it (builder/LongshotBuilder/Runner.cs).
function Invoke-MakeGame([string[]]$MoreArgs, [string]$Log = '') {
    $script:MakeGameErrors = @()
    $env:PYTHONIOENCODING = 'utf-8'
    $env:RX_CPM = Join-Path $tools 'cpm'
    $env:LONGSHOT_MINGW = Join-Path $tools 'llvm-mingw'
    foreach ($v in 'LONGSHOT_NGX_SDK', 'LONGSHOT_FFX_SDK', 'LONGSHOT_MSVC', 'EMSDK', 'LONGSHOT_BUILDER_EXE', 'LONGSHOT_TOOLS',
             'LONGSHOT_ROMFS_FROM') {   # (a launcher's: game files hard-linked from another folder, Longshot rc.6 #360)
        Remove-Item "Env:\$v" -ErrorAction SilentlyContinue
    }
    # (a shared work folder keeps all its build files, the translated C too: the next build of this pin
    # skips the translation unless a lift file changed. A kit's own folder keeps Longshot's default.)
    if ($sharedWork) { $env:LONGSHOT_KEEP_BUILD_FILES = '1' }
    # (the release the menu names, top left: the source archive has no git history and no VERSION file, so
    # without this the builder's nx2\version.py says "unknown")
    if ($pin.tag) { $env:LONGSHOT_VERSION = $pin.tag }
    # (co-op's own OOT_COOP_* ones (the test cache, the test password) are no business of the build's: before rc.6
    # Longshot's lift key hashed every A64_/OOT_/RX_ variable, a whole new translation for nothing; rc.6's (#22) keys
    # only the A64_*, SUYU_RECOMP_* and RX_TARGET ones)
    Get-ChildItem Env: | Where-Object { $_.Name -like 'OOT_COOP_*' } | ForEach-Object { Remove-Item "Env:\$($_.Name)" }
    $logArgs = if ($Log) { @('--log', $Log) } else { @() }
    Push-Location $tools
    try {
        $ErrorActionPreference = 'Continue'
        # (its "@@<word> ..." lines are for the builder window: the stage names and errors are shown, the rest left out)
        & $python -I (Join-Path $tools 'nx2\make_game.py') @MoreArgs @logArgs 2>&1 | ForEach-Object {
            $line = "$_"
            if ($line -match '^@@stage \S+ (.*)$') { Write-Host "  -- $($Matches[1])" -ForegroundColor Cyan }
            elseif ($line -match '^@@error (.*)$') { Write-Host "  $($Matches[1])" -ForegroundColor Red; $script:MakeGameErrors += $Matches[1] }
            elseif ($line -notmatch '^@@') { Write-Host "  $line" }
        }
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
    } finally { Pop-Location }
    return $code
}

if ($gameReady -and -not $Rebuild -and -not $CheckOnly) {
    Step "The game: built already ($Out)"
} else {
    if (-not $gameArgs) { Fail 'No game files: none were found or remembered, and none could be asked for here. Start "Start Squadala.bat" again, or run Build-Hookshot-Coop.bat -Game <your .nup>.' }
    Step 'Checking your game files'
    $code = Invoke-MakeGame ($gameArgs + @('--check'))
    if ($code -ne 0) {
        # (remembered with its reason: the next start asks again and says why these were not taken)
        $said = @($script:MakeGameErrors | Select-Object -Last 2) -join ' '
        $why = "Longshot's check refused $Game$(if ($said) { ": $said" } else { ' (its lines above say why)' })."
        Save-KitGameRejected $Game $why
        # (and forgotten: a remembered file the check refuses would be taken again at every start, with no question.
        # The pack question and the pack step save game-files.txt unchecked.)
        $remembered = Join-Path $hs 'game-files.txt'
        if ((Test-Path -LiteralPath $remembered) -and "$(Get-Content -LiteralPath $remembered -TotalCount 1)".Trim() -ieq $Game) {
            Remove-Item -LiteralPath $remembered -Force -ErrorAction SilentlyContinue
        }
        Fail "$why Most often the file is another version of the game: co-op needs program 0400486024DEC000, update v131072, build e0f3ccfa (dump that version and give its .nup). Start again to give other files."
    }
    # Taken: remembered now, so a build that stops later does not ask again.
    if ($Game) { [System.IO.File]::WriteAllText((Join-Path $hs 'game-files.txt'), "$Game`n") }
    Remove-Item -LiteralPath $gameRejected -Force -ErrorAction SilentlyContinue
    if ($CheckOnly) { Write-Host ''; Write-Host 'Your game files are right for Longshot. Run this again without -CheckOnly to build.' -ForegroundColor Green; exit 0 }
    $drive = [System.IO.Path]::GetPathRoot($work)
    $free = (Get-PSDrive -Name $drive.Substring(0, 1) -ErrorAction SilentlyContinue).Free
    if ($free -and $free -lt 60GB -and -not (Test-Path -LiteralPath (Join-Path $work 'sa'))) {
        Write-Host ('Warning: {0:N0} GB free on {1}; the first build wants about 60 GB.' -f ($free / 1GB), $drive) -ForegroundColor Yellow
    }
    Step 'Building the game (10 to 45 minutes; the PC stays usable)'
    $buildLog = Join-Path $hs 'build.log'
    $buildArgs = $gameArgs + @('--out', $Out, '--work', $work, '--language', $Language)
    if ($Jobs) { $buildArgs += @('--jobs', "$Jobs") }
    # (-RomfsFrom: another game folder unpacked from the same .nup. Longshot's --romfs-from (since rc.6, #360) hard-links its
    # game files instead of writing the .nup's ~26 GB again; Longshot itself checks the folder's .nup stamp and the drive,
    # and reads the .nup when it can't. Only with a .nup, and only a Longshot that has the option)
    $makeGame = Join-Path $tools 'nx2\make_game.py'
    if ($RomfsFrom -and $gameArgs[0] -eq '--nup' -and (Test-Path -LiteralPath $RomfsFrom -PathType Container) -and
        (Test-Path -LiteralPath $makeGame) -and (Select-String -LiteralPath $makeGame -SimpleMatch '"--romfs-from"' -Quiet)) {
        $buildArgs += @('--romfs-from', $RomfsFrom)
        Write-Host "  the game files from $RomfsFrom (hard links where the drive allows)"
    }
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    # (your own Longshot of the same release: its compiled objects, keyed by source, flags and headers and never by folder,
    # so the files co-op does not change are not compiled again. Only into a work folder with none yet; copied, not moved)
    $ourTag = if ($pin.tag) { $pin.tag } else { $toolsPin.release }
    $objTo = Join-Path $work 'objcache'
    if ($lsFresh -and -not (Test-Path -LiteralPath $objTo)) {
        foreach ($h in $lsHomes) {
            $objFrom = Join-Path $h.path 'objcache'
            if (-not (Test-Path -LiteralPath $objFrom) -or -not ($lsSameRelease -or $h.version -eq $ourTag)) { continue }
            Write-Host "  copying the compiled files of your Longshot $ourTag ($objFrom) ..."
            & robocopy $objFrom $objTo /E /R:1 /W:1 /XC /XN /XO /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { Write-Host "  (not copied, robocopy $($LASTEXITCODE): all of it is compiled here)" }
            $global:LASTEXITCODE = 0
            break
        }
    }
    $code = Invoke-MakeGame $buildArgs $buildLog
    if ($code -ne 0) { Fail "The build stopped (exit $code). Its log: $buildLog" }
    $exe = Find-HookshotExe $Out
    if (-not $exe) { Fail "The build finished but there is no longshot.exe in $Out. Its log: $buildLog" }
    [System.IO.File]::WriteAllText($gameStamp, $stamp)
}
# Where the game is, for Host-Hookshot.bat and Join-Hookshot.bat (play.ps1 -Hookshot).
# (relative when it is inside the kit, so a copied or moved kit keeps its own game: kit-copy)
$kitFull = [System.IO.Path]::GetFullPath($kit).TrimEnd('\') + '\'
$outNote = if ($Out.StartsWith($kitFull, [StringComparison]::OrdinalIgnoreCase)) { $Out.Substring($kitFull.Length) } else { $Out }
[System.IO.File]::WriteAllText((Join-Path $hs 'game-folder.txt'), "$outNote`n")

# --- 4: co-op into the game ----------------------------------------------------------------
Step 'Co-op into the game'
$exeDir = Split-Path -Parent $exe
# The module and the Visual C++ runtime it needs (when the kit carries it), beside longshot.exe.
# (a kit always has it; a hand-made test folder may not yet: the game is built, and co-op is off until it is there)
$module = Join-Path $hs 'hookshot_coop.dll'
if (-not (Test-Path -LiteralPath $module)) {
    Write-Host "  No hookshot\hookshot_coop.dll in this kit: the game is built without co-op. Put the module there and run this again." -ForegroundColor Yellow
    exit 1
}
Copy-Item -LiteralPath $module -Destination $exeDir -Force
Get-ChildItem -LiteralPath $hs -Filter '*.dll' -File | Where-Object { $_.Name -ne 'hookshot_coop.dll' } |
    Where-Object { -not (Test-Path -LiteralPath (Join-Path $exeDir $_.Name)) } | Copy-Item -Destination $exeDir
Write-Host "  hookshot_coop.dll -> $exeDir"

# coop.ini beside longshot.exe (the module reads it there): the player's own server and name from
# this kit's emulator when the game has none yet.
$ini = Join-Path $exeDir 'coop.ini'
$kitIni = Join-Path $kit 'emulator\user\config\coop.ini'
$template = Join-Path $PSScriptRoot 'coop.ini.template'
if (-not (Test-Path -LiteralPath $ini)) {
    $have = if (Test-Path -LiteralPath $kitIni) { Read-CoopIni $kitIni } else { @{ server = ''; port = ''; name = ''; password = '' } }
    $port = if ($have.port) { $have.port } else { '27510' }
    Write-CoopIni $template $ini $have.server $port $have.name $have.password
}
$now = Read-CoopIni $ini
Write-Host "  coop.ini -> $ini (server: $(if ($now.server) { $now.server } else { 'not set' }), name: $(if ($now.name) { $now.name } else { 'not set' }))"
$options = Join-Path $exeDir 'coop-options.ini'
if (-not (Test-Path -LiteralPath $options)) {
    $kitOptions = Join-Path $kit 'coop-options.ini'
    if (-not (Test-Path -LiteralPath $kitOptions)) { $kitOptions = Join-Path $PSScriptRoot 'coop-options.default.ini' }
    if (Test-Path -LiteralPath $kitOptions) { Copy-Item -LiteralPath $kitOptions -Destination $options }
}

# The randomizer, OOTRR (hookshot\OOTRR.txt: its release and SHA-256), into <exe dir>\tools\ootrr where the co-op
# module finds it with no setting; it reads the game's own files beside it (<exe dir>\romfs) and never changes them.
# A failed download only warns: co-op plays without it, and the next run of this script tries again.
$ootrrPin = Join-Path $hs 'OOTRR.txt'
if (Test-Path -LiteralPath $ootrrPin) {
    $op = Read-KeyFile $ootrrPin
    $ootrrDir = Join-Path $exeDir 'tools\ootrr'
    $ootrrStamp = Join-Path $ootrrDir 'coop-ootrr.txt'
    $ootrrWant = "$($op.release) $($op.windows_sha256)"
    $ootrrHave = if (Test-Path -LiteralPath $ootrrStamp) { (Get-Content -LiteralPath $ootrrStamp -TotalCount 1).Trim() } else { '' }
    if ($ootrrHave -eq $ootrrWant -and (Test-Path -LiteralPath (Join-Path $ootrrDir 'ootrr.exe'))) {
        Write-Host "  randomizer: OOTRR $($op.release) -> $ootrrDir (there already)"
    } elseif (-not ($op.url -and $op.windows -match '^[A-Za-z0-9._-]+$' -and $op.windows_sha256 -match '^[0-9a-f]{64}$')) {
        Write-Host '  hookshot\OOTRR.txt is incomplete: the randomizer is left out.' -ForegroundColor Yellow
    } else {
        New-Item -ItemType Directory -Force -Path $downloads | Out-Null
        $ootrrZip = Join-Path $downloads $op.windows
        $why = ''
        if (-not ((Test-Path -LiteralPath $ootrrZip) -and (Get-Sha256 $ootrrZip) -eq $op.windows_sha256)) {
            if (($env:OOT_COOP_OFFLINE -eq '1' -or $op.url -match '^https?://') -and (Test-KitOffline)) {
                # (no internet: no download try, which would only wait for its timeout)
                $why = 'this PC has no internet now'
            } else {
                # (kit-mirror: retries and curl.exe too; optional, so two tries, not four)
                $why = Get-KitDownload @("$($op.url)/$($op.windows)") $ootrrZip $op.windows_sha256 @() 2
                if ($why) { $why = "the download failed ($why)" }
            }
        }
        if (-not $why) {
            if (Test-Path -LiteralPath $ootrrDir) { Remove-Item -LiteralPath $ootrrDir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $ootrrDir | Out-Null
            # (the zip holds one folder, OOTRR-<version>-windows-x64\: ootrr.exe, LICENSE, NOTICE, README.md)
            & "$env:SystemRoot\System32\tar.exe" -x -f $ootrrZip -C $ootrrDir --strip-components=1
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $ootrrDir 'ootrr.exe'))) { $why = "unpacking $($op.windows) failed" }
            else { [System.IO.File]::WriteAllText($ootrrStamp, "$ootrrWant`n") }
        }
        if ($why) { Write-Host "  The randomizer (OOTRR $($op.release)) was not set up: $why. Co-op works without it; run Build-Hookshot-Coop.bat again to retry." -ForegroundColor Yellow }
        else {
            Write-Host "  randomizer: OOTRR $($op.release) -> $ootrrDir"
            # (another release than the one before: its seeds are other worlds, Remove-KitRandoSeeds)
            if ($ootrrHave -and ($ootrrHave -split ' ')[0] -ne $op.release) {
                foreach ($l in @(Remove-KitRandoSeeds $exeDir $op.release)) { Write-Host "  $l" }
            }
        }
    }
}

# The puppet pack (Invoke-PuppetPackStep above), from the same game files.
[void](Invoke-PuppetPackStep $exeDir)
# Randomizer seeds built before this puppet pack: built again with its size table (else the game aborts while it loads).
foreach ($l in @(Update-KitRandoSeeds $exeDir)) { Write-Host "  $l" }

# Your own Longshot's saves into the co-op game (once, after its first build; a slot already there is never overwritten).
if ($lsImage) {
    $ourImage = Get-KitLongshotImageDir $Out
    if (-not $ourImage) { $ourImage = $exeDir }
    foreach ($l in (Copy-KitLongshotSaves $lsImage $ourImage)) { Write-Host "  $l" }
}

# A desktop shortcut to the kit's one start file, "Start Squadala.bat", once, for the kit's own game (not for a game
# hs.py builds elsewhere). "Play Squadala" (its name up to v0.11.2, "Play OoT Co-op", counts as there: start.ps1
# renames it; update.ps1 Update-KitStartLinks points every older shortcut at "Start Squadala.bat").
$launcher = Join-Path $kit 'Start Squadala.bat'
if (-not $PSBoundParameters.ContainsKey('Out') -and -not $Tools -and (Test-Path -LiteralPath $launcher) -and
    -not $env:OOT_COOP_NO_SHORTCUT) {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $link = Join-Path $desktop 'Play Squadala.lnk'
        if ($desktop -and -not (Test-Path -LiteralPath $link) -and -not (Test-Path -LiteralPath (Join-Path $desktop 'Play OoT Co-op.lnk'))) {
            $shell = New-Object -ComObject WScript.Shell
            $s = $shell.CreateShortcut($link)
            $s.TargetPath = $launcher
            $s.WorkingDirectory = $kit
            $s.IconLocation = "$exe,0"
            $s.Description = 'OoT co-op on Hookshot: host or join, updates itself'
            $s.Save()
            Write-Host "  A shortcut 'Play Squadala' is on your desktop."
        }
    } catch { Write-Host "  (no desktop shortcut: $($_.Exception.Message))" }
}

Write-Host ''
if (Test-Path -LiteralPath (Join-Path $kit 'Start Squadala.bat')) {
    Write-Host 'Done. The game is ready: "Start Squadala.bat" (or the desktop shortcut) starts it; Host and Join are in the game.' -ForegroundColor Green
    Write-Host "  The game: $exe. Its log (longshot_log.txt in the game's logs folder) says 'coop: module loaded'."
    exit 0
}
Write-Host 'Done. To play co-op on Hookshot: Play-OoT-Coop.bat (or the desktop shortcut) starts the game, Host and Join are on its title screen; Host-Hookshot.bat hosts, Join-Hookshot.bat joins (as Host.bat and' -ForegroundColor Green
Write-Host "  Join.bat, with the Hookshot game in place of the emulator). The game: $exe"
Write-Host "  Its log (longshot_log.txt in the game's logs folder) says 'coop: module loaded' and 'coop: connected'. HOS_COOP=0 starts it without co-op."
Write-Host '  Updates come by themselves: the launchers check for a new version and bring the game up to date.'
exit 0
