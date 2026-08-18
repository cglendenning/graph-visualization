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

## Apple — SUBMITTED

Version 3.0.0 (build 20) went to review on 17 August 2026. State:
`WAITING_FOR_REVIEW`, submission `d4b1cc4e`.

Everything below was done through the API and does not need repeating for a
resubmission — only a new build and release notes would.

| | |
|---|---|
| App id | `6802487924` "Perihelion Graph" |
| Bundle id | `com.craigglendenning.perihelion` (`CL9WD6DKTD`) |
| Signing profile | "Perihelion Graph App Store", API-created against cert `Z58395TNCT` |
| Age rating | 12+ |
| Price | Free |
| Device family | iPhone only |

### If review comes back rejected

The likeliest objection is guideline 1.2 or 4.2: the app shows live,
uncurated encyclopedia content, and reviewers sometimes ask for filtering or
reporting controls on anything that displays open web content. The defence
is that the app displays a licensed third-party encyclopedia rather than
user submissions, has no way for users to post anything, and links to the
source for every article. If that comes up, say so plainly and offer to add
a report-content link rather than arguing the guideline.

## TestFlight — public link

A textable URL, no tester emails to collect, capped at 10,000 people:

**https://testflight.apple.com/join/CX6NWHxc**

Set up by `python3 tool/asc_publish.py testflight`, which is idempotent —
re-run it after uploading a new build and it attaches the build, refreshes
the notes and resubmits if needed.

The link is live but only starts installing once **Beta App Review** passes
(submitted 18 August 2026, `WAITING_FOR_REVIEW`). That review is separate
from and much lighter than App Store review — usually under a day. Until it
clears, the page loads and says the build is not yet available.

External testing needed four things Apple will not let you skip, all now set
through the API: the beta app description, a feedback email, the review
contact, and per-build "what to test" notes.

Internal testers (App Store Connect users on the account) can install
immediately without any of the above, but that path caps at 100 people and
still needs each person added by Apple ID — which is what the public link
exists to avoid.

## Apple — historical: what was left

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

## Google Play — ROLLED OUT, IN REVIEW

Version code 19 is a **completed release on production** as of 18 August
2026. The App content declarations were answered in the console and the app
has left draft state, confirmed by staging a live production release and
validating it without the draft-app refusal.

The store page still returns 404, so Google's review of the first release is
outstanding. New apps typically take a few days. Nothing further is needed
from either side — it goes live when review passes.

| | |
|---|---|
| Package | `com.craigglendenning.perihelion` |
| Service account | `perihelion-publisher@goal-executor.iam.gserviceaccount.com` |
| Key | `~/keys/play-service-account.json` (chmod 600, outside the repo) |
| Cloud project | `goal-executor` |
| Script | `tool/play_publish.py` |
| Contact | `c_glendenning@yahoo.com`, GitHub Pages URL |

```bash
python3 tool/play_publish.py upload --track internal        # bundle + listing
python3 tool/play_publish.py listing                        # listing only
python3 tool/play_publish.py status                         # what is live
python3 tool/play_publish.py promote --track production     # after first publish
```

### The permission trap

Granting the service account app-level permissions was not enough, and the
failure was silent in a confusing way: the account could open an edit, stage
any change, and commit an *empty* edit, but committing a listing change
returned a bare `403 The caller does not have permission`. "Manage store
presence" showed as ticked in the app-level dialog the whole time. Only
granting **Admin** on the *Account permissions* tab made listing commits
work. If a 403 reappears, isolate it the same way — commit an empty edit,
then a listing-only edit — rather than guessing at checkboxes.

### Verified complete through the API

Checked directly, not assumed:

| | |
|---|---|
| Listing text | title, 58-char short, 1459-char full |
| Graphics | icon 1, feature graphic 1, phone screenshots 4 |
| Contact | email and website set |
| Countries | 176 selected, plus rest-of-world |
| Default language | en-US |
| Bundle | versionCode 19, draft release on production |

Tablet screenshots are absent (0 seven-inch, 0 ten-inch). Play warns about
this but does not block publication.

