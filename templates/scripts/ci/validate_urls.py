#!/usr/bin/env python3
"""Checks that the URLs we ship actually resolve — PR check, no dependencies.

Every other check in this repo validates the SHAPE of a URL. Shape is not the
failure mode. `https://owner.github.io/repo/privacy` is a perfectly well-formed
URL and returns 404 until someone enables GitHub Pages and writes the page —
and PES scaffolds exactly that URL into both config.json and the store
metadata. An app can pass every check, push metadata to App Store Connect, and
only discover at submission that Apple rejects the listing because the privacy
URL is dead. Apple requires a working privacy URL; a 404 is a rejection.

Two sources, because both ship URLs and both are scaffolded with the same
GitHub Pages guess:
  - fastlane/metadata/<locale>.json  -> support_url, privacy_url, marketing_url
  - App/Resources/config.json        -> anything URL-shaped under "urls"

A 4xx/5xx is a hard failure: the server answered, and the answer was "no".
A connection error, DNS failure or timeout is reported as a warning instead —
CI runners lose the network often enough that failing the build on it would
train everyone to re-run checks, and a check people reflexively re-run is a
check that no longer means anything.

Placeholders ({{...}}) are skipped; validate_metadata already fails on those.
"""
import json
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
METADATA_DIR = ROOT / "fastlane" / "metadata"
CONFIG = ROOT / "App" / "Resources" / "config.json"

METADATA_URL_FIELDS = ("support_url", "privacy_url", "marketing_url")
TIMEOUT = 15
ATTEMPTS = 3
# Some hosts (GitHub Pages included) answer HEAD differently from GET, and a
# few reject HEAD outright, so a HEAD failure is retried as a GET before it
# counts against the URL.
USER_AGENT = "pes-validate-urls/1.0 (+https://github.com/ERbittuu/portfolio-engineering-standards)"


def collect_urls() -> dict[str, list[str]]:
    """Map each URL to the places it came from, so one report covers duplicates."""
    found: dict[str, list[str]] = {}

    def note(url: str, source: str) -> None:
        if not isinstance(url, str) or not url.strip():
            return
        if "{{" in url or "}}" in url:
            return  # unsubstituted placeholder — validate_metadata's job
        if not url.startswith(("http://", "https://")):
            return  # malformed — validate_metadata's job
        found.setdefault(url.strip(), []).append(source)

    if METADATA_DIR.is_dir():
        for path in sorted(METADATA_DIR.glob("*.json")):
            try:
                fields = json.loads(path.read_text())
            except (json.JSONDecodeError, OSError):
                continue  # validate_metadata reports malformed metadata
            if not isinstance(fields, dict):
                continue
            for field in METADATA_URL_FIELDS:
                note(fields.get(field), f"{path.name}:{field}")

    if CONFIG.is_file():
        try:
            config = json.loads(CONFIG.read_text())
        except (json.JSONDecodeError, OSError):
            config = {}
        # The key is "urls" in the config schema. Accepting "links" too is not
        # generosity — an earlier draft of this script read "links", found
        # nothing, and reported success, which is the exact failure this file
        # exists to prevent.
        for section in ("urls", "links"):
            block = config.get(section) if isinstance(config, dict) else None
            if isinstance(block, dict):
                for key, value in block.items():
                    note(value, f"config.json:{section}.{key}")

    return found


def check(url: str) -> tuple[str, str]:
    """Return (status, detail): status is "ok", "dead" or "unknown"."""
    last_network_error = ""
    context = ssl.create_default_context()

    for attempt in range(ATTEMPTS):
        for method in ("HEAD", "GET"):
            request = urllib.request.Request(url, method=method, headers={"User-Agent": USER_AGENT})
            try:
                with urllib.request.urlopen(request, timeout=TIMEOUT, context=context) as response:
                    return "ok", f"HTTP {response.status}"
            except urllib.error.HTTPError as e:
                if method == "HEAD" and e.code in (403, 405, 501):
                    continue  # host dislikes HEAD — try GET before judging
                return "dead", f"HTTP {e.code}"
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                last_network_error = str(getattr(e, "reason", e))
                break  # network problem, not a verdict on the URL — retry
        if attempt < ATTEMPTS - 1:
            continue

    return "unknown", last_network_error or "no response"


def main() -> int:
    urls = collect_urls()
    if not urls:
        print("No shippable URLs found to check.")
        return 0

    dead: list[str] = []
    unknown: list[str] = []

    for url, sources in sorted(urls.items()):
        status, detail = check(url)
        where = ", ".join(sources)
        if status == "ok":
            print(f"  ok       {url}  ({detail})")
        elif status == "dead":
            print(f"  DEAD     {url}  ({detail})  <- {where}")
            dead.append(f"{url} returned {detail} — referenced by {where}")
        else:
            print(f"  unknown  {url}  ({detail})  <- {where}")
            unknown.append(f"{url} could not be reached ({detail}) — referenced by {where}")

    for warning in unknown:
        print(f"::warning::{warning}")

    if dead:
        print("\nURL validation failed:")
        for problem in dead:
            print(f"  - {problem}")
        print(
            "\nApple requires a working privacy URL and rejects listings whose "
            "support or privacy page 404s. Publish the page (GitHub Pages needs "
            "enabling per repo) or point the field at a URL that exists."
        )
        return 1

    print(f"\nURL validation passed for {len(urls)} URL(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
