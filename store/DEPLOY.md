# Shipping Perihelion

What is done, what is left, and which parts only you can do.

---

## Built and verified

| Artifact | Where | Notes |
|---|---|---|
| iOS IPA (dev-signed) | `build/ios/ipa/perihelion.ipa` | for the OTA link; App Store needs a fresh archive |
| Android App Bundle | `build/app/outputs/bundle/release/app-release.aab` | signed with the upload key, verified |
| App icon, all sizes | `ios/.../AppIcon.appiconset`, `android/.../mipmap-*` | from `tool/generate_icon.py` |
| Play feature graphic | `store/feature-graphic.png` | 1024×500 |
| 1024 icon | `store/icon-1024.png` | both stores |
| Screenshots | `store/screenshots/ios-6.9/` | four, 1320×2868 |
| Listing copy | `store/listing.md` | names, descriptions, keywords, privacy answers |
| Privacy policy | https://cglendenning.github.io/graph-visualization/privacy.html | live |

## The signing key — read this first

`~/keys/perihelion-upload.jks` with its password in `~/keys/perihelion-key.properties`.

**Back both up somewhere you will still have in five years.** If you lose this key you cannot ship an update to the same Play listing without asking Google to reset it. Neither file is in the repo, and `.gitignore` now refuses `*.jks`, `*.keystore` and `key.properties` so one cannot be committed by accident.

Upload key SHA-1: `3B:56:62:60:6A:8B:24:8E:68:F2:19:43:D7:5D:A1:FD:8D:E8:18:29`

---

## Apple — what I need from you

1. **Confirm the Developer Program is current.** Team `MCALPSQ5P5` already has a distribution certificate, so this is probably a yes.
2. **Register the bundle id** `com.craigglendenning.perihelion` at developer.apple.com → Identifiers, or let Xcode do it on first archive.
3. **Create the app record** in App Store Connect: name `Perihelion`, primary language English (US), bundle id as above, SKU anything (`perihelion-001`).
4. **App Store Connect API key** — if you point me at one (you used `H96P2D43T6` for a previous project), I can build the distribution archive and upload it without you touching Xcode. Otherwise you upload from Xcode Organizer.
5. **Answer the age-rating questionnaire.** These are legal declarations and must be yours. Guidance is in `listing.md`; expect 12+.
6. **App Privacy** → choose *Data Not Collected*. Paste the privacy URL above.

## Google Play — what I need from you

1. **A Play Console account** (one-off $25). I cannot create or pay for this.
2. **Create the app**, then upload `app-release.aab`.
3. **Data safety form** — answers are in `listing.md`; everything is "no".
4. **Content rating (IARC) questionnaire** — again a legal declaration, must be yours. Declare that the app shows live web content that the developer does not curate.
5. **Target audience** — 13+ is the honest answer given uncurated encyclopedia content.

---

## One screenshot I could not take

The four captured shots are all of the graph. The detail screen — Wikipedia extract, connections list — needs a tap, and driving the simulator requires Accessibility permission for the terminal, which only you can grant.

The simulator is already running with the app installed, so it is two taps:

```bash
open -a Simulator                       # already booted: "Perihelion 6.9"
# tap the centre circle, then:
xcrun simctl io booted screenshot store/screenshots/ios-6.9/05-detail.png
```

Both stores accept four screenshots, so this is a nice-to-have rather than a blocker.

If you would rather I automate it: System Settings → Privacy & Security → Accessibility → enable your terminal, tell me, and I will script the taps.

---

## Rebuilding

```bash
# regenerate every icon and store graphic
python3 tool/generate_icon.py

# Android release bundle (uses ~/keys automatically)
flutter build appbundle --release

# iOS App Store archive
flutter build ipa --release            # then upload from Organizer or altool
```

---

## Housekeeping

Disk ran to 2 GB during the simulator build. Worth reclaiming when you are done:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/*   # several GB
rm -rf ~/.gradle/caches                          # ~3.8 GB
xcrun simctl delete "Perihelion 6.9"             # after screenshots
```
