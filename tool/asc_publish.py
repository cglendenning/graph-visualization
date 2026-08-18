#!/usr/bin/env python3
"""Fill in Perihelion Graph's App Store listing through the Connect API.

Everything here is metadata: categories, the version record, and the
localised text. Uploading a build is a separate step (altool), and creating
the app record itself is not possible through the API at all.

Usage:
    python3 tool/asc_publish.py inspect
    python3 tool/asc_publish.py categories
    python3 tool/asc_publish.py version 3.0.0
    python3 tool/asc_publish.py text
    python3 tool/asc_publish.py screenshots
"""

import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

KEY_ID = "MRKVCR3WF6"
ISSUER_ID = "78bfbe39-6c61-4296-b086-b36925bcc396"
KEY_PATH = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"
APP_ID = "6802487924"
BASE = "https://api.appstoreconnect.apple.com/v1"
ROOT = Path(__file__).resolve().parent.parent

SUBTITLE = "Traverse a knowledge graph"
KEYWORDS = ("wikipedia,wikidata,knowledge,graph,explore,discover,"
            "encyclopedia,serendipity,trivia,learn,browse")
PROMO = ("Every launch drops you somewhere new. Six connections radiate out; "
         "tap one and it becomes the centre. Keep going and you arrive "
         "somewhere you'd never have searched for.")
MARKETING_URL = "https://cglendenning.github.io/graph-visualization/"
PRIVACY_URL = "https://cglendenning.github.io/graph-visualization/privacy.html"

DESCRIPTION = """Perihelion is a different way to move through what we collectively know.

You start on a topic — any of the millions Wikipedia covers. Around it sit six things it is connected to: a person, a place, a work, an event, an idea. Tap one and it slides to the centre, and six new connections open around it.

There is no results page and no ranked list. There is only where you are and where you can go next, and the way back is always on screen.

Keep going and the interesting thing happens. Four or five hops in you are somewhere you could never have searched for, having arrived by a path you can still trace. A composer leads to a city, the city to a physicist, the physicist to an idea that turns up again somewhere you did not expect.

HOW IT WORKS

Nothing is bundled and nothing is invented. Every topic and every connection is read live from Wikidata, the structured database behind Wikipedia, released into the public domain. Article summaries come from Wikipedia itself, credited where they appear.

Connections are drawn at random from everything a topic actually records, favouring the ones widely enough known to recognise. Return to a topic later and you will be offered a different six.

WHAT IT DOES NOT DO

No account. No advertising. No analytics. Nothing about you is collected or stored — there is no server to send it to.

Perihelion needs an internet connection, because the graph is the whole of Wikidata rather than a copy in your pocket."""


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(), algorithm="ES256", headers={"kid": KEY_ID})


