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

# 8x8 salvage nugget (dropped when ore rock is dug out)
NUGGET = {
    "grid": [
        "........",
        "..GGY...",
        ".GYYYG..",
        "GGYWWYG.",
        "GYWWYYGG",
        ".GYYYGG.",
        "..GGGG..",
        "........",
    ],
    "palette": {
        "G": "#8a6420",
        "Y": "#d9a33c",
        "W": "#f2cf6e",
    },
}

# 16x16 upgrade console (sub interior): terminal with screen + keys
CONSOLE = {
    "grid": [
        "................",
        "..GGGGGGGGGGGG..",
        ".GSSSSSSSSSSSSG.",
        ".GSCCCCCCCCCCSG.",
        ".GSCWWCCCCWCCSG.",
        ".GSCCCCWCCCCCSG.",
        ".GSCCCCCCCCCCSG.",
        ".GSSSSSSSSSSSSG.",
        ".GGGGGGGGGGGGGG.",
        ".GSYSYSYSYSYSSG.",
        ".GSSSSSSSSSSSSG.",
        ".GGGGGGGGGGGGGG.",
        "...GG......GG...",
        "...GG......GG...",
        "................",
        "................",
    ],
    "palette": {
        "G": "#4a5a64",
        "S": "#2c3a44",
        "C": "#153a4a",
        "W": "#7ee6ff",
        "Y": "#ffd75e",
    },
}

# 16x16 diver locker (sub interior): tall cabinet with suit silhouette
LOCKER = {
    "grid": [
        ".GGGGGGGGGGGGGG.",
        ".GSSSSSSGSSSSSG.",
        ".GSSSSSSGSSSSSG.",
        ".GSSDDSSGSSDDSG.",
        ".GSDDDDSGSDDDDG.",
        ".GSSDDSSGSSDDSG.",
        ".GSDDDDSGSDDDDG.",
        ".GSDDDDSGSDDDDG.",
        ".GSSYSSSGSSYSSG.",
        ".GSSSSSSGSSSSSG.",
        ".GSSSSSSGSSSSSG.",
        ".GSSSSSSGSSSSSG.",
        ".GGGGGGGGGGGGGG.",
        ".GG..........GG.",
        "................",
        "................",
    ],
    "palette": {
        "G": "#4a5a64",
        "S": "#2c3a44",
        "D": "#d9a33c",
        "Y": "#7ee6ff",
    },
}

# 20x20 dive hatch (sub interior): round wheel-door in the deck
HATCH = {
    "grid": [
        "......PPPPPPP.......",
        "....PPGGGGGGGPP.....",
        "...PGGSSSSSSSGGP....",
        "..PGSSSSSSSSSSSGP...",
        ".PGSSSGSSSSSGSSSGP..",
        ".PGSSSSGSSSGSSSSGP..",
        "PGSSSSSSGSGSSSSSSGP.",
        "PGSSSSSSSGSSSSSSSGP.",
        "PGSGGGGGGGGGGGGGSGP.",
        "PGSSSSSSSGSSSSSSSGP.",
        "PGSSSSSSGSGSSSSSSGP.",
        ".PGSSSSGSSSGSSSSGP..",
        ".PGSSSGSSSSSGSSSGP..",
        "..PGSSSSSSSSSSSGP...",
        "...PGGSSSSSSSGGP....",
        "....PPGGGGGGGPP.....",
        "......PPPPPPP.......",
        "....................",
        "....................",
        "....................",
    ],
    "palette": {
        "P": "#1c2a33",
        "G": "#4a5a64",
        "S": "#2c3a44",
    },
}

# 12x12 porthole (sub interior): brass ring, deep water beyond
PORTHOLE = {
    "grid": [
        "...GGGGGG...",
        "..GYYYYYYG..",
        ".GYBBBBBBYG.",
        "GYBBCBBBBBYG",
        "GYBBBBBBBBYG",
        "GYBBBBBCBBYG",
        "GYBBBBBBBBYG",
        "GYBCBBBBBBYG",
        "GYBBBBBBBBYG",
        ".GYBBBBBBYG.",
        "..GYYYYYYG..",
        "...GGGGGG...",
    ],
    "palette": {
        "G": "#1c2a33",
        "Y": "#8a6420",
        "B": "#0b2030",
        "C": "#7ee6ff",
    },
}

