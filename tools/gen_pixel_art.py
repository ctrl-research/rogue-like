#!/usr/bin/env python3
"""Generate placeholder pixel-art sprites as PNGs (stdlib only, no PIL).

Sprites are defined as ASCII grids with a per-sprite palette. Rerun after
editing a grid:  python3 tools/gen_pixel_art.py
Output goes to assets/sprites/.
"""
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")


def write_png(path: str, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    height = len(pixels)
    width = len(pixels[0])
    raw = b""
    for row in pixels:
        raw += b"\x00"  # filter type 0 (None)
        for r, g, b, a in row:
            raw += struct.pack("4B", r, g, b, a)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data))
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # RGBA8
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def hex_rgba(s: str) -> tuple[int, int, int, int]:
    s = s.lstrip("#")
    r, g, b = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
    a = int(s[6:8], 16) if len(s) == 8 else 255
    return (r, g, b, a)


def grid_to_pixels(grid: list[str], palette: dict[str, str]):
    return [
        [hex_rgba(palette[ch]) if ch in palette else (0, 0, 0, 0) for ch in row]
        for row in grid
    ]


TRANSPARENT = "."

# 16x16 diver: yellow-brass suit, cyan visor, orange tank
DIVER = {
    "grid": [
        "................",
        ".....YYYYYY.....",
        "....YYYYYYYY....",
        "....YBBBBBBY....",
        "....YBCCCCBY....",
        "....YBCCWCBY....",
        "....YBBBBBBY....",
        "...YYYYYYYYYY...",
        "..OYYYYYYYYYYO..",
        "..OYYYYYYYYYYO..",
        "..O.YYYYYYYY.O..",
        "....YYY..YYY....",
        "....YYY..YYY....",
        "....YYY..YYY....",
        "....DDD..DDD....",
        "................",
    ],
    "palette": {
        "Y": "#d9a521",
        "B": "#8a6508",
        "C": "#0e3a52",
        "W": "#9fe8ff",
        "O": "#b04a1e",
        "D": "#5e4a10",
    },
}

# 16x16 barbfish: fast teal swarmer with red fins
BARBFISH = {
    "grid": [
        "................",
        "................",
        "......TT........",
        ".....TTTT..R....",
        "..R.TTTTTT.RR...",
        ".RR.TTWTTTTTRR..",
        ".RRTTTWTTTTTTR..",
        "..TTTTTTTTTTTT..",
        "..TTTTTTTTTTTT..",
        ".RRTTTTTTTTTTR..",
        ".RR.TTTTTTTTRR..",
        "..R.TTTTTT.RR...",
        ".....TTTT..R....",
        "......TT........",
        "................",
        "................",
    ],
    "palette": {
        "T": "#2e8f86",
        "W": "#e8f6f2",
        "R": "#c23b3b",
    },
}

# 16x16 angler brute: heavy purple tank with lure
BRUTE = {
    "grid": [
        "......G.........",
        "......G.........",
        ".....GG.........",
        "....PPPPPPPP....",
        "...PPPPPPPPPP...",
        "..PPWWPPPPPPPP..",
        "..PPWWPPPPPPPPP.",
        ".PPPPPPPPPPPPPP.",
        ".PPKKKKKKKKKPPP.",
        ".PPPPPPPPPPPPPP.",
        "..PPPPPPPPPPPPP.",
        "..PPPPPPPPPPPP..",
        "...PPP.PPP.PP...",
        "...PP...PP......",
        "................",
        "................",
    ],
    "palette": {
        "P": "#5a3070",
        "W": "#f2e14c",
        "K": "#d8d8e8",
        "G": "#8ef7d3",
    },
}

# 12x4 harpoon bolt (points right)
HARPOON = {
    "grid": [
        "..SSSSSSSSW.",
        "BBSSSSSSSWWW",
        "..SSSSSSSSW.",
        "............",
    ],
    "palette": {
        "S": "#b8c4cc",
        "W": "#eef4f6",
        "B": "#6a4a20",
    },
}

# 8x8 biomass gem (XP pickup)
GEM = {
    "grid": [
        "...CC...",
        "..CCCC..",
        ".CCWWCC.",
        "CCWWWWCC",
        "CCWWWWCC",
        ".CCWWCC.",
        "..CCCC..",
        "...CC...",
    ],
    "palette": {
        "C": "#25c9a5",
        "W": "#b4ffe9",
    },
}

