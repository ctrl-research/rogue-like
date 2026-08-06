#!/usr/bin/env python3
"""Guard the one duplicated fact in the recolour pipeline.

The diver sprite's palette is authored in tools/gen_pixel_art.py and the
recolour shader has to know which of those tones mean "suit" and which mean
"helmet screen". Those key colours are declared in src/appearance.gd and passed
to the shader as uniforms, so the shader itself holds no hexes — but appearance
and the generator can still drift, and the failure mode is quiet: the shader
matches nothing, and divers silently render in stock brass no matter what
anyone picked.

Prints PALETTE_OK, or the mismatch and a non-zero exit.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "tools" / "gen_pixel_art.py"
APPEARANCE = ROOT / "src" / "appearance.gd"

# Which generator palette entry each Appearance key must equal.
EXPECTED = {
    "KEY_SUIT_LIT": "Y",
    "KEY_SUIT_DARK": "B",
    "KEY_SCREEN_LIT": "W",
    "KEY_SCREEN_DARK": "C",
}


def diver_palette(source: str) -> dict:
    """Pull the palette out of the DIVER dict without importing the generator."""
    start = source.index("DIVER = {")
    body = source[start : source.index("\n}", start)]
    palette = body[body.index('"palette"') :]
    return {k: v.lower() for k, v in re.findall(r'"(\w)":\s*"(#[0-9a-fA-F]{6})"', palette)}


def appearance_keys(source: str) -> dict:
    return {
        k: v.lower()
        for k, v in re.findall(r'const (KEY_\w+)\s*:=\s*"(#[0-9a-fA-F]{6})"', source)
    }


def main() -> int:
    palette = diver_palette(GEN.read_text())
    keys = appearance_keys(APPEARANCE.read_text())

    problems = []
    for const, entry in EXPECTED.items():
        if const not in keys:
            problems.append(f"{const} is missing from src/appearance.gd")
            continue
        if entry not in palette:
            problems.append(f"DIVER palette has no '{entry}' entry in {GEN.name}")
            continue
        if keys[const] != palette[entry]:
            problems.append(
                f"{const} is {keys[const]} but DIVER['{entry}'] is {palette[entry]}"
            )

    if problems:
        print("PALETTE_FAIL")
        for p in problems:
            print(f"  - {p}")
        print(
            "\nThe sprite palette and the recolour keys have drifted. Update "
            "src/appearance.gd to match tools/gen_pixel_art.py (or vice versa); "
            "otherwise the shader matches nothing and every diver renders stock."
        )
        return 1

    print(f"PALETTE_OK ({len(EXPECTED)} keys match {GEN.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
