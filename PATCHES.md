# Installing this JumpHUD fork

This repo is **JumpHUD v2.6.4** plus a set of local patches. The patches exist because
v2.6.4 began shipping files at paths that other mods in `tf/custom/` already owned, and
because one shipped font is registered under a name it doesn't have.

Everything below assumes a clean checkout of this repo.

---

## 1. Prerequisites

- Team Fortress 2 installed (Steam, any library)
- **TF2 must be closed.** The installer refuses to run while `tf.exe` / `tf_win64.exe` is live.
- Admin rights if TF2 lives under `C:\Program Files (x86)`. The installer checks write
  access up front and tells you if it can't write.
- Python 3 + `fontTools` — **only** if you need to re-subset the font (patch 2 below):

  ```powershell
  python -m pip install fontTools
  ```

## 2. Install

From the repo root:

```powershell
.\install-jumphud.ps1
```

| Flag | Effect |
|---|---|
| *(none)* | Mirror HUD files into `tf/custom/jumphud`, keep your settings |
| `-ResetConfig` | Also move `tf/cfg/jumphud` aside so the HUD regenerates defaults |
| `-WhatIf` | Preview — prints what it would copy/delete, changes nothing |
| `-TfPath '<path>'` | Install to a non-default Steam library |
| `-BackupRoot '<path>'` | Override backup location (default `%LOCALAPPDATA%\TF2-Jumphud-Backups`) |
| `-SkipBackup` | Replace without backing up |

The script auto-detects the install via the Steam registry key and `libraryfolders.vdf`,
mirrors `<repo>\jumphud` → `<TF2>\tf\custom\jumphud`, and backs up whatever was there to a
timestamped folder first. Mirroring (rather than copying) is deliberate — it removes files
that upstream deleted between releases.

Run `-ResetConfig` when crossing a major JumpHUD release. JumpHUD stores your customization
choices in `tf/cfg/jumphud`, and those files are version-specific; v2.6.4 moved them into a
`customization/` layout. Stale files are not read.

## 3. Local patches

These are the differences from stock upstream v2.6.4. **Don't revert them without reading
why** — two of them exist to stop v2.6.4 from shadowing your own mods.

### Patch 1 — JetBrains Mono font name

The font's real family name is `JetBrainsMono NFM`. Upstream registers it as
`JetBrainsMono Nerd Font Mono`, which matches nothing, so Source silently falls back to a
default font and the menu entry appears to do nothing.

Fixed in 4 files, 7 references:

- `resource/scheme/font_paths.res` (slot 34)
- `resource/ui/custom/fonts/font_mono_cs_jetbrainsmono.res`
- `resource/ui/custom/fonts/font_mono_ss_jetbrainsmono.res`
- `resource/ui/custom/#customization_menu/font_showcase.res`

**If you ever change this font, use the family name from the font itself, not from the
filename.** Read it with:

```powershell
python -c "from fontTools.ttLib import TTFont; print(TTFont(r'<path>.ttf')['name'].getDebugName(1))"
```

Other JumpHUD fonts have the same bug (`Kodchasan Bold` vs `Kodchasan`, `Eternal UI 2
Regular` vs `Eternal UI 2`, `Freeman Regular` vs `Freeman`, `Chivo Mono Regular` vs
`Chivo Mono`) — they are **not** patched here.

### Patch 2 — JetBrains Mono subset and size

Nerd Fonts bundle ~11,800 icon glyphs. Upstream ships one at 2.5 MB / 12,608 glyphs; every
other font in the set is under 325 KB. Subset to Latin + punctuation + symbols:

```powershell
python -m fontTools.subset `
  jumphud\resource\scheme\fonts\optional\JetBrainsMonoNerdFontMono-Regular.ttf `
  --output-file=out.ttf --layout-features="*" `
  --name-IDs="*" --name-legacy --name-languages="*" `
  --unicodes="U+0020-007E,U+00A0-00FF,U+0100-017F,U+2000-206F,U+2070-209F,U+20A0-20CF,U+2100-214F,U+2150-218F,U+2190-21FF,U+2200-22FF,U+2500-257F,U+25A0-25FF,U+2600-26FF,U+2713-2717,U+FEFF"
```

Result: **2,573,248 → 149,804 bytes, 12,608 → 1,044 glyphs**, family name preserved.

**Do not add `--no-hinting`.** Dropping `fpgm`/`prep`/`cvt` makes small text render badly, and
the console draws at `Tall 16`.

`Tall` values also lowered, since NFM is much wider than the HUD's default face:

| File | Was | Now |
|---|---|---|
| `font_mono_ss_jetbrainsmono.res` (ConsoleText, DefaultFixedOutline) | 20 | **16** |
| `font_mono_cs_jetbrainsmono.res` (Default, HudHintText) | 10 | **9** |

Everything known to render correctly in JumpHUD sits at 16/9. The other 20/11 fonts
(Kodchasan, Chivo Mono, Freeman, Space Grotesk) are not valid references — they all carry
the patch 1 name bug.

**Why patch 2 exists** — two different symptoms, two different causes:

- *Font doesn't load at all, renders as default* → **patch 1**, the name mismatch.
- *Font loads but renders badly* → **patch 2**, the subsetting. Too-narrow ranges dropped box
  drawing, arrows and math symbols; `--no-hinting` wrecked small text; `Tall 20` overflowed.

Only the Nerd Font *icon* glyphs are gone; letterforms are untouched.

`test-jumphud-font.ps1 -Variant A|B|C` swaps font + size combinations in place if you ever
need to re-bisect this.

### Patch 3 — JetBrains Mono added to the menu