# 16x16 salvage crate
CRATE = {
    "grid": [
        "................",
        "..GGGGGGGGGGGG..",
        ".GBBBBBBBBBBBBG.",
        ".GBWWBBBBBBWWBG.",
        ".GBBBBBBBBBBBBG.",
        ".GGGGGGGGGGGGGG.",
        ".GBBBBBBBBBBBBG.",
        ".GBBBGGGGGGBBBG.",
        ".GBBBGYYYYGBBBG.",
        ".GBBBGYYYYGBBBG.",
        ".GBBBGGGGGGBBBG.",
        ".GBBBBBBBBBBBBG.",
        ".GGGGGGGGGGGGGG.",
        ".GBBBBBBBBBBBBG.",
        "..GGGGGGGGGGGG..",
        "................",
    ],
    "palette": {
        "G": "#7a5a28",
        "B": "#4a3418",
        "W": "#b8c4cc",
        "Y": "#e8c832",
    },
}

# 24x24 dive bell (extraction)
BELL = {
    "grid": [
        "........BBBBBBBB........",
        "......BBBBBBBBBBBB......",
        ".....BBGGGGGGGGGGBB.....",
        "....BBGGGGGGGGGGGGBB....",
        "...BBGGGGGGGGGGGGGGBB...",
        "...BGGGGWWWWWWGGGGGGB...",
        "..BBGGGWWCCCCWWGGGGGBB..",
        "..BGGGGWCCCCCCWGGGGGGB..",
        "..BGGGGWCCCCCCWGGGGGGB..",
        "..BGGGGWWCCCCWWGGGGGGB..",
        "..BGGGGGWWWWWWGGGGGGGB..",
        "..BGGGGGGGGGGGGGGGGGGB..",
        "..BBGGGGGGGGGGGGGGGGBB..",
        "...BGGGGGGGGGGGGGGGGB...",
        "...BBBBBBBBBBBBBBBBBB...",
        "...BGGB..........BGGB...",
        "...BGGB..........BGGB...",
        "...BBBB..........BBBB...",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
    ],
    "palette": {
        "B": "#8a6508",
        "G": "#c9a227",
        "W": "#6a5210",
        "C": "#9fe8ff",
    },
}

SPRITES = {
    "diver.png": DIVER,
    "barbfish.png": BARBFISH,
    "brute.png": BRUTE,
    "harpoon.png": HARPOON,
    "gem.png": GEM,
    "crate.png": CRATE,
    "bell.png": BELL,
}


def gen_floor() -> list[list[tuple[int, int, int, int]]]:
    """32x32 seabed tile: dark blue-green with deterministic speckles."""
    base = hex_rgba("#0a1c2b")
    dark = hex_rgba("#081624")
    speck = hex_rgba("#14324a")
    algae = hex_rgba("#0f2e33")
    px = [[base for _ in range(32)] for _ in range(32)]
    # Deterministic pseudo-random speckling (no RNG so output is reproducible).
    for y in range(32):
        for x in range(32):
            h = (x * 31 + y * 17) % 97
            if h < 6:
                px[y][x] = speck
            elif h < 12:
                px[y][x] = dark
            elif h in (40, 41):
                px[y][x] = algae
    return px


def gen_light(size: int = 128) -> list[list[tuple[int, int, int, int]]]:
    """Radial white gradient for PointLight2D lamp texture."""
    c = (size - 1) / 2.0
    px = []
    for y in range(size):
        row = []
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / c
            a = max(0.0, 1.0 - d)
            a = a * a  # quadratic falloff, softer edge
            row.append((255, 245, 220, int(a * 255)))
        px.append(row)
    return px


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, spec in SPRITES.items():
        write_png(
            os.path.join(OUT_DIR, name),
            grid_to_pixels(spec["grid"], spec["palette"]),
        )
    write_png(os.path.join(OUT_DIR, "floor.png"), gen_floor())
    write_png(os.path.join(OUT_DIR, "light.png"), gen_light())
    print(f"Wrote {len(SPRITES) + 2} sprites to {os.path.normpath(OUT_DIR)}")


if __name__ == "__main__":
    main()
