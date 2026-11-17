# Makes the custom models test zip (custom-models-test-<name>.zip): the files of this branch that differ from the
# official kit, at their kit paths, with skins-test.ps1, the two .bat files and README.txt.
#
#   powershell -ExecutionPolicy Bypass -File tools\skins-test\make_release.ps1 -BuildDir <cmake build> -KitRelease <kit release tag> -Name <name>
#
# -BuildDir    this repo's CMake build (Release) with hookshot_coop.dll and coop_server.exe
# -Base        the official release's commit to compare with (default: the tag named by -KitRelease, else upstream/main)
# -KitRelease  the Squadala kit release the test is for (the installer refuses any other)
# -Name        the test build's name (letters, digits, dots, dashes)
# -OutDir      where the folder and zip go (default: <repo>\..\custom-models-test-out)
param(
    [Parameter(Mandatory)][string]$BuildDir,
    [Parameter(Mandatory)][ValidatePattern('^v[0-9][0-9A-Za-z._-]*$')][string]$KitRelease,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Name,
    [string]$Base = '',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $here '..\..')).Path
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $repo) 'custom-models-test-out' }
if (-not $Base) {
    $Base = if (& git -C $repo rev-parse -q --verify "refs/tags/$KitRelease" 2>$null) { $KitRelease } else { 'upstream/main' }
}
$commit = (& git -C $repo rev-parse --short=12 HEAD).Trim()
$branch = (& git -C $repo rev-parse --abbrev-ref HEAD).Trim()
if (& git -C $repo status --porcelain --untracked-files=no) { throw 'The repo has uncommitted changes: commit them first, so BUILD.txt names what is in the zip.' }

$dll = Get-ChildItem -LiteralPath $BuildDir -Recurse -File -Filter 'hookshot_coop.dll' | Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
$srv = Get-ChildItem -LiteralPath $BuildDir -Recurse -File -Filter 'coop_server.exe' | Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
if (-not $dll -or -not $srv) { throw "No Release hookshot_coop.dll / coop_server.exe under $BuildDir" }
# (built after the last commit that changed compiled code; a change to scripts or the pack tool needs no new build)
$codeTime = (Get-Date ((& git -C $repo log -1 --format=%cI HEAD -- coop hookshot lichii server CMakeLists.txt cmake).Trim())).ToUniversalTime()
foreach ($f in @($dll, $srv)) {
    if ($f.LastWriteTimeUtc -lt $codeTime) { throw "$($f.Name) is older than the last change to the module or server code: build again first." }
}

$folder = Join-Path $OutDir 'custom-models-test'
if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
$payload = Join-Path $folder 'payload'
New-Item -ItemType Directory -Force -Path $payload | Out-Null
function Put([string]$Src, [string]$Rel) {
    $dst = Join-Path $payload $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath $Src -Destination $dst
    Write-Host "  payload\$Rel"
}
Put $dll.FullName 'hookshot\hookshot_coop.dll'
Put $srv.FullName 'server\coop_server.exe'
# The repo files the kit carries, where this branch differs from the official release.
$changed = @(& git -C $repo diff --name-only --diff-filter=AM "$Base..HEAD")
foreach ($f in $changed) {
    if ($f -match '^tools/puppet_pack/([^/]+\.py)$') { Put (Join-Path $repo $f) "tools\puppet_pack\$($Matches[1])" }
    elseif ($f -match '^tools/release/kit/scripts/([^/]+)$') { Put (Join-Path $repo $f) "scripts\$($Matches[1])" }
}
foreach ($f in 'skins-test.ps1', 'Install-CustomModels.bat', 'Remove-CustomModels.bat', 'README.txt') {
    Copy-Item -LiteralPath (Join-Path $here $f) -Destination (Join-Path $folder $f)
}
$sha = { param($p) (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.Substring(0, 16).ToLowerInvariant() }
@(
    "name: $Name",
    "kit_release: $KitRelease",
    "commit: $commit",
    "branch: $branch",
    "base: $Base",
    "built: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))",
    "hookshot_coop.dll: $(& $sha $dll.FullName)",
    "coop_server.exe: $(& $sha $srv.FullName)",
    "source: https://github.com/Waso2101/oot-remake-multiplayer/tree/$commit"
) | Set-Content -LiteralPath (Join-Path $folder 'BUILD.txt') -Encoding ASCII
$zip = Join-Path $OutDir "custom-models-test-$Name-$KitRelease.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $folder -DestinationPath $zip
Write-Host "zip: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