def call(method, path, body=None, raw=None, content_type=None, full=False):
    url = path if full else BASE + path
    data = raw if raw is not None else (
        json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            payload = resp.read().decode()
            return json.loads(payload) if payload.strip() else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            errs = json.loads(detail).get("errors", [])
            msg = "; ".join(
                f"{x.get('title')}: {x.get('detail', '')}" for x in errs[:3])
        except Exception:
            msg = detail[:400]
        raise SystemExit(f"  {method} {path} -> {e.code}\n  {msg}")


def inspect():
    app = call("GET", f"/apps/{APP_ID}")["data"]["attributes"]
    print(f"  app: {app['name']} ({app['bundleId']}) locale={app['primaryLocale']}")
    infos = call("GET", f"/apps/{APP_ID}/appInfos")["data"]
    for i in infos:
        print(f"  appInfo {i['id']} state={i['attributes'].get('appStoreState')}")
    vers = call("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10").get("data", [])
    for v in vers:
        a = v["attributes"]
        print(f"  version {v['id']} {a.get('versionString')} "
              f"state={a.get('appStoreState')} platform={a.get('platform')}")
    if not vers:
        print("  no version records yet")


def _primary_app_info():
    for i in call("GET", f"/apps/{APP_ID}/appInfos")["data"]:
        state = i["attributes"].get("appStoreState")
        if state not in ("READY_FOR_SALE",):
            return i["id"]
    return call("GET", f"/apps/{APP_ID}/appInfos")["data"][0]["id"]


def categories():
    info_id = _primary_app_info()
    body = {"data": {
        "type": "appInfos", "id": info_id,
        "relationships": {
            "primaryCategory": {
                "data": {"type": "appCategories", "id": "EDUCATION"}},
            "secondaryCategory": {
                "data": {"type": "appCategories", "id": "REFERENCE"}},
        }}}
    call("PATCH", f"/appInfos/{info_id}", body)
    print("  categories set: Education / Reference")


def version(version_string):
    existing = call("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10").get("data", [])
    for v in existing:
        if v["attributes"].get("versionString") == version_string:
            print(f"  version {version_string} already exists ({v['id']})")
            return v["id"]
    body = {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version_string,
                       "releaseType": "MANUAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}}
    vid = call("POST", "/appStoreVersions", body)["data"]["id"]
    print(f"  created version {version_string} ({vid})")
    return vid


def _current_version_id():
    vers = call("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10").get("data", [])
    if not vers:
        raise SystemExit("  no version record; run: version 3.0.0")
    return vers[0]["id"]


def text():
    vid = _current_version_id()
    locs = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
    attrs = {"description": DESCRIPTION, "keywords": KEYWORDS,
             "promotionalText": PROMO, "marketingUrl": MARKETING_URL,
             "supportUrl": MARKETING_URL}
    if loc:
        call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}",
             {"data": {"type": "appStoreVersionLocalizations",
                       "id": loc["id"], "attributes": attrs}})
        print("  version text updated (en-US)")
    else:
        attrs["locale"] = "en-US"
        call("POST", "/appStoreVersionLocalizations",
             {"data": {"type": "appStoreVersionLocalizations",
                       "attributes": attrs,
                       "relationships": {"appStoreVersion": {
                           "data": {"type": "appStoreVersions", "id": vid}}}}})
        print("  version text created (en-US)")

    # Subtitle and privacy policy live on the appInfo, not the version.
    info_id = _primary_app_info()
    ilocs = call("GET", f"/appInfos/{info_id}/appInfoLocalizations")["data"]
    iloc = next((l for l in ilocs if l["attributes"]["locale"] == "en-US"), None)
    iattrs = {"subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY_URL}
    if iloc:
        call("PATCH", f"/appInfoLocalizations/{iloc['id']}",
             {"data": {"type": "appInfoLocalizations", "id": iloc["id"],
                       "attributes": iattrs}})
        print("  subtitle and privacy url updated")
    else:
        iattrs["locale"] = "en-US"
        call("POST", "/appInfoLocalizations",
             {"data": {"type": "appInfoLocalizations", "attributes": iattrs,
                       "relationships": {"appInfo": {
                           "data": {"type": "appInfos", "id": info_id}}}}})
        print("  subtitle and privacy url created")


def screenshots():
    """Uploads the 6.9-inch set. Apple takes each file in reserved chunks."""
    vid = _current_version_id()
    locs = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    loc = next(l for l in locs if l["attributes"]["locale"] == "en-US")

    sets = call("GET",
                f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    display = "APP_IPHONE_67"
    sset = next((s for s in sets
                 if s["attributes"]["screenshotDisplayType"] == display), None)
    if sset is None:
        sset = call("POST", "/appScreenshotSets", {"data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations",
                         "id": loc["id"]}}}}})["data"]
        print(f"  created screenshot set {display}")

    folder = ROOT / "store" / "screenshots" / "ios-6.9"
    for path in sorted(folder.glob("*.png")):
        blob = path.read_bytes()
        created = call("POST", "/appScreenshots", {"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(blob)},
            "relationships": {"appScreenshotSet": {
                "data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]

        for op in created["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk,
                                         method=op["method"])
            for h in op["requestHeaders"]:
                req.add_header(h["name"], h["value"])
            urllib.request.urlopen(req, timeout=120).read()

        import hashlib
        call("PATCH", f"/appScreenshots/{created['id']}", {"data": {
            "type": "appScreenshots", "id": created["id"],
            "attributes": {"uploaded": True,
                           "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
        print(f"  uploaded {path.name}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "inspect"
    if cmd == "inspect":
        inspect()
    elif cmd == "categories":
        categories()
    elif cmd == "version":
        version(sys.argv[2] if len(sys.argv) > 2 else "3.0.0")
    elif cmd == "text":
        text()
    elif cmd == "screenshots":
        screenshots()
    else:
        raise SystemExit(__doc__)
