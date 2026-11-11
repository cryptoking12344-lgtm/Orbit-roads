# Orbit Roads

A portrait space-road runner for Android, in the spirit of the old DOS road-hopping games. 10 worlds, 30 roads, 6 ships. Fully offline: no ads, no purchases.

Built with Godot 4.3. Ships, tiles and planets are modelled in Blender; skies, roads, music and sound effects are generated for this game.

## Get the APK

Every push to `main` builds the APK with GitHub Actions and publishes it under **Releases → Orbit Roads (latest build)**. Download `orbit-roads.apk` on your phone and open it to install.

Builds are signed with the test key in `ci/test.keystore` so updates install over each other. For a Play Store release, add your own key as the repo secrets `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASS` and `ANDROID_KEYSTORE_USER`.

## How it plays

- Stay on the road, jump the gaps, and reach the finish gate before fuel or air runs out.
- Tiles: cyan boosts, purple slows, pale is slick (no steering), orange burns, blue refills fuel and air.
- Each road has its own gravity. A crash restarts the road.
- Two control layouts: **Invisible** (left half drags to steer and set speed, right half taps to jump) and **Buttons**.

## Project layout

- `scripts/sim.gd` — game logic at a fixed 60 Hz tick
- `scripts/play.gd` — builds and draws a road, effects, HUD, result screens
- `scripts/main.gd` — menus
- `data/roads.json` — all 30 roads
- `tests/bot.gd` — headless check that every road can be cleared

Fonts: Inter (SIL Open Font License).
