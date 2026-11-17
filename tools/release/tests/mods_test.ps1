# Tests for the kit's game-mod check (Get-KitMods in tools/release/kit/scripts/kit-paths.ps1,
# issue 136: co-op does not allow game mods), and the custom character models in coop-models (Get-KitModelSkins,
# Get-KitModelsHash, Test-KitModelsChanged and Invoke-KitPackBuild in the same file, with a stand-in pack tool).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release\tests\mods_test.ps1
# Exits 1 when a check fails.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'kit\scripts\kit-paths.ps1')

$failed = 0
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Host "ok   $What" } else { Write-Host "FAIL $What"; $script:failed++ }
}
function Write-File([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text)
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('oot-coop-mods-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $user = Join-Path $tmp 'emulator\user'
    $game = Join-Path $user 'load\0400486024DEC000'
    New-Item -ItemType Directory -Force -Path $user | Out-Null
    Check (@(Get-KitMods $user).Count -eq 0) 'no load folder: no mods'

    # Co-op's own puppet pack is no mod for this check.
    Write-File (Join-Path $game 'coop-puppet\romfs\Pack\Actor\CoopPuppet_Child.pack.zs') 'x'
    Check (@(Get-KitMods $user).Count -eq 0) 'the coop-puppet pack does not count'
    # An empty folder, or one with only empty parts, is no mod (as in the emulator's Add-Ons).
    New-Item -ItemType Directory -Force -Path (Join-Path $game 'Empty\exefs') | Out-Null
    Check (@(Get-KitMods $user).Count -eq 0) 'an empty mod folder does not count'

    # The Hyrule Cheat Menu's layout: an IPS and a subsdk in exefs.
    Write-File (Join-Path $game 'Hyrule-Cheat-Menu\exefs\E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348.ips') 'PATCH'
    Write-File (Join-Path $game 'Hyrule-Cheat-Menu\exefs\subsdk8') 'x'
    $mods = @(Get-KitMods $user)
    Check ($mods.Count -eq 1 -and $mods[0] -like '*Hyrule-Cheat-Menu') "an exefs mod is found: $($mods -join ', ')"
    # Texture and model mods (game files only, romfs) are allowed; cheats folders are not; a mod
    # with code (ExeFS, any case) and textures is a code mod.
    Write-File (Join-Path $game 'Textures\RomFS\a.bin') 'x'
    Write-File (Join-Path $game 'Water Temple fix\romfslite\b.bin') 'x'
    Check (@(Get-KitMods $user).Count -eq 1) 'romfs-only mods (texture and model fixes) are allowed'
    Write-File (Join-Path $game 'Cheats only\cheats\0123456789ABCDEF.txt') '[x]'
    Write-File (Join-Path $game 'Both\ExeFS\main.ips') 'PATCH'
    Write-File (Join-Path $game 'Both\romfs\c.bin') 'x'
    $mods = @(Get-KitMods $user | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object)
    Check (($mods -join ',') -eq 'Both,Cheats only,Hyrule-Cheat-Menu') "a cheats folder and a code+texture mod count [$($mods -join ',')]"
    Remove-Item -LiteralPath (Join-Path $game 'Both') -Recurse -Force

    # Turned off in the game's Add-Ons: not counted. Another game's list does not matter.
    $id = [Convert]::ToUInt64('0400486024DEC000', 16).ToString()
    $ini = "[UI]`r`nfoo=1`r`n[DisabledAddOns]`r`n1\disabled\1\d=Hyrule-Cheat-Menu`r`n1\disabled\1\d\default=false`r`n" +
           "1\disabled\2\d=Textures`r`n1\disabled\size=2`r`n1\title_id=$id`r`n1\title_id\default=false`r`n" +
           "2\disabled\1\d=Cheats only`r`n2\disabled\size=1`r`n2\title_id=12345`r`nsize=2`r`n[Other]`r`n3\disabled\1\d=Cheats only`r`n"
    Write-File (Join-Path $user 'config\qt-config.ini') $ini
    Check ((@(Get-KitDisabledAddons $user) -join ',') -eq 'Hyrule-Cheat-Menu,Textures') 'the Add-Ons list of this game is read'
    $mods = @(Get-KitMods $user)
    Check ($mods.Count -eq 1 -and $mods[0] -like '*Cheats only') "mods turned off in Add-Ons do not count: $($mods -join ', ')"

    # A load folder set elsewhere in qt-config.ini, and the SD card's atmosphere folder.
    $other = Join-Path $tmp 'elsewhere\load'
    Write-File (Join-Path $other '0400486024DEC000\Moved\exefs\main.ips') 'PATCH'
    $sd = Join-Path $tmp 'sd'
    Write-File (Join-Path $sd 'atmosphere\contents\0400486024DEC000\romfs\x.bin') 'x'
    $ini = "[Data%20Storage]`r`nsdmc_directory=$($sd.Replace('\', '/'))/`r`n"
    Write-File (Join-Path $user 'config\qt-config.ini') $ini
    Check (-not (@(Get-KitMods $user) | Where-Object { $_ -like '*atmosphere*' })) 'game files on the SD card (romfs) are allowed'
    Write-File (Join-Path $sd 'atmosphere\contents\0400486024DEC000\exefs\subsdk9') 'x'
    $ini = "[Data%20Storage]`r`nload_directory=$($other.Replace('\', '/'))/`r`nsdmc_directory=$($sd.Replace('\', '/'))/`r`n"
    Write-File (Join-Path $user 'config\qt-config.ini') $ini
    $mods = @(Get-KitMods $user)
    Check ($mods.Count -eq 2) "the load folder from qt-config.ini and the SD card's mod both count: $($mods -join ', ')"
    Check (@($mods | Where-Object { $_ -like '*Moved' }).Count -eq 1) 'the mod in the moved load folder'
    Check (@($mods | Where-Object { $_ -like '*atmosphere*0400486024DEC000' }).Count -eq 1) 'code on the SD card (SDMC exefs) counts'
    Write-File (Join-Path $user 'config\qt-config.ini') ($ini + "[DisabledAddOns]`r`n1\disabled\1\d=SDMC`r`n1\disabled\size=1`r`n1\title_id=$id`r`nsize=1`r`n")
    Check (@(Get-KitMods $user).Count -eq 1) 'the SD card mod turned off (SDMC) does not count'

    # Dark's Dynamic FPS mod (Fritchii v5.7 skips it for its built-in, and hides it in Add-Ons).
    Remove-Item -LiteralPath (Join-Path $user 'config\qt-config.ini') -Force
    $u2 = Join-Path $tmp 'dfps\emulator\user'
    $g2 = Join-Path $u2 'load\0400486024DEC000'
    New-Item -ItemType Directory -Force -Path $u2 | Out-Null
    function New-Ips([string]$Path, [int64[]]$Offsets, [int]$Size, [switch]$Ips32) {
        $bytes = New-Object System.Collections.Generic.List[byte]
        $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($(if ($Ips32) { 'IPS32' } else { 'PATCH' })))
        foreach ($o in $Offsets) {
            $w = if ($Ips32) { 4 } else { 3 }
            for ($k = $w - 1; $k -ge 0; $k--) { $bytes.Add([byte](($o -shr (8 * $k)) -band 0xff)) }
            $bytes.Add([byte]($Size -shr 8)); $bytes.Add([byte]($Size -band 0xff))
            for ($k = 0; $k -lt $Size; $k++) { $bytes.Add(0x1f) }
        }
        $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($(if ($Ips32) { 'EEOF' } else { 'EOF' })))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [System.IO.File]::WriteAllBytes($Path, $bytes.ToArray())
    }
    $build = 'E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348'
    New-Ips (Join-Path $g2 'DynamicFPS\exefs\E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348.ips') @(0x6e6dc4, 0x3c46300) 4 -Ips32
    Check (@(Get-KitMods $u2).Count -eq 0) 'Dark''s Dynamic FPS (IPS32 over its call and routine) is no mod: Fritchii uses its built-in'
    $ranges = (Get-KitIpsRanges (Join-Path $g2 'DynamicFPS\exefs\E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348.ips'))
    Check ($ranges.Count -eq 2 -and $ranges[0][0] -eq 0x6e6dc4 -and $ranges[1][1] -eq 0x3c46304) 'an IPS file''s write ranges are read'
    New-Ips (Join-Path $g2 'DynFPS3\exefs\E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348.ips') @(0x6e6dc4) 4
    Check (@(Get-KitMods $u2).Count -eq 0) 'a plain IPS over the call alone: no mod either'
    $pch = "@nsobid-$build`r`n@flag offset_shift 0x100`r`n@enabled`r`n// the call`r`n006E6CC4 4F80D594`r`n@stop`r`n"
    Write-File (Join-Path $g2 'DynFPStxt\exefs\dynamic.pchtxt') $pch
    Check (@(Get-KitMods $u2).Count -eq 0) 'an IPSwitch Dynamic FPS (offset_shift 0x100): no mod'
    Check (((Get-KitPchtxt (Join-Path $g2 'DynFPStxt\exefs\dynamic.pchtxt')).Ranges[0] -join ',') -eq "$(0x6e6dc4),$(0x6e6dc8)") 'an IPSwitch file''s write ranges are read'
    # Not Dynamic FPS: a patch elsewhere, a disabled IPSwitch patch, a name the emulator does not match.
    New-Ips (Join-Path $g2 'Other\exefs\E0F3CCFAF50065AE4EA01EB5AEB13B1A45DA3348.ips') @(0x10000) 4
    Write-File (Join-Path $g2 'OffTxt\exefs\x.pchtxt') ("@nsobid-$build`r`n@flag offset_shift 0x100`r`n@disabled`r`n006E6CC4 4F80D594`r`n")
    New-Ips (Join-Path $g2 'Lower\exefs\e0f3ccfaf50065ae4ea01eb5aeb13b1a45da3348.ips') @(0x6e6dc4) 4
    $mods = @(Get-KitMods $u2 | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object)
    Check (($mods -join ',') -eq 'Lower,OffTxt,Other') "patches elsewhere, disabled or not matched by name stay mods [$($mods -join ',')]"
    # With the built-in turned off in Add-Ons, Fritchii loads Dark's mod: it counts.
    Write-File (Join-Path $u2 'config\qt-config.ini') "[DisabledAddOns]`r`nsize=1`r`n1\title_id=$id`r`n1\disabled\size=1`r`n1\disabled\1\d=Dynamic FPS by Dark (built-in)`r`n"
    Check (@(Get-KitMods $u2).Count -eq 6) 'the built-in turned off: Dark''s mods count'
    Remove-Item -LiteralPath (Join-Path $u2 'config\qt-config.ini') -Force

    # Loose cheat files in the game's load folder ("Cheats" in Add-Ons), turned off by file name.
    Write-File (Join-Path $g2 'cheat_infinite_hearts.txt') '[Hearts]'
    $mods = @(Get-KitMods $u2 | ForEach-Object { Split-Path -Leaf $_ })
    Check ($mods -contains 'cheat_infinite_hearts.txt') 'a loose cheat_* file counts'
    Write-File (Join-Path $u2 'config\qt-config.ini') "[DisabledAddOns]`r`nsize=1`r`n1\title_id=$id`r`n1\disabled\size=1`r`n1\disabled\1\d=cheat_infinite_hearts.txt`r`n"
    Check (-not (@(Get-KitMods $u2 | ForEach-Object { Split-Path -Leaf $_ }) -contains 'cheat_infinite_hearts.txt')) 'a cheat file turned off does not'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Custom character models (skins) in coop-models beside the game's mods folder (kit-paths.ps1)