### What cannot be verified from here

- **Nothing in the Android Publisher API touches the App content
  declarations.** The v3 discovery document lists 145 methods, 45 of them
  GET, and none reads or writes privacy policy, app access, ads, content
  rating, target audience, data safety, advertising ID, or the
  news/government/financial/health questions. That form is console-only.
  This was enumerated from the discovery document, so it is not a matter of
  having missed an endpoint.
- **`edits:validate` cannot stand in for them.** It returns `Only releases
  with status draft may be created on draft app` for a fully staged live
  release regardless, because an app cannot leave draft state through the
  API at all. **The first rollout must be done in the console.** Every
  release after that can be scripted.

---|---|
| Package | `com.craigglendenning.perihelion` |
| Service account | `perihelion-publisher@goal-executor.iam.gserviceaccount.com` |
| Key | `~/keys/play-service-account.json` (chmod 600, outside the repo) |
| Cloud project | `goal-executor` |
| Script | `tool/play_publish.py` |

Version 19 is also **staged as a draft on Open testing** (API track name
`beta`). It cannot go live yet: a Play app stays a "draft app" until it has
been published once, and draft apps accept live releases on the internal
track only. Answer the App content declarations below, then release it from
the console and the opt-in link becomes:

**https://play.google.com/apps/testing/com.craigglendenning.perihelion**

Production is still a separate decision and has not been touched.

```bash
python3 tool/play_publish.py upload --track internal   # bundle + listing
python3 tool/play_publish.py listing                   # listing only
python3 tool/play_publish.py status                    # what is live
python3 tool/play_publish.py promote --track beta      # open testing
```

### The permission trap, for next time

Granting the service account app-level permissions was not enough, and the
failure was silent in a confusing way: the account could open an edit, stage
any change, and commit an *empty* edit, but committing a listing change
returned a bare `403 The caller does not have permission`. "Manage store
presence" showed as ticked in the app-level dialog the whole time. Only
granting **Admin** on the *Account permissions* tab made listing commits
work. If a 403 reappears, isolate it the same way — commit an empty edit,
then a listing-only edit — rather than guessing at checkboxes.

### Verified complete through the API

Checked directly, not assumed:

| | |
|---|---|
| Listing text | title, 58-char short, 1459-char full |
| Graphics | icon 1, feature graphic 1, phone screenshots 4 |
| Contact | email and website set |
| Countries | 176 selected, plus rest-of-world |
| Default language | en-US |
| Bundle | versionCode 19, draft release on production |

Tablet screenshots are absent (0 seven-inch, 0 ten-inch). Play warns about
this but does not block publication.

### What cannot be verified from here

Two limits worth knowing before trying to check Play state by script:

- **Nothing in the Android Publisher API reads back the App content
  declarations.** Content rating, data safety and target audience are
  write-only through the console. There is no way to confirm them
  programmatically — the Publishing overview page is the only source of
  truth.
- **`edits:validate` cannot tell you whether they are done.** It returns
  `Only releases with status draft may be created on draft app` for a fully
  staged live release regardless, because an app cannot leave draft state
  through the API at all. **The first rollout has to be done in the
  console.** After that, releases can be pushed by script.

Store contact email and website were both empty and are now set
(`c_glendenning@yahoo.com`, the GitHub Pages URL). Play requires a contact
email on the listing, so that alone would have blocked the first rollout.

### Declarations still owed (no API exists for any of them)

In Play Console → Perihelion Graph → **App content**:

1. **Privacy policy** — https://cglendenning.github.io/graph-visualization/privacy.html
2. **App access** — all functionality available without restrictions
3. **Ads** — no
4. **Content rating** — IARC questionnaire, category Reference; declare live
   web content the developer does not curate. Expect Teen / PEGI 12.
5. **Target audience** — 13+
6. **Data safety** — no collection, no sharing, encrypted in transit, no
   deletion mechanism because nothing is retained
7. **Government / financial / health** — no to all

Then Internal testing → Testers to add an email and install on a device.

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
