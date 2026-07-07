#!/usr/bin/env python3
"""Validates fastlane/screenshots/ before merge — PR check, no dependencies.

{{ EDIT STORE_LOCALES and REQUIRED below for this app — the values here
   are just an example (a trilingual app supporting one 6.9" iPhone size
   and one 13" iPad size). Get exact required pixel dimensions from
   App Store Connect's screenshot specs, they change as new device
   classes ship. }}

For every locale folder that's an actual App Store Connect store locale
(must match fastlane/Deliverfile's languages() — app languages and store
languages are frequently different lists, check before assuming):
  - exactly N screenshots per required device size, at the exact pixel
    dimensions Apple requires
  - no corrupt / zero-byte files, no unexpected extra files

Locale folders outside the store-locale list are skipped (kept for
in-app/reference use if the app supports more languages than the store
listing does).
"""
import struct
import sys
from pathlib import Path

STORE_LOCALES = {"en-US"}  # must match Deliverfile's languages()
SCREENSHOTS_DIR = Path(__file__).resolve().parents[2] / "fastlane" / "screenshots"

REQUIRED = {
    **{f"iPhone-6-9-{i:02d}.png": (1290, 2796) for i in range(1, 7)},
    "iPad-13-01.png": (2064, 2752),
}


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        header = f.read(33)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def main() -> int:
    if not SCREENSHOTS_DIR.is_dir():
        print(f"error: {SCREENSHOTS_DIR} does not exist")
        return 1

    errors: list[str] = []
    locale_dirs = sorted(p for p in SCREENSHOTS_DIR.iterdir() if p.is_dir())
    checked = 0

    for locale_dir in locale_dirs:
        locale = locale_dir.name
        if locale not in STORE_LOCALES:
            print(f"skipping {locale}/ — not a store locale ({', '.join(sorted(STORE_LOCALES))})")
            continue
        checked += 1

        for filename, expected_size in REQUIRED.items():
            path = locale_dir / filename
            if not path.is_file():
                errors.append(f"{locale}: missing {filename}")
                continue
            if path.stat().st_size == 0:
                errors.append(f"{locale}: {filename} is zero bytes")
                continue
            try:
                actual_size = png_dimensions(path)
            except (ValueError, struct.error) as e:
                errors.append(f"{locale}: {filename} is not a valid PNG ({e})")
                continue
            if actual_size != expected_size:
                errors.append(
                    f"{locale}: {filename} is {actual_size[0]}x{actual_size[1]}, "
                    f"App Store requires exactly {expected_size[0]}x{expected_size[1]}"
                )

        extra = {p.name for p in locale_dir.glob("*.png")} - set(REQUIRED)
        if extra:
            errors.append(f"{locale}: unexpected file(s) not part of the required set: {', '.join(sorted(extra))}")

    if errors:
        print("Screenshot validation failed:")
        for e in errors:
            print(f"  - {e}")
        return 1

    print(f"Screenshot validation passed for {checked} locale(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
