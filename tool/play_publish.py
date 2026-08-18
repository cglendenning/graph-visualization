#!/usr/bin/env python3
"""Publish Perihelion Graph to Google Play.

Uploads the signed bundle to a track and sets the whole store listing:
text, icon, feature graphic and screenshots. The declarations Play requires
(content rating, data safety, target audience) have no API and stay manual.

Usage:
    python3 tool/play_publish.py upload   [--track internal]
    python3 tool/play_publish.py listing
    python3 tool/play_publish.py status
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

SA_PATH = Path.home() / "keys" / "play-service-account.json"
PKG = "com.craigglendenning.perihelion"
ROOT = Path(__file__).resolve().parent.parent
API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"

TITLE = "Perihelion Graph"
SHORT = "Follow the connections between everything Wikipedia knows."
FULL = """Perihelion is a different way to move through what we collectively know.

You start on a topic - any of the millions Wikipedia covers. Around it sit six things it is connected to: a person, a place, a work, an event, an idea. Tap one and it slides to the centre, and six new connections open around it.

There is no results page and no ranked list. There is only where you are and where you can go next, and the way back is always on screen.

Keep going and the interesting thing happens. Four or five hops in you are somewhere you could never have searched for, having arrived by a path you can still trace. A composer leads to a city, the city to a physicist, the physicist to an idea that turns up again somewhere you did not expect.

HOW IT WORKS

Nothing is bundled and nothing is invented. Every topic and every connection is read live from Wikidata, the structured database behind Wikipedia, released into the public domain. Article summaries come from Wikipedia itself, credited where they appear.

Connections are drawn at random from everything a topic actually records, favouring the ones widely enough known to recognise. Return to a topic later and you will be offered a different six.

WHAT IT DOES NOT DO

No account. No advertising. No analytics. Nothing about you is collected or stored - there is no server to send it to.

Perihelion needs an internet connection, because the graph is the whole of Wikidata rather than a copy in your pocket."""

RELEASE_NOTES = ("First release. Explore Wikipedia as a graph: a topic at the centre, "
                 "six connections around it, tap to travel.")


def token():
    sa = json.load(open(SA_PATH))
    now = int(time.time())
    assertion = jwt.encode(
        {"iss": sa["client_email"],
         "scope": "https://www.googleapis.com/auth/androidpublisher",
         "aud": sa["token_uri"], "iat": now, "exp": now + 3600},
        sa["private_key"], algorithm="RS256")
    data = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion}).encode()
    req = urllib.request.Request(sa["token_uri"], data=data)
    return json.loads(urllib.request.urlopen(req, timeout=30).read())["access_token"]


def call(method, url, tok, body=None, raw=None, content_type=None):
    data = raw if raw is not None else (
        json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {tok}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            payload = r.read().decode()
            return json.loads(payload) if payload.strip() else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            msg = json.loads(detail)["error"]["message"]
        except Exception:
            msg = detail[:400]
        raise SystemExit(f"  {method} {url.split('/v3')[-1][:70]} -> {e.code}\n  {msg}")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    track = "internal"
    if "--track" in sys.argv:
        track = sys.argv[sys.argv.index("--track") + 1]
    tok = token()

    if cmd == "status":
        e = call("POST", f"{API}/applications/{PKG}/edits", tok, body={})
        tr = call("GET", f"{API}/applications/{PKG}/edits/{e['id']}/tracks", tok)
        for t in tr.get("tracks", []):
            rels = t.get("releases", [])
            desc = "; ".join(
                f"{r.get('status')} {r.get('versionCodes')}" for r in rels) or "empty"
            print(f"  track {t['track']:12s} {desc}")
        li = call("GET", f"{API}/applications/{PKG}/edits/{e['id']}/listings", tok)
        for l in li.get("listings", []):
            print(f"  listing {l['language']}: title={l.get('title')!r} "
                  f"short={len(l.get('shortDescription') or '')}ch "
                  f"full={len(l.get('fullDescription') or '')}ch")
        call("DELETE", f"{API}/applications/{PKG}/edits/{e['id']}", tok)
        return

    e = call("POST", f"{API}/applications/{PKG}/edits", tok, body={})
    eid = e["id"]
    print(f"  edit {eid}")

    if cmd == "upload":
        aab = ROOT / "build/app/outputs/bundle/release/app-release.aab"
        blob = aab.read_bytes()
        print(f"  uploading {aab.name} ({len(blob)//1024//1024} MB) ...")
        b = call("POST",
                 f"{UPLOAD}/applications/{PKG}/edits/{eid}/bundles?uploadType=media",
                 tok, raw=blob, content_type="application/octet-stream")
        vc = b["versionCode"]
        print(f"  uploaded versionCode {vc}")
        call("PUT", f"{API}/applications/{PKG}/edits/{eid}/tracks/{track}", tok, body={
            "track": track,
            "releases": [{"status": "completed", "versionCodes": [str(vc)],
                          "releaseNotes": [{"language": "en-US",
                                            "text": RELEASE_NOTES}]}]})
        print(f"  assigned to track '{track}'")

    if cmd in ("listing", "upload"):
        call("PUT", f"{API}/applications/{PKG}/edits/{eid}/listings/en-US", tok, body={
            "language": "en-US", "title": TITLE,
            "shortDescription": SHORT, "fullDescription": FULL})
        print("  listing text set")

        images = {
            "icon": [ROOT / "store/icon-512.png"],
            "featureGraphic": [ROOT / "store/feature-graphic.png"],
            "phoneScreenshots": sorted((ROOT / "store/screenshots/ios-6.9").glob("*.png")),
        }
        for kind, paths in images.items():
            call("DELETE",
                 f"{API}/applications/{PKG}/edits/{eid}/listings/en-US/{kind}", tok)
            for p in paths:
                call("POST",
                     f"{UPLOAD}/applications/{PKG}/edits/{eid}/listings/en-US/{kind}?uploadType=media",
                     tok, raw=p.read_bytes(), content_type="image/png")
                print(f"  {kind}: {p.name}")

    call("POST", f"{API}/applications/{PKG}/edits/{eid}:commit", tok, body={})
    print("  edit committed")


if __name__ == "__main__":
    main()