$cm = Join-Path ([System.IO.Path]::GetTempPath()) ('oot-coop-models-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $exeDir = Join-Path $cm 'game\bin'
    $models = Get-KitModelsDir $exeDir
    Check ($models -eq (Join-Path $exeDir 'coop-models')) 'models: coop-models beside the game''s mods folder, never in it'
    Check (@((Get-KitModelSkins $models).Skins).Count -eq 0 -and (Get-KitModelsHash $models) -eq '') 'models: no coop-models folder: no model, no hash'
    # The ID filter: 1 to 20 letters or digits; '.' and '_' folders quietly; files are no models.
    Check ((Test-KitSkinId 'Malon') -and (Test-KitSkinId 'A') -and (Test-KitSkinId ('a' * 20)) -and (Test-KitSkinId 'Link2')) 'skin id: letters and digits, 1 to 20'
    Check (-not (Test-KitSkinId '') -and -not (Test-KitSkinId ('a' * 21)) -and -not (Test-KitSkinId 'bad name') -and -not (Test-KitSkinId 'a-b') -and
        -not (Test-KitSkinId 'a_b') -and -not (Test-KitSkinId "Mal$([char]0xF6)n")) 'skin id: not empty, not 21, no space, dash, underscore or other letters'
    foreach ($d in 'Zelda', 'Malon', 'bad name', 'ThisNameIsFarTooLong123', '_importing', '.hidden') { New-Item -ItemType Directory -Force -Path (Join-Path $models $d) | Out-Null }
    Write-File (Join-Path $models 'notes.txt') 'not a model'
    Write-File (Join-Path $models 'Malon\romfs\Pack\Actor\Player_Adult.pack.zs') 'model'
    Write-File (Join-Path $models 'Zelda\romfs\Pack\Actor\Player_Child.pack.zs') 'model z'
    $found = Get-KitModelSkins $models
    Check ((@($found.Skins | ForEach-Object { $_.Id }) -join ',') -eq 'Malon,Zelda') "models: the valid folders, in order [$(@($found.Skins | ForEach-Object { $_.Id }) -join ',')]"
    Check ((@($found.Skins)[0].Path) -eq (Join-Path $models 'Malon')) 'models: each with its folder'
    Check ((@($found.Skipped) -join ',') -eq 'ThisNameIsFarTooLong123,bad name') "models: the others skipped (to be said), not _ or . folders [$(@($found.Skipped) -join ',')]"
    # The hash: paths, sizes and times; the same models the same hash, any change another.
    $h1 = Get-KitModelsHash $models
    Check ($h1 -match '^[0-9a-f]{64}$') 'models hash: a SHA-256'
    Check ((Get-KitModelsHash $models) -eq $h1) 'models hash: nothing changed, the same'
    Write-File (Join-Path $models 'bad name\romfs\x') 'skipped folders do not count'
    Write-File (Join-Path $models 'notes2.txt') 'nor files beside the folders'
    Check ((Get-KitModelsHash $models) -eq $h1) 'models hash: a skipped folder or a loose file does not change it'
    $f = Join-Path $models 'Malon\romfs\Pack\Actor\Player_Adult.pack.zs'
    (Get-Item -LiteralPath $f).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-5)
    $h2 = Get-KitModelsHash $models
    Check ($h2 -ne $h1) 'models hash: a file''s time changed, another hash'
    Write-File $f 'model, longer'
    $h3 = Get-KitModelsHash $models
    Check ($h3 -ne $h2) 'models hash: a file''s size changed, another hash'
    Write-File (Join-Path $models 'Malon\romfs\Tex\new.bntx.zs') 't'
    $h4 = Get-KitModelsHash $models
    Check ($h4 -ne $h3) 'models hash: a file added, another hash'
    New-Item -ItemType Directory -Force -Path (Join-Path $models 'Saria') | Out-Null
    $h5 = Get-KitModelsHash $models
    Check ($h5 -ne $h4) 'models hash: a model folder added (even empty), another hash'
    Remove-Item -LiteralPath (Join-Path $models 'Saria') -Recurse -Force
    Check ((Get-KitModelsHash $models) -eq $h4) 'models hash: that folder removed again, the hash before'
    # The stamp beside the pack and the rebuild decision.
    $pack = Join-Path $exeDir 'mods\contents\0400486024DEC000\coop-puppet'
    New-Item -ItemType Directory -Force -Path $pack | Out-Null
    Check (Test-KitModelsChanged $pack $models) 'models: a pack made without these models: changed (made again)'
    Save-KitModelsStamp $pack (Get-KitModelsHash $models)
    Check (-not (Test-KitModelsChanged $pack $models)) 'models: the stamp written after the pack: unchanged (not made again)'
    Write-File (Join-Path $models 'Zelda\romfs\Pack\Actor\Player_Child.pack.zs') 'model z, changed'
    Check (Test-KitModelsChanged $pack $models) 'models: a model changed: made again'
    Remove-Item -LiteralPath $models -Recurse -Force
    Check (Test-KitModelsChanged $pack $models) 'models: every model removed: made again (without them)'
    Save-KitModelsStamp $pack ''
    Check (-not (Test-Path -LiteralPath (Join-Path $pack 'coop-models.txt')) -and -not (Test-KitModelsChanged $pack $models)) 'models: no model and no stamp: unchanged (a kit without models keeps its pack)'

    # The pack build: every model; one the pack tool cannot build is left out and the pack made again.
    $skins = @([pscustomobject]@{ Id = 'BAD'; Path = 'C:\g\coop-models\BAD' }, [pscustomobject]@{ Id = 'Malon'; Path = 'C:\g\coop-models\Malon' },
        [pscustomobject]@{ Id = 'Mal'; Path = 'C:\g\coop-models\Mal' })
    $script:calls = @()
    # (a stand-in pack tool: refuses a model by its folder, or with $script:failAll every model with a line naming none)
    $script:failAll = $false
    $fake = {
        param([string[]]$Extra)
        $script:calls += , (@($Extra) -join ' ')
        if (-not $Extra) { return @{ Code = $(if ($script:noneFails) { 1 } else { 0 }); Lines = @('done') } }
        if ($script:failAll) { return @{ Code = 1; Lines = @('reading the game', 'error: something else broke', '') } }
        if ($Extra -contains 'BAD=C:\g\coop-models\BAD') { return @{ Code = 1; Lines = @('error: C:\g\coop-models\BAD is not a model mod (no changed Player_Adult or Player_Child pack)') } }
        return @{ Code = 0; Lines = @('done') }
    }
    $script:noneFails = $false
    $said = @(& { $r = Invoke-KitPackBuild $fake $skins; $script:r = $r } 6>&1 | ForEach-Object { "$_" })
    Check ($script:calls[0] -eq '--skin BAD=C:\g\coop-models\BAD --skin Malon=C:\g\coop-models\Malon --skin Mal=C:\g\coop-models\Mal') "pack build: first with every model [$($script:calls[0])]"
    Check ($script:r.Code -eq 0 -and ($script:r.Built -join ',') -eq 'Malon,Mal' -and ($script:r.Left -join ',') -eq 'BAD') "pack build: the model named by its folder left out, the others built [$($script:r.Built -join ',') / $($script:r.Left -join ',')]"
    Check ($script:calls.Count -eq 2 -and $script:calls[1] -eq '--skin Malon=C:\g\coop-models\Malon --skin Mal=C:\g\coop-models\Mal') "pack build: made again without it [$($script:calls[1])]"
    Check (($said -join '|') -eq '  custom model BAD could not be built: C:\g\coop-models\BAD is not a model mod (no changed Player_Adult or Player_Child pack); left out') "pack build: one plain line naming it [$($said -join '|')]"
    # A folder named in the line is that model, not one whose folder name starts the same (Mal and Malon).
    $script:calls = @()
    $fake2 = {
        param([string[]]$Extra)
        $script:calls += , (@($Extra) -join ' ')
        if ($Extra -contains 'Malon=C:\g\coop-models\Malon') { return @{ Code = 1; Lines = @('error: C:\g\coop-models\Malon\romfs: has an exefs folder') } }
        return @{ Code = 0; Lines = @() }
    }
    $said = @(& { $script:r = Invoke-KitPackBuild $fake2 @($skins[1], $skins[2]) } 6>&1 | ForEach-Object { "$_" })
    Check ($script:r.Code -eq 0 -and ($script:r.Left -join ',') -eq 'Malon' -and ($script:r.Built -join ',') -eq 'Mal') "pack build: Malon's folder named, Mal kept [$($script:r.Built -join ',') / $($script:r.Left -join ',')]"
    # Named by its ID alone (no folder in the line).
    $fake3 = {
        param([string[]]$Extra)
        if ($Extra -contains 'Mal=C:\g\coop-models\Mal') { return @{ Code = 1; Lines = @('error: --skin Mal: no changed Player_Adult or Player_Child pack') } }
        return @{ Code = 0; Lines = @() }
    }
    $said = @(& { $script:r = Invoke-KitPackBuild $fake3 $skins } 6>&1 | ForEach-Object { "$_" })
    Check ($script:r.Code -eq 0 -and ($script:r.Left -join ',') -eq 'Mal' -and ($script:r.Built -join ',') -eq 'BAD,Malon') "pack build: named by its ID as a word (Malon is not Mal) [$($script:r.Built -join ',') / $($script:r.Left -join ',')]"
    # A failure that names no model: made again without any; every model said.
    $script:calls = @()
    $script:failAll = $true
    $said = @(& { $script:r = Invoke-KitPackBuild $fake @($skins[1], $skins[2]) } 6>&1 | ForEach-Object { "$_" })
    Check ($script:r.Code -eq 0 -and ($script:r.Left -join ',') -eq 'Malon,Mal' -and @($script:r.Built).Count -eq 0 -and $script:calls.Count -eq 2 -and $script:calls[1] -eq '') "pack build: no model named: made again without any [$($script:calls -join ' / ')]"
    Check ($said.Count -eq 2 -and $said[0] -eq '  custom model Malon could not be built: something else broke; left out') "pack build: each model said, with the error line [$($said -join '|')]"
    # The pack tool failing without any model too: its exit code, no model built (the caller says the pack was not made).
    $script:noneFails = $true
    $said = @(& { $script:r = Invoke-KitPackBuild $fake @($skins[1]) } 6>&1 | ForEach-Object { "$_" })
    Check ($script:r.Code -eq 1 -and @($script:r.Built).Count -eq 0) 'pack build: failing without models too: the failure stays'
    $script:noneFails = $false
    $script:failAll = $false
    # No model: one plain run.
    $script:calls = @()
    $said = @(& { $script:r = Invoke-KitPackBuild $fake @() } 6>&1 | ForEach-Object { "$_" })
    Check ($script:r.Code -eq 0 -and $script:calls.Count -eq 1 -and $script:calls[0] -eq '' -and $said.Count -eq 0) 'pack build: no model: the pack tool once, as before'
} finally {
    Remove-Item -LiteralPath $cm -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Host "$failed check(s) failed"; exit 1 }
Write-Host 'all checks passed'
