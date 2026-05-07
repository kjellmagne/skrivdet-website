#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STRINGS_FILE = ROOT / "nb.lproj" / "Localizable.strings"
IGNORE_KEYS = {"•", r"• \(item)"}

PATTERNS = [
    re.compile(r'AppLocalizer\.text\("((?:\\.|[^"])*)"\)'),
    re.compile(r'AppLocalizer\.format\("((?:\\.|[^"])*)"'),
    re.compile(r'localized\("((?:\\.|[^"])*)"\s*,\s*language:'),
    re.compile(
        r'(?:Text|Label|Button|Section|Picker|LabeledContent|Toggle|TextField|SecureField|navigationTitle|NavigationTitle|confirmationDialog|alert|accessibilityLabel|accessibilityHint)\(\s*"((?:\\.|[^"])*)"'
    ),
    re.compile(r'searchable\(text: \$[^,]+, prompt: "((?:\\.|[^"])*)"'),
]


def decode_escaped(value: str) -> str:
    return (
        value
        .replace(r"\\", "\\")
        .replace(r"\"", "\"")
        .replace(r"\n", "\n")
        .replace(r"\t", "\t")
    )


def load_localized_keys() -> set[str]:
    keys: set[str] = set()
    key_pattern = re.compile(r'"((?:\\.|[^"])*)"\s*=\s*"')

    for line in STRINGS_FILE.read_text().splitlines():
        match = key_pattern.match(line)
        if match:
            keys.add(decode_escaped(match.group(1)))

    return keys


def collect_missing_keys(localized_keys: set[str]) -> dict[str, list[str]]:
    missing: dict[str, list[str]] = {}

    for path in ROOT.rglob("*.swift"):
        text = path.read_text()
        for lineno, line in enumerate(text.splitlines(), 1):
            for pattern in PATTERNS:
                for match in pattern.finditer(line):
                    key = decode_escaped(match.group(1))
                    if key in localized_keys or key in IGNORE_KEYS or key.startswith("•"):
                        continue
                    missing.setdefault(key, []).append(f"{path.relative_to(ROOT)}:{lineno}")

    return dict(sorted(missing.items(), key=lambda item: item[0].lower()))


def main() -> int:
    missing = collect_missing_keys(load_localized_keys())

    if not missing:
        print("No missing Norwegian localization keys found.")
        return 0

    print("Missing Norwegian localization keys:\n")
    for key, locations in missing.items():
        print(key)
        for location in locations:
            print(f"  {location}")
        print()

    return 1


if __name__ == "__main__":
    sys.exit(main())
