CUSTOM MODELS - TEST BUILD (unofficial)
=======================================

Play as a character model mod (Playable Malon, Playable Zelda, ...) in co-op, and see the
other players in theirs. This is a TEST from Waso2101's fork (issue 250 on
daurosk/oot-remake-multiplayer). It is not an official Squadala release.

You need: a Squadala kit of the version named in BUILD.txt (kit_release). Everyone you
play with needs this same test build.

INSTALL
1. Close the game and the server.
2. Unzip this folder into your kit folder (where "Start OoT Co-op.bat" is), so you get
   <kit>\custom-models-test\Install-CustomModels.bat
3. Double-click Install-CustomModels.bat.
   It checks the kit version, keeps a copy of every file it replaces, and turns the kit's
   auto-update off (an update would overwrite the test).

ADD A MODEL
1. Download a character model mod (a folder that holds "romfs").
2. Put that folder into <kit>\hookshot\game\coop-models\ (the installer makes a shortcut
   "Custom models folder" in the kit folder). Rename the folder to letters/digits only,
   e.g. Malon:   coop-models\Malon\romfs\...
   Never put a model mod into the "mods" folder: it would replace everyone's Link.
3. Start the kit as usual. The first start makes the puppet pack again (a minute or two).
4. In the game: pause menu > Multiplayer > Customize Link > Characters, pick it, Confirm.
   Your own Link changes at the next start; the others see it at once.
   Other players see your model only if they have the same model folder (same files).

REMOVE
Double-click Remove-CustomModels.bat. Every replaced file is put back, auto-update is
set back, and the next start makes the official puppet pack again. Your model folders
stay in coop-models (the official kit ignores them).

KNOWN LIMITS
- Hair and skirts don't swing on the other players' view (no cloth physics yet).
- Only models whose skeleton uses Link's bone names get his running/sword poses.
- Two games on one PC: each must run in the foreground to see the other.

Problems: collect-logs.cmd in the kit, then tell Waso (Discord) what you did.