# 20x20 Trench Warden (boss): armored angler — plated carapace, glowing
# lure, wide tooth-lined jaw
WARDEN = {
    "grid": [
        "........YY..........",
        ".........Y..........",
        ".........P..........",
        "......PPPPPPP.......",
        "....PPAAAAAAAPP.....",
        "...PAAPPAAAPPAAP....",
        "..PAAAPPAAAPPAAAP...",
        ".PAAAAAAAAAAAAAAAP..",
        ".PAARRAAAAAAARRAAP..",
        "PAAARRAAAAAAARRAAAP.",
        "PAAAAAAAAAAAAAAAAAPP",
        "PAWWAWWAWWAWWAWWAWAP",
        "PADDDDDDDDDDDDDDDDAP",
        ".PADDDDDDDDDDDDDDAP.",
        ".PAWWAWWAWWAWWAWAAP.",
        "..PAAAAAAAAAAAAAAP..",
        "...PAAAFFAAFFAAAP...",
        "....PPAFFAAFFAPP....",
        "......PPPFFPPP......",
        "........PPP.........",
    ],
    "palette": {
        "P": "#1a2830",
        "A": "#33505e",
        "R": "#c94f4f",
        "W": "#e8e4d0",
        "D": "#0c161c",
        "F": "#2a4450",
        "Y": "#ffd75e",
    },
}

# 16x16 wrecked relay (repair-quest objective): battered console, antenna,
# warning light
RELAY = {
    "grid": [
        ".......Y........",
        ".......G........",
        ".......G........",
        "....GGGGGGG.....",
        "...GSSSSSSSG....",
        "...GSCCCCCSG....",
        "...GSCWWCCSG....",
        "...GSCCCCCSG....",
        "...GSSSSSSSG....",
        "...GSDDSDDSG....",
        "...GSDDSDDSG....",
        "...GSSSSSSSG....",
        "....GGGGGGG.....",
        "....G.....G.....",
        "...GG.....GG....",
        "................",
    ],
    "palette": {
        "G": "#4a5a64",
        "S": "#2c3a44",
        "C": "#153a4a",
        "W": "#7ee6ff",
        "D": "#1c2a33",
        "Y": "#ffd75e",
    },
}

