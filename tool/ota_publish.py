#!/usr/bin/env python3
"""Publish the development IPA to the OTA page.

Every build is published under a filename carrying its version, because the
OTA install is only as reliable as the least cooperative cache between the
phone and GitHub. Reusing `perihelion.ipa` meant Safari, iOS and the Pages
CDN could each hand back an older copy, which shows up as an install that
sits on "Waiting..." forever. A URL that has never been requested before
cannot be served stale.

Old builds are pruned so the working tree does not accumulate 8 MB files.

Usage:
    python3 tool/ota_publish.py            # publish build/ios/ipa/perihelion.ipa
    python3 tool/ota_publish.py --keep 5   # retain more previous builds
"""

import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
BUILDS = DOCS / "builds"
SOURCE = ROOT / "build/ios/ipa/perihelion.ipa"
BASE = "https://cglendenning.github.io/graph-visualization"
KEEP_DEFAULT = 3


def ipa_version(path):
    """Reads the version out of the IPA rather than trusting pubspec.

    They can disagree when a build fails part way, and shipping a manifest
    that disagrees with its payload is exactly the kind of mismatch that
    makes an install hang.
    """
    with zipfile.ZipFile(path) as z:
        name = next(n for n in z.namelist()
                    if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n))
        info = plistlib.loads(z.read(name))
    return (info["CFBundleShortVersionString"], info["CFBundleVersion"],
            info["CFBundleIdentifier"])


def manifest(bundle_id, short, build, ipa_url):
    return {
        "items": [{
            "assets": [
                {"kind": "software-package", "url": ipa_url},
                {"kind": "display-image", "url": f"{BASE}/icon-57.png"},
                {"kind": "full-size-image", "url": f"{BASE}/icon-512.png"},
            ],
            "metadata": {
                "bundle-identifier": bundle_id,
                "bundle-version": f"{short}.{build}",
                "kind": "software",
                "platform-identifier": "com.apple.platform.iphoneos",
                "title": "Perihelion",
            },
        }]
    }


def main():
    keep = KEEP_DEFAULT
    if "--keep" in sys.argv:
        keep = int(sys.argv[sys.argv.index("--keep") + 1])
    if not SOURCE.exists():
        raise SystemExit(f"  no IPA at {SOURCE}; run flutter build ipa first")

    short, build, bundle_id = ipa_version(SOURCE)
    stamp = f"{short}-{build}"
    BUILDS.mkdir(parents=True, exist_ok=True)

    ipa_name = f"perihelion-{stamp}.ipa"
    man_name = f"manifest-{stamp}.plist"
    shutil.copy2(SOURCE, BUILDS / ipa_name)
    ipa_url = f"{BASE}/builds/{ipa_name}"
    (BUILDS / man_name).write_bytes(
        plistlib.dumps(manifest(bundle_id, short, build, ipa_url)))
    print(f"  {ipa_name}  ({(BUILDS / ipa_name).stat().st_size // 1024} KB)")
    print(f"  {man_name}")

    install = (f"itms-services://?action=download-manifest&amp;"
               f"url={BASE}/builds/{man_name}")
    page = DOCS / "index.html"
    html = page.read_text()
    html = re.sub(r'href="itms-services://[^"]*"', f'href="{install}"', html)
    html = re.sub(r"<dt>Version</dt><dd>[^<]*</dd>",
                  f"<dt>Version</dt><dd>{short} ({build})</dd>", html)
    page.write_text(html)
    print(f"  index.html -> {short} ({build})")

    # Prune, newest first by mtime so a rebuild of the same version survives.
    for pattern in ("perihelion-*.ipa", "manifest-*.plist"):
        old = sorted(BUILDS.glob(pattern),
                     key=lambda p: p.stat().st_mtime, reverse=True)[keep:]
        for path in old:
            path.unlink()
            print(f"  pruned {path.name}")

    # The old fixed-name payload is what made stale caches possible.
    for stale in (DOCS / "perihelion.ipa", DOCS / "manifest.plist"):
        if stale.exists():
            stale.unlink()
            print(f"  removed {stale.name} (fixed names invite stale caches)")

    subprocess.run(["plutil", "-lint", str(BUILDS / man_name)], check=True)
    print(f"\n  install: {BASE}/")


if __name__ == "__main__":
    main()