Upstream ships the font, scheme files and aliases but never adds a button, so it was
console-only. `hud_customization_fonts_mono.res` gains a `JetBrainsMono` panel pinned below
`Comic`, and the picker height goes `960 → 1008` (48px × 21 rows) so the new row scrolls.

### Patch 4 — mono font aliases reload the scheme

Selecting a font wrote the `#base` files but never reloaded, so nothing changed on screen.
`hud_reloadscheme` appended to the 20 composite `jh_font_mono_*` aliases in
`cfg/customization/jh_fonts.cfg` — the ones the menu buttons call. Deliberately **not** added
to the `_cs_` / `_ss_` aliases, which would reload twice per selection.

The primary / speedo / sourcescheme font aliases still lack this.

### Patch 5 — `particles/stickybomb.pcf` deleted

**Do not restore this.** It collides with `tf/custom/my_custom_stuff/particles/stickybomb.pcf`.

Source resolves `particles/stickybomb.pcf` by path — **first match wins, no merging.** The
two files define disjoint effect sets:

| `my_custom_stuff` (yours) | JumpHUD v2.6.4 |
|---|---|
| `stickybombtrail_red2`, `stickybombtrail_blue2` | `circle1` |
| `pipebombtrail_red2`, `pipebombtrail_blue2` | `circle2_stickypulse_blue/red` |
| `pipebomb_glow_blue`, `render_rope`, … | `sc_softglow_stickytrail_blue/red` |

Whichever won, the other side's effects were missing. v2.5.0 shipped no `particles/` folder,
so this is a v2.6.4 regression. Cost: JumpHUD's 5 optional pulse/glow effects stop working
(referenced by `sc_softglow_stickytrail_*.vmt`, reloaded via `jh_reloadkeymaterials.cfg`).

### Patch 6 — `materials/models/weapons/w_stickybomb/` deleted (26 files)

**Do not restore this.** It collides with `tf/custom/sticky-bombs-glow-in-the-dark.vpk`,
which ships:

```
materials/models/weapons/w_stickybomb/w_stickybomb_red.vmt
materials/models/weapons/w_stickybomb/w_stickybomb_blue.vmt
materials/models/weapons/w_stickybomb/w_stickybomb_red.vtf
materials/models/weapons/w_stickybomb/w_stickybomb_blue.vtf
```

Loose files in `tf/custom/` outrank VPK content, so JumpHUD's `.vmt` files shadowed the skin
silently. The `.vtf` textures still loaded, but were drawn through JumpHUD's material, whose
`w_stickybomb_*_def.vmt` runs a `StickybombGlowColor` proxy forcing `$color2` and
`$selfillumtint` — so the skin appeared recoloured rather than missing.

v2.5.0 shipped no `materials/models/` folder at all, so this is also a v2.6.4 regression.

Cost: JumpHUD → Jump Settings → **Stickybombs** is now a dead menu option. The 21 colour
aliases remain in `cfg/customization/jh_visuals.cfg` and write a `#base` pointing at deleted
files, so clicking one does nothing. It also frees 1.37 MB.

You can have JumpHUD's colour picker **or** the skin — both want the same two `.vmt` paths
and only one can hold them.

### Patch 7 — `#` comments in `jh_shaders.cfg`

`#` is **not** a comment character in exec'd `.cfg` files. Three commented-out aliases in
`cfg/customization/jh_shaders.cfg` used `#`, so they were parsed as commands and printed
`Unknown command "#"` three times at startup. Changed to `//`.

### Installer behaviour — hitmarker file

`scripts/hudanimations_manifest.txt` loads `cfg/jumphud/jh_hitmarker_animation.txt` on every
launch. That file is only written when you change the hitmarker setting in the menu, so after
`-ResetConfig` it's missing and you get `Couldn't find script file` repeatedly. The installer
now creates it if absent, so this can't recur.

## 4. Verify

```powershell
$hud = "C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\tf\custom\jumphud"

# version
(Get-Content "$hud\cfg\jh_versioninfo.cfg" | Select-String Release).Line.Trim()

# font name matches the font's real family name, old name gone
@(Get-ChildItem $hud -Recurse -Include *.res | Select-String 'JetBrainsMono NFM').Count
@(Get-ChildItem $hud -Recurse -Include *.res | Select-String 'Nerd Font Mono').Count   # want 0

# mono menu has 21 entries incl. jetbrains
(Select-String "$hud\resource\ui\custom\#customization_menu\hud_customization_fonts_mono.res" `
  -Pattern 'engine jh_font_mono_').Count

# stickybomb: your pcf is sole owner
Get-ChildItem "C:\...\tf\custom" -Recurse -Filter stickybomb.pcf

# jumphud's overrides are gone
Test-Path "$hud\particles\stickybomb.pcf"                                    # want False
Test-Path "$hud\materials\models\weapons\w_stickybomb"                       # want False
```

In-game checks: launch TF2 → JumpHUD → Fonts → Mono → **JETBRAINS MONO** (last row); open the
console and confirm the text is monospaced. Throw a stickybomb and confirm both the grenade
skin and the trail.

## 5. Known harmless messages

```
'jh_mat_reload_custom_N' not present; not executing.
```

Intentional extension hooks — see the comment at the top of `cfg/jh_reloadkeymaterials.cfg`:
*"mods updated to work with jumphud should use these files."* Upstream never defines them, so
they always report missing. Not a fault.

## 6. Updating from upstream

**The two deletions will come back.** Pulling a newer upstream release restores
`particles/stickybomb.pcf` and `materials/models/weapons/w_stickybomb/`, and the conflicts
return with them — silently, with no error in the console. Re-apply patches 5 and 6 after
every upstream merge, and re-check patches 1 and 3 in case the font files were renamed.

If you'd rather keep JumpHUD's stickybomb colour feature than the skin, drop patch 6 and
accept that the skin VPK won't apply.
