#!/usr/bin/env python3
"""Stages the complete Firebase Hosting site into _hosting/.

Run by CI (`cd Data && python3 build.py --clean`) before the Hosting deploy.
Every app needs this file, including apps that host nothing but config.json.

WHY THIS STAGES config.json TOO
-------------------------------
A Firebase Hosting deploy atomically replaces the WHOLE site: files absent from
the staged directory are DELETED from the live site. PES used to run two deploy
jobs against one site — one staging config.json, one staging data bundles — so
whichever deployed last silently removed the other's files. Verified on a
preview channel: staging both gave config.json 200 and manifest.json 200;
re-staging config.json alone left manifest.json returning 404.

There is now one staging step and one deploy, and this script produces the
entire site. If you add a new kind of hosted file, add it here. Do not add a
second job that deploys it.

{{ EDIT: the section marked below is where this app's hosted data is built.
   An app that hosts only config can delete it and ship this file as-is —
   manifest.json is optional and CI skips the data checks when it is absent. }}
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent
REPO = DATA_DIR.parent
APP_CONFIG = REPO / "App" / "Resources" / "config.json"
STAGE = REPO / "_hosting"


def stage_app_data() -> dict | None:
    """Build this app's hosted data into STAGE. Return a manifest dict, or None.

    {{ EDIT — replace the body with this app's data build.

    Whatever scheme you use, content-address the filenames (name-<sha8>.zip).
    A new file name for new content means an old install keeps resolving the
    URL it already knows, which still exists, while a new install fetches a URL
    it has never cached. That is what allows content to be added without an app
    update, and it is why firebase.json can mark those paths immutable.

    Build deterministically (sorted entries, fixed timestamps) so unchanged
    content keeps its hash and is not re-uploaded on every run. }}
    """
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clean", action="store_true", help="remove _hosting/ first")
    # pr.yml's data-ci job runs this with --clean --verbose. Accepting the flag
    # is part of the contract: argparse exits 2 on an unknown argument, so a
    # build.py without it fails the PR check with "unrecognized arguments"
    # rather than anything about the data.
    parser.add_argument("--verbose", action="store_true", help="list every staged file")
    args = parser.parse_args()

    if not APP_CONFIG.is_file():
        print(f"error: {APP_CONFIG} does not exist — the site must ship a config")
        return 1

    if args.clean and STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir(parents=True, exist_ok=True)

    manifest = stage_app_data()
    if manifest is not None:
        (STAGE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"Staged manifest.json with {len(manifest.get('items', []))} item(s)")
    else:
        print("No hosted data for this app — staging config only")

    # The app ships a copy of this file; Hosting serves the same bytes so the
    # bundled and served copies cannot drift.
    shutil.copyfile(APP_CONFIG, STAGE / "config.json")

    files = sorted(f for f in STAGE.rglob("*") if f.is_file())
    if args.verbose:
        for f in files:
            print(f"  {f.relative_to(STAGE)}  {f.stat().st_size:,} B")
    print(f"Site root: {STAGE} ({len(files)} file(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
