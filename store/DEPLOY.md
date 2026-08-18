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

## Credentials found on this machine

**App Store Connect API** — verified working, 13 apps visible on the account.

| | |
|---|---|
| Key id | `MRKVCR3WF6` |
| Issuer id | `78bfbe39-6c61-4296-b086-b36925bcc396` |
| Key file | `~/.appstoreconnect/private_keys/AuthKey_MRKVCR3WF6.p8` |
| Working example | `~/greenpyramid/scripts/asc_release.py` |

A second key, `H96P2D43T6`, is present in the same folder and on the Desktop.

**Google Play** — `~/greenpyramid/scripts/play_publish.py` exists and works, but it takes a
Google Cloud **service-account JSON** as an argument and **no such key is on this machine**.
That is the one Play credential that has to be recreated.

## Apple — done, and what is left

Done already:

- Bundle id `com.craigglendenning.perihelion` **registered** (id `CL9WD6DKTD`). It was not
  registered before: the dev builds worked only because the team wildcard profile covers any
  identifier, which App Store distribution does not.

Only you can do:

1. **Create the app record.** The API refuses this outright — `apps` allows only
   `GET_COLLECTION, GET_INSTANCE, UPDATE`. In App Store Connect → Apps → **+**:
   name `Perihelion Graph`, language English (US), bundle id `com.craigglendenning.perihelion`,
   SKU `perihelion-001`.
2. **Age rating questionnaire** — a legal declaration. Guidance in `listing.md`; expect 12+.
3. **App Privacy** → *Data Not Collected*, plus the privacy URL above.

Once the record exists, **I can do the rest without you**: build the distribution archive,
upload it with the key above, and set the description, keywords, and screenshots through the
API. Just say go.

## Google Play — what is left

1. **Create a service account** so uploads can be automated:
   Google Cloud Console → IAM → Service Accounts → create → add a JSON key.
   Then Play Console → Users and permissions → invite that service-account email and grant
   release permissions. Save the JSON somewhere outside this repo, e.g. `~/keys/`.
2. **Create the app** in Play Console (the API cannot create listings either).
3. **Data safety form** — answers in `listing.md`; everything is "no".
4. **Content rating (IARC)** — a legal declaration, must be yours. Declare live web content
   the developer does not curate.
5. **Target audience** — 13+ is the honest answer for uncurated encyclopedia content.

With the JSON key in place, the existing script does the upload:

```bash
python3 ~/greenpyramid/scripts/play_publish.py publish \
  ~/keys/play-service-account.json \
  build/app/outputs/bundle/release/app-release.aab \
  store/release-notes.txt --track internal
```

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