# 12x12 salvage payload (escort-quest objective): sealed pressure pod
PAYLOAD = {
    "grid": [
        "....GGGG....",
        "..GGYYYYGG..",
        ".GYYWWWWYYG.",
        ".GYWWCCWWYG.",
        "GYYWCCCCWYYG",
        "GYWWCCCCWWYG",
        "GYWWCCCCWWYG",
        "GYYWCCCCWYYG",
        ".GYWWCCWWYG.",
        ".GYYWWWWYYG.",
        "..GGYYYYGG..",
        "....GGGG....",
    ],
    "palette": {
        "G": "#6a5a2a",
        "Y": "#c9a84c",
        "W": "#e8d896",
        "C": "#7ee6ff",
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

# 10x10 depth-charge mine: dark steel ball with spikes and a warning light
MINE = {
    "grid": [
        "....R.....",
        "..S.W.S...",
        "...SSSS...",
        ".SSSKKSS..",
        "..SKKKKS..",
        "..SKKKKS..",
        ".SSSKKSSS.",
        "...SSSS...",
        "..S....S..",
        "..........",
    ],
    "palette": {
        "S": "#4a545c",
        "K": "#2e3438",
        "W": "#8a949c",
        "R": "#e04438",
    },
}

# 16x16 lurker: spiny ambusher, sand-colored until it strikes
LURKER = {
    "grid": [
        "................",
        "....S...S...S...",
        "....SS.SS..SS...",
        ".....SSSSSSS....",
        "..S.SSDDDDSS....",
        "..SSSDDDDDDSS...",
        "...SDDRDDDDDSS..",
        "..SSDDDDDDDDDS..",
        "...SDDDDDDDDSS..",
        "..SSSDDDDDDSS...",
        "..S.SSDDDDSS....",
        ".....SSSSSSS....",
        "....SS.SS..SS...",
        "....S...S...S...",
        "................",
        "................",
    ],
    "palette": {
        "S": "#7a6a4a",
        "D": "#5a4c34",
        "R": "#d84438",
    },
}

# 16x16 jelly bloom: translucent bell with trailing stingers
JELLY = {
    "grid": [
        "................",
        ".....JJJJJJ.....",
        "...JJJJJJJJJJ...",
        "..JJWWJJJJJJJJ..",
        "..JJWWJJJJJJJJ..",
        ".JJJJJJJJJJJJJJ.",
        ".JJJJJJJJJJJJJJ.",
        ".JPJPJPJPJPJPJP.",
        "..P.J.P.J.P.J...",
        "..J.P.J.P.J.P...",
        "..P...P...P.....",
        "....J...J...J...",
        "..P...P...P.....",
        "....J...J.......",
        "................",
        "................",
    ],
    "palette": {
        "J": "#b46ad4aa",
        "W": "#eed4ffcc",
        "P": "#8a4aaa88",
    },
}

# 24x24 trench maw: huge angler-thing that guards prime salvage
MAW = {
    "grid": [
        "...........G............",
        "..........GG............",
        ".........GG.............",
        "......MMMMMMMMMM........",
        "....MMMMMMMMMMMMMM......",
        "...MMMWWMMMMMMMMMMM.....",
        "..MMMWWWWMMMMMMMMMMM....",
        ".MMMMWWMMMMMMMMMMMMMM...",
        ".MMMMMMMMMMMMMMMMMMMMM..",
        "MMMMKKKKKKKKKKKKKMMMMMM.",
        "MMMKWKWKWKWKWKWKWKMMMMMM",
        "MMMMKKKKKKKKKKKKKKMMMMM.",
        "MMMKWKWKWKWKWKWKWKMMMMM.",
        "MMMMKKKKKKKKKKKKKMMMMM..",
        ".MMMMMMMMMMMMMMMMMMMMM..",
        ".MMMMMMMMMMMMMMMMMMMM...",
        "..MMMMMMMMMMMMMMMMMM....",
        "...MMMMMMMMMMMMMMMM.....",
        "....MMMM..MMMM..MM......",
        ".....MM....MM............",
        "........................",
        "........................",
        "........................",
        "........................",
    ],
    "palette": {
        "M": "#2e4a42",
        "W": "#f2e14c",
        "K": "#101c18",
        "G": "#8ef7d3",
    },
}

# 16x10 slash crescent (melee cutter/drill impact visual, tinted at runtime)
SLASH = {
    "grid": [
        "......WWWW......",
        "....WWWWWWWW....",
        "..WWWW....WWWW..",
        ".WWW........WWW.",
        ".WW..........WW.",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    "palette": {
        "W": "#f0f8ffdd",
    },
}

# 8x8 drone: little brass helper bot
DRONE = {
    "grid": [
        "...BB...",
        "..BYYB..",
        ".BYCCYB.",
        ".BYCCYB.",
        "..BYYB..",
        "...BB...",
        "..R..R..",
        "........",
    ],
    "palette": {
        "B": "#8a6508",
        "Y": "#d9a521",
        "C": "#9fe8ff",
        "R": "#b04a1e",
    },
}

SPRITES = {
    "diver.png": DIVER,
    "mine.png": MINE,
    "lurker.png": LURKER,
    "jelly.png": JELLY,
    "maw.png": MAW,
    "drone.png": DRONE,
    "slash.png": SLASH,
    "barbfish.png": BARBFISH,
    "brute.png": BRUTE,
    "harpoon.png": HARPOON,
    "gem.png": GEM,
    "nugget.png": NUGGET,
    "warden.png": WARDEN,
    "console.png": CONSOLE,
    "locker.png": LOCKER,
    "hatch.png": HATCH,
    "porthole.png": PORTHOLE,
    "relay.png": RELAY,
    "payload.png": PAYLOAD,
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


def gen_rock_atlas() -> list[list[tuple[int, int, int, int]]]:
    """64x16 atlas: three 16x16 rock tile variants (deterministic speckling)
    plus a fourth ore variant — same rock, veined with salvage-gold glints."""
    base = hex_rgba("#2a3b46")
    dark = hex_rgba("#1c2a33")
    lite = hex_rgba("#3d5260")
    edge = hex_rgba("#15202a")
    ore = hex_rgba("#d9a33c")
    ore_lite = hex_rgba("#f2cf6e")
    px = [[base for _ in range(64)] for _ in range(16)]
    for y in range(16):
        for x in range(64):
            variant = x // 16
            lx = x % 16
            h = (lx * 29 + y * 13 + variant * 41) % 89
            if lx in (0, 15) or y in (0, 15):
                px[y][x] = edge
            elif h < 12:
                px[y][x] = dark
            elif h < 20:
                px[y][x] = lite
            if variant == 3 and lx not in (0, 15) and y not in (0, 15):
                v = (lx * 17 + y * 31) % 71
                if v < 6:
                    px[y][x] = ore
                elif v == 6:
                    px[y][x] = ore_lite
    return px


def gen_ring(size: int = 64) -> list[list[tuple[int, int, int, int]]]:
    """Thin cyan ring for the sonar pulse visual (scaled up at runtime)."""
    c = (size - 1) / 2.0
    r_mid = c - 2.0
    px = []
    for y in range(size):
        row = []
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            a = max(0.0, 1.0 - abs(d - r_mid) / 2.5)
            row.append((140, 235, 255, int(a * 235)))
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
    write_png(os.path.join(OUT_DIR, "ring.png"), gen_ring())
    write_png(os.path.join(OUT_DIR, "rock.png"), gen_rock_atlas())
    print(f"Wrote {len(SPRITES) + 4} sprites to {os.path.normpath(OUT_DIR)}")


if __name__ == "__main__":
    main()
