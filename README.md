# Centipede

[![CI](https://github.com/sneeper/centipede/actions/workflows/ci.yml/badge.svg)](https://github.com/sneeper/centipede/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A from-scratch recreation of the classic Atari arcade game **Centipede** for
macOS, built in Swift with **SpriteKit** and packaged as a Swift Package (no
`.xcodeproj` required). Centipede, spider, flea, scorpion, poison mushrooms,
high scores, and an attract mode — all in code, no art assets.

## Install

**Download (easiest):** grab `Centipede-macOS.zip` from the
[latest release](https://github.com/sneeper/centipede/releases/latest), unzip,
and move `Centipede.app` to `/Applications`.

The download is open-source and only ad-hoc signed (no paid Apple Developer ID),
so the first time you open it macOS will warn about an unidentified developer.
Either **right-click the app → Open → Open**, or clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Centipede.app
```

**Build from source:** see below — requires Xcode or the Swift toolchain.

## Run it

From this folder:

```sh
swift run            # builds and launches the game window
```

Or open it in Xcode and press ▶:

```sh
open Package.swift   # opens the package in Xcode
```

> If you ever see a `sandbox_apply: Operation not permitted` error when building
> from a restricted shell, add `--disable-sandbox` (e.g. `swift build --disable-sandbox`).
> A normal Terminal doesn't need this.

## Build a standalone app

To get a double-clickable `Centipede.app` with an icon that you can keep in
`/Applications`:

```sh
./make_app.sh            # builds release, generates the icon, assembles the bundle
cp -R Centipede.app /Applications/
```

`make_app.sh` compiles a release binary, generates a Core Graphics app icon
(`Tools/makeicon.swift` → `.icns`, no art files needed), writes a proper
`Info.plist`, and ad-hoc code-signs the bundle. Because it's built locally and
never quarantined, it launches without Gatekeeper prompts. (Note: as a bundled
app it stores high scores under its bundle id, so scores from `swift run` won't
carry over.)

## Controls

| Action            | Input                          |
| ----------------- | ------------------------------ |
| Move shooter      | Mouse (relative, trackball-style; roams the bottom zone) |
| Fire              | Hold left mouse button / Space |
| Free / re-grab cursor | `Esc` (⌘-Tab away also frees it) |
| Restart           | `R`, or click after Game Over  |
| Full screen       | ⌘F (toggles; scales everything up, centered) |
| Quit              | ⌘Q                             |

During a round the mouse cursor is **captured** (hidden and locked to the window)
so it can't accidentally slide out and drop focus — the shooter is driven by
relative motion. Press `Esc` to free the cursor (and again to re-grab), or just
⌘-Tab away; focus is restored automatically when you return. Click back into the
window to re-grab.

## What's implemented (Milestone 1 — the core loop)

- Grid-based playfield (`GameConfig`) with a scattered **mushroom field**.
- **Mouse-controlled shooter** confined to the bottom rows, with auto-fire.
- A **centipede** that crawls horizontally and drops down a row + reverses when it
  hits a wall or a mushroom (classic behavior), moving as a follow-the-leader train.
- **Shooting a segment** drops a mushroom in its place and *splits* the centipede;
  each piece keeps crawling. Shooting the head re-promotes the next segment.
- **Mushrooms** take 4 hits to clear, and **regenerate to full when you lose a life**
  (as in the arcade).
- **Scoring**: body segment 10, **head 100**, mushroom 1, flea 200, spider 300/600/900
  by proximity, scorpion 1000.
- **Wave progression** (arcade-style): each wave keeps 12 total segments but shortens
  the main centipede by one and adds another lone fast "head" centipede, and speeds up.
  Lone heads also keep **injecting mid-wave** once the centipede reaches your zone.
- HUD with score/level, **shooter-head icons for spare lives**, an **extra life every
  12,000 points**, life loss on contact, and a Game Over → restart flow.
- **Procedural sound** (`SoundEngine`) — square-wave blips synthesized at runtime
  for firing, segment explosions, mushroom hits, death, and wave-clear. No audio
  files to bundle.
- **Hit explosions** — code-configured `SKEmitterNode` particle bursts on segment
  kills, mushroom clears, and player death.
- **Spider** — periodically skitters in from a side, zig-zags through the player
  zone, eats mushrooms it crosses, and is worth 300/600/900 points by how close
  you are when you shoot it (with a floating score popup).
- **Flea** — drops straight down when the player zone runs low on mushrooms,
  replanting a trail as it falls; takes two hits (the first speeds it up), 200 points.
- **Scorpion** (from level 2) — crosses the upper field poisoning every mushroom it
  touches (they glow red); a centipede link that reaches a poisoned mushroom dives
  straight down at the player, then recovers at the bottom. Worth 1000 points.
- **Game-over sequence + high scores** — prominently shows your final score; if it
  makes the **top 10**, you type 3 initials (A–Z, Delete to fix, Return to confirm)
  and your entry is highlighted in the table. Scores persist across launches
  (`HighScores`, via `UserDefaults`).
- **Attract mode** — when nobody's playing it cycles **Title → High Scores → AI
  demo round → repeat**. The demo plays a real round driven by a simple AI, but
  with **sound muted**, **lives hidden**, and **nothing recorded**. Press fire /
  click at any point to start. The backdrop tint cycles per wave and per screen.
- **Visual polish** — neon **glow** on the shooter, centipede, bullets and bugs;
  a faint **playfield grid**; **animated bug legs**; **per-wave sprite recoloring**
  (4 palettes); and a **screen-shake** on death and scorpion kills.

## Architecture

```
Package.swift                 SwiftPM manifest (macOS executable)
Sources/Centipede/
  main.swift                  Hand-rolled AppKit bootstrap -> SKView -> GameScene
  GameConfig.swift            All tunable constants (grid size, speeds, counts)
  GameScene.swift             The game: entities, game loop, input, collisions, FX
  SoundEngine.swift           Runtime square-wave sound synthesis (AVAudioEngine)
  HighScores.swift            Top-10 high score store (persisted via UserDefaults)
Tools/makeicon.swift          Core Graphics app-icon generator (no art assets)
make_app.sh                   Packages everything into Centipede.app
```

The game loop lives in `GameScene.update(_:)`: it polls the mouse, advances
bullets every frame, ticks the centipede on a fixed interval, then resolves
collisions. Collision is done manually against the grid (not the physics engine)
so the discrete, grid-locked movement stays deterministic and arcade-accurate.

## Roadmap (toward full Centipede)

Rough order, smallest/most-fun first:

1. ~~**Sound + juice**~~ ✅ done — procedural blips + explosion particle bursts.
2. ~~**Spider**~~ ✅ done — bounces through the player zone, eats mushrooms,
   proximity-based scoring (300/600/900).
3. ~~**Flea**~~ ✅ done — drops vertically when the lower field is sparse, leaving
   a trail of mushrooms; takes 2 hits.
4. ~~**Scorpion**~~ ✅ done — poisons mushrooms so a passing centipede dive-bombs;
   appears from level 2.
5. ~~**Proper lives / waves / scoring**~~ ✅ done — head=100, mushroom regeneration
   on death, shorter-main-plus-more-heads wave progression, **bonus life every
   12k**, **shooter-head life icons**, and **mid-wave lone-head injection**.
6. **Art pass** — ✅ in-code visual polish done (neon glow, grid, animated legs,
   per-wave recoloring, screen-shake). Still optional: swap the placeholder shapes
   for real **sprite textures** (PNGs via `SKTexture`).
7. ~~**High-score table**~~ ✅ done. ~~**Attract / title screen**~~ ✅ done
   (title + high-score + AI demo cycle). Still open: pause, settings/difficulty curve.

When the placeholder shapes start to feel limiting, that's the cue to add a
texture/asset pipeline (step 6) and migrate the `SKShapeNode`s to `SKSpriteNode`s.

## Contributing

Issues and pull requests are welcome. The whole game is plain Swift in
`Sources/Centipede/`; `swift build` (or `swift run`) is the full dev loop, and CI
builds every push and PR. Most tunable values live in `GameConfig.swift`.

## Releasing

Cutting a release is automated. Push a version tag and the
[Release workflow](.github/workflows/release.yml) builds `Centipede.app`, zips
it, and attaches it to a GitHub Release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

## License

[MIT](LICENSE) © 2026 sneeper.

## Disclaimer

This is an unofficial, fan-made tribute for educational purposes. *Centipede* is
a trademark of Atari Interactive, Inc. This project is **not affiliated with,
endorsed by, or sponsored by Atari**, and ships none of the original game's code
or assets — all graphics and sound are generated in code.

