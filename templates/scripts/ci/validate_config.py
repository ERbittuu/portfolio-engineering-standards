#!/usr/bin/env python3
"""Validates App/Resources/config.json before merge.

This one file reaches every user of the app at once and cannot be rolled back
by them, so it gets the strictest check in the repo. In particular it refuses a
`minimumVersion` above the version currently live on the App Store — that
combination blocks 100% of users with no version available to update to.

Checks:
  - valid JSON, object at the root
  - required standard keys present
  - configVersion is a positive integer
  - version strings are dotted numerics
  - recommendedVersion is not below minimumVersion
  - minimumVersion is not above the version live on the App Store
  - no unknown top-level keys (typos silently do nothing otherwise)
"""
import json
import sys
import urllib.request
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[2] / "App/Resources/config.json"
ALLOWED_TOP_LEVEL = {
    "configVersion", "updatedAt", "update", "maintenance",
    "flags", "rating", "urls", "content", "crossPromo", "whatsNew", "app",
}
REQUIRED_TOP_LEVEL = {"configVersion", "update", "flags", "app"}


def is_version(value) -> bool:
    return isinstance(value, str) and value and all(p.isdigit() for p in value.split("."))


def version_tuple(value: str):
    return tuple(int(p) for p in value.split("."))


def live_app_store_version(bundle_id: str):
    """The version currently on the App Store, or None if not published yet."""
    url = f"https://itunes.apple.com/lookup?bundleId={bundle_id}"
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            payload = json.load(response)
    except Exception:
        return None
    results = payload.get("results") or []
    return results[0].get("version") if results else None


def main() -> int:
    if not CONFIG.is_file():
        print(f"error: {CONFIG} does not exist")
        return 1

    errors = []
    try:
        config = json.loads(CONFIG.read_text())
    except json.JSONDecodeError as exc:
        print(f"config.json is not valid JSON: {exc}")
        return 1

    if not isinstance(config, dict):
        print("config.json must be a JSON object")
        return 1

    for key in sorted(REQUIRED_TOP_LEVEL - set(config)):
        errors.append(f"missing required key '{key}'")
    for key in sorted(set(config) - ALLOWED_TOP_LEVEL):
        errors.append(f"unknown top-level key '{key}' — typo? it would be silently ignored")

    version = config.get("configVersion")
    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        errors.append("configVersion must be a positive integer")

    update = config.get("update") or {}
    minimum = update.get("minimumVersion")
    recommended = update.get("recommendedVersion")

    for label, value in (("minimumVersion", minimum), ("recommendedVersion", recommended)):
        if value is not None and not is_version(value):
            errors.append(f"update.{label} '{value}' is not a dotted numeric version")

    if is_version(minimum) and is_version(recommended):
        if version_tuple(recommended) < version_tuple(minimum):
            errors.append("update.recommendedVersion is below update.minimumVersion")

    # The one that prevents a total lockout.
    if is_version(minimum):
        bundle_id = sys.argv[1] if len(sys.argv) > 1 else None
        if bundle_id:
            live = live_app_store_version(bundle_id)
            if live and is_version(live) and version_tuple(minimum) > version_tuple(live):
                errors.append(
                    f"update.minimumVersion {minimum} is above the version live on the "
                    f"App Store ({live}) — every user would be blocked with no update available"
                )

    # whatsNew: {"2.5.0": {"en": ["line", ...]}}. A wrong shape here means the
    # release-notes screen silently shows nothing after an update.
    whats_new = config.get("whatsNew")
    if whats_new is not None:
        if not isinstance(whats_new, dict):
            errors.append("whatsNew must be an object keyed by version")
        else:
            for release, localized in whats_new.items():
                if not is_version(release):
                    errors.append(f"whatsNew key '{release}' is not a dotted numeric version")
                if not isinstance(localized, dict):
                    errors.append(f"whatsNew['{release}'] must be an object keyed by language")
                    continue
                for language, lines in localized.items():
                    if not isinstance(lines, list) or not all(isinstance(line, str) for line in lines):
                        errors.append(f"whatsNew['{release}']['{language}'] must be a list of strings")

    if errors:
        print("config.json validation failed:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(f"config.json valid (configVersion {version}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
