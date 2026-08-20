#!/usr/bin/env python3
"""Checks that the app uses SYSKit instead of re-implementing it — PR check.

SYSKit exists so five apps behave the same way and one fix reaches all of them.
That only holds while apps actually use it. Nothing stops someone reaching for
`UserDefaults.standard` or `URLSession` directly — it works, it is one line, and
the app quietly stops sharing the behaviour everything else depends on. By the
time that matters, the divergence is old and expensive.

So each rule below names something SYSKit already does, and fails the build when
app code does it another way. This is not style: every rule maps to a defect that
has already happened, or to behaviour other apps rely on being identical.

`sys-ok: <reason>` opts out where an app genuinely has to be different. Put it
on the line itself or anywhere in the comment block directly above it — a
justification worth reading rarely fits on the end of a line, and one squeezed
until it does is not a justification. The reason is required: an opt-out nobody
has to explain is a rule that quietly stops applying.

Only `App/Source/` is scanned. Vendored packages, tests and generated code are
not app code.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App" / "Source"

# (pattern, what to use instead, why it matters)
RULES: list[tuple[str, str, str]] = [
    (
        r"\bUserDefaults\s*\.\s*standard\b",
        "@SYSStored or SYSSettings",
        "reading defaults directly loses the typed key and the "
        "absent-vs-false distinction that keeps upgrades from resetting settings",
    ),
    (
        r"\bURLSession\s*\.\s*shared\b",
        "SYSNetwork",
        "SYSNetwork carries the ETag handling, retry policy and offline "
        "detection every app's config and content fetching depends on",
    ),
    (
        r"\bSKStoreReviewController\b",
        "SYSReview",
        "asking without recording spends all three of Apple's yearly review "
        "requests on one user",
    ),
    (
        r"https://[a-z0-9-]+\.web\.app",
        "SYSHosting",
        "the hosting URL is derived from PROJECT_ID; hardcoding it is how a "
        "release ends up pointing at another project's content",
    ),
    (
        r"\bAnalytics\s*\.\s*logEvent\b",
        "SYSAnalytics with an AnalyticsEvent case",
        "events sent outside the enum skip the CI limit checks, and Firebase "
        "drops what breaks its limits without erroring",
    ),
    (
        r"\bCrashlytics\s*\.\s*crashlytics\(\)",
        "SYSLogger",
        "reporting through SYSLogger keeps non-fatals consistent and keeps "
        "Firebase out of app code",
    ),
]

# An app's entry point should hand its launch to SYSKit rather than re-deriving
# the sequence. Checked separately because it is an absence, not a pattern.
ENTRY_POINT = re.compile(r"@main\s+struct\s+(\w+)\s*:\s*([^{]+)\{", re.MULTILINE)


def opted_out_above(lines: list[str], line_number: int) -> bool:
    """True when the comment block immediately above the line carries sys-ok."""
    index = line_number - 2   # zero-based, the line before this one
    while index >= 0:
        stripped = lines[index].strip()
        if not stripped.startswith("//"):
            return False
        if "sys-ok:" in stripped:
            return True
        index -= 1
    return False


def scan() -> list[str]:
    problems: list[str] = []

    if not SOURCE.is_dir():
        print(f"error: {SOURCE} does not exist")
        return ["missing App/Source"]

    entry_points: list[tuple[Path, str, str]] = []

    for path in sorted(SOURCE.rglob("*.swift")):
        text = path.read_text(errors="replace")
        rel = path.relative_to(ROOT)

        lines = text.splitlines()
        for line_number, line in enumerate(lines, start=1):
            if "sys-ok:" in line or opted_out_above(lines, line_number):
                continue
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for pattern, replacement, why in RULES:
                if re.search(pattern, line):
                    problems.append(
                        f"{rel}:{line_number}: use {replacement} — {why}\n"
                        f"    {stripped[:100]}"
                    )

        for match in ENTRY_POINT.finditer(text):
            entry_points.append((rel, match.group(1), match.group(2)))

    for rel, name, conformances in entry_points:
        if "SYSBootstrappedApp" not in conformances:
            problems.append(
                f"{rel}: {name} does not conform to SYSBootstrappedApp — the launch "
                "sequence, the retry path and the task that starts them are shared; "
                "an app that wires its own can forget the task and sit on its "
                "loading screen forever with nothing in the log"
            )

    return problems


def main() -> int:
    problems = scan()
    if problems:
        print("SYSKit adoption check failed:\n")
        for problem in problems:
            print(f"  - {problem}")
        print(
            "\nSYSKit exists so every app behaves the same way and one fix reaches\n"
            "all of them. Use the shared path, or mark the line with\n"
            "`sys-ok: <reason>` in a comment on it or directly above it, if this\n"
            "app genuinely has to differ."
        )
        return 1

    print("SYSKit adoption check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
