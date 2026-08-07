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

# 8x8 guide arrow (off-screen objective marker). Points +X; the HUD rotates
# it and tints the white fill per target, so the outline must stay dark.
ARROW = {
    "grid": [
        "OO......",
        "OWWO....",
        "OWWWWO..",
        "OWWWWWWO",
        "OWWWWWWO",
        "OWWWWO..",
        "OWWO....",
        "OO......",
    ],
    "palette": {
        "O": "#0c161c",
        "W": "#ffffff",
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

# 16x16 wardrobe (sub interior): mirror over two dye canisters. Deliberately
# unlike the locker next to it — that one is a closed cabinet of suits (pick your
# class), this one is a mirror you stand at (pick your look). The canisters carry
# the two stock diver colours so the station reads as "colour" at 16px.
WARDROBE = {
    "grid": [
        "................",
        "................",
        "..GGGGGGGGGGGG..",
        "..GLLLLLLLLLLG..",
        "..GLLLLLWLLLLG..",
        "..GLLLLWWWLLLG..",
        "..GLLLLLWLLLLG..",
        "..GLLLLLLLLLLG..",
        "..GGGGGGGGGGGG..",
        "..G..........G..",
        "..G.CC....YY.G..",
        "..G.CC....YY.G..",
        "..GGGGGGGGGGGG..",
        "..GG........GG..",
        "................",
        "................",
    ],
    "palette": {
        "G": "#4a5a64",
        "L": "#24404e",
        "W": "#ffffff",
        "C": "#d9a521",
        "Y": "#9fe8ff",
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
    "arrow.png": ARROW,
    "console.png": CONSOLE,
    "locker.png": LOCKER,
    "wardrobe.png": WARDROBE,
    "hatch.png": HATCH,
    "porthole.png": PORTHOLE,
    "relay.png": RELAY,
    "payload.png": PAYLOAD,
    "crate.png": CRATE,
    "bell.png": BELL,
}


def _value_noise_tile(size: int, period: int, seed: int) -> list[list[float]]:
    """Tileable value noise in 0..1. The lattice wraps at `period`, so as long
    as period divides size the tile butts against itself seamlessly — which the
    seabed needs, since one tile is repeated across the whole arena."""
    step = size // period
    lattice = [
        [(_hash2(gx + 1, (gy + 1) * 131 + seed) % 1000) / 999.0 for gx in range(period)]
        for gy in range(period)
    ]
    out = [[0.0 for _ in range(size)] for _ in range(size)]
    for y in range(size):
        for x in range(size):
            fx = x / step
            fy = y / step
            x0 = int(fx) % period
            y0 = int(fy) % period
            x1 = (x0 + 1) % period
            y1 = (y0 + 1) % period
            # Smoothstep the interpolation, or the lattice shows up as
            # diamond-shaped facets.
            tx = fx - int(fx)
            ty = fy - int(fy)
            sx = tx * tx * (3 - 2 * tx)
            sy = ty * ty * (3 - 2 * ty)
            top = lattice[y0][x0] * (1 - sx) + lattice[y0][x1] * sx
            bottom = lattice[y1][x0] * (1 - sx) + lattice[y1][x1] * sx
            out[y][x] = top * (1 - sy) + bottom * sy
    return out


FLOOR_TILE = 128


def gen_floor() -> list[list[tuple[int, int, int, int]]]:
    """Seabed tile built from three octaves of tileable value noise, so silt
    gathers in drifts. The old version keyed colour off `(x*31 + y*17) % 97`,
    and a linear function under a modulo lays down a regular diagonal lattice.

    128px rather than 32: the arena repeats this one tile across 1600px, and at
    32 the drifts were big enough relative to the tile that the repeat read as
    a grid — worse than the speckle it replaced. Bigger tile, finer features."""
    deep = hex_rgba("#08161f")
    base = hex_rgba("#0a1c2b")
    mid = hex_rgba("#0c2030")
    silt = hex_rgba("#123049")
    algae = hex_rgba("#0f2e33")
    size = FLOOR_TILE
    broad = _value_noise_tile(size, 8, 11)  # slow sediment drifts
    medium = _value_noise_tile(size, 16, 29)
    grain = _value_noise_tile(size, 64, 47)  # per-pixel-ish grit
    px = [[base for _ in range(size)] for _ in range(size)]
    for y in range(size):
        for x in range(size):
            n = broad[y][x] * 0.4 + medium[y][x] * 0.3 + grain[y][x] * 0.3
            # Narrow bands: the seabed wants texture, not tonal blotches.
            if n < 0.38:
                px[y][x] = deep
            elif n < 0.46:
                px[y][x] = mid
            elif n < 0.70:
                px[y][x] = base
            elif n < 0.78:
                px[y][x] = mid
            else:
                px[y][x] = silt
            # Algae settles where the grit peaks inside a darker drift.
            if grain[y][x] > 0.88 and broad[y][x] < 0.45:
                px[y][x] = algae
    return px


def gen_light(size: int = 128) -> list[list[tuple[int, int, int, int]]]:
    """Lamp disc for PointLight2D: a hard edge and quantised bands instead of a
    smooth radial fade. A soft gradient reads as an airbrush laid over 16px
    pixel art — the crisp cut belongs to the same grid as everything else, and
    the project renders 2D with nearest filtering, so the edge stays sharp
    however far PointLight2D scales it up.

    Three bands rather than one flat disc: the light still falls off toward the
    rim, it just does it in steps you can count."""
    c = (size - 1) / 2.0
    px = []
    for y in range(size):
        row = []
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / c
            if d > 1.0:
                alpha = 0.0  # hard cut: outside the lamp is outside the lamp
            elif d > 0.87:
                alpha = 0.52
            elif d > 0.63:
                alpha = 0.80
            else:
                alpha = 1.0
            row.append((255, 245, 220, int(alpha * 255)))
        px.append(row)
    return px


def gen_rock_atlas() -> list[list[tuple[int, int, int, int]]]:
    """64x16 atlas: three 16x16 rock top faces (deterministic speckling) plus
    a fourth ore variant, veined with salvage-gold glints.

    Deliberately seamless — no per-tile border. An outline on every cell turns
    a rock mass into visible graph paper; definition comes instead from the
    dressing layers, which rim only the edges actually exposed to open water
    (see terrain.gd)."""
    base = hex_rgba("#2a3b46")
    dark = hex_rgba("#1c2a33")
    lite = hex_rgba("#3d5260")
    ore = hex_rgba("#d9a33c")
    ore_lite = hex_rgba("#f2cf6e")
    px = [[base for _ in range(64)] for _ in range(16)]
    for y in range(16):
        for x in range(64):
            variant = x // 16
            lx = x % 16
            h = (lx * 29 + y * 13 + variant * 41) % 89
            if h < 12:
                px[y][x] = dark
            elif h < 20:
                px[y][x] = lite
            if variant == 3:
                v = (lx * 17 + y * 31) % 71
                if v < 6:
                    px[y][x] = ore
                elif v == 6:
                    px[y][x] = ore_lite
    return px


def gen_rock_edge_atlas() -> list[list[tuple[int, int, int, int]]]:
    """128x16 atlas: rim highlights for the three sides that aren't the front,
    drawn only where a rock cell actually meets open water. Together with the
    wall front on the south, this is what gives the mass a silhouette now that
    the rock tiles themselves are seamless.

    The column index is an exposure bitmask (1 = north, 2 = west, 4 = east), so
    a corner gets both of its rims from one tile — a tile layer holds only a
    single tile per cell, and three separate layers for this would be waste."""
    clear = (0, 0, 0, 0)
    rim = hex_rgba("#4f6878")
    soft = hex_rgba("#3a4e5c")
    px = [[clear for _ in range(128)] for _ in range(16)]
    for mask in range(8):
        ox = mask * 16
        if mask & 1:  # north: the lamp-lit top lip
            for i in range(16):
                px[0][ox + i] = rim
                px[1][ox + i] = soft
        # Side rims stay a single dim pixel: the light reads as coming from
        # above, and doubling these up outlines the mass like a cartoon stroke.
        if mask & 2:  # west
            for y in range(16):
                px[y][ox] = soft
        if mask & 4:  # east
            for y in range(16):
                px[y][ox + 15] = soft
    return px


FACE_ROWS = 7  # opaque rows of a wall-front tile; the rest shows the deck.
# Kept well under half a cell on purpose: mining carves single-cell tunnels,
# and a taller front would leave one of those looking almost filled in.


# One palette for every kind of growth — mats on the rock tops, fronds
# overhanging the lips, tufts clinging to the side rims. Darker blue-green
# than a plant green: it has to read as something living in near-black water,
# close enough to the rock's own value that a dressed block still reads as
# stone rather than turning into a green tile.
GROWTH_DEEP = "#0d2a2a"
GROWTH_MID = "#15423f"
GROWTH_LITE = "#226059"
GROWTH_GLOW = "#7ee6ff"  # bioluminescent bud, straight from the game palette


def _hash2(a: int, b: int) -> int:
    """Small integer mix. Anything linear in x leaves a visible diagonal comb
    across a tile, so the organic dressing needs a real scramble."""
    h = (a * 374761393 + b * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFFFFFF


def gen_rock_face_atlas() -> list[list[tuple[int, int, int, int]]]:
    """64x16 atlas: four wall fronts (3 rock + 1 ore) matching rock.png's
    columns. Only the top FACE_ROWS are opaque — the tile is drawn in the open
    cell below a rock, so the band reads as the wall's front and the floor
    still shows beneath it. Darker than the top face: this side faces away
    from the diver's lamp."""
    clear = (0, 0, 0, 0)
    # The front faces away from the light, so every tone here sits BELOW the
    # top face's #2a3b46 — that value drop is what sells the turn of the edge.
    lip = hex_rgba("#3d5260")  # just enough to catch the lip
    base = hex_rgba("#1a2731")
    dark = hex_rgba("#121c24")
    deep = hex_rgba("#080e13")
    ore = hex_rgba("#a8762a")
    px = [[clear for _ in range(64)] for _ in range(16)]
    for y in range(FACE_ROWS):
        for x in range(64):
            variant = x // 16
            lx = x % 16
            if y == 0:
                px[y][x] = lip
            elif y >= FACE_ROWS - 2:
                px[y][x] = deep  # contact shadow where wall meets deck
            else:
                # Vertical striations, darkening toward the base.
                streak = (lx * 23 + variant * 37) % 5
                px[y][x] = dark if streak < 2 or y > FACE_ROWS - 5 else base
            # Ore seams glint on the front too, not just the top face.
            if variant == 3 and 0 < y < FACE_ROWS - 2:
                if (lx * 17 + y * 29) % 41 < 5:
                    px[y][x] = ore
    return px


def gen_rock_growth_atlas() -> list[list[tuple[int, int, int, int]]]:
    """64x16 atlas: four overhang variants — abyssal growth cresting a wall's
    lip and trailing over its front. Drawn on a layer offset half a cell down,
    so the upper rows sit on the rock and the lower rows dangle past the edge,
    breaking the tile grid's straight silhouette."""
    clear = (0, 0, 0, 0)
    dark = hex_rgba(GROWTH_DEEP)
    mid = hex_rgba(GROWTH_MID)
    lite = hex_rgba(GROWTH_LITE)
    glow = hex_rgba(GROWTH_GLOW)
    px = [[clear for _ in range(64)] for _ in range(16)]
    # Each variant is a sparse arrangement of clumps rather than full-width
    # cover: growth wants to read as something that took hold in places, and
    # a continuous fringe would just be a green stripe hiding the wall.
    clumps = [
        [(1, 6)],  # one clump, left of centre
        [(5, 8)],  # a broad clump mid-tile
        [(0, 4), (10, 5)],  # two smaller colonies
        [(11, 4)],  # a lone wisp near the right edge
    ]
    for variant, spans in enumerate(clumps):
        for start, width in spans:
            middle = (width - 1) / 2.0
            for i in range(width):
                lx = start + i
                if lx > 15:
                    continue
                x = variant * 16 + lx
                # Fat in the middle, tapering at the edges, so a clump has a
                # rounded silhouette instead of a squared-off block.
                taper = 1.0 - abs(i - middle) / (middle + 1.0)
                h = _hash2(lx + 1, variant + 1)
                crest = max(1, round((2 + h % 3) * (0.5 + 0.5 * taper)))
                for y in range(crest):
                    px[y][x] = lite if y >= crest - 1 else mid
                # Long enough to trail past the bottom of the wall front and
                # hang free in the water — the drape is the whole point.
                frond = round((5 + (h >> 3) % 8) * taper)
                if frond > 2:
                    tip = min(16, crest + frond)
                    sway = 1 if (h >> 11) % 2 else -1
                    last = None
                    for y in range(crest, tip):
                        fall = y - crest
                        # Curls to one side as it falls, so a frond drapes
                        # instead of hanging like a plumb line.
                        column = lx + sway * (fall // 4)
                        if 0 <= column < 16:
                            # Fronds darken as they fall away from the lit lip,
                            # holding the mid tone a while so the drape still
                            # reads against the dark wall front behind it.
                            px[y][variant * 16 + column] = dark if fall > 4 else mid
                            last = (y, column)
                        # Doubled up near the crown: a single pixel column
                        # reads as a hair, not a frond.
                        if fall < 3 and 0 <= column + sway < 16:
                            px[y][variant * 16 + column + sway] = mid
                    if frond >= 8 and last is not None:
                        px[last[0]][variant * 16 + last[1]] = glow  # bud
    return px


def gen_rock_tuft_atlas() -> list[list[tuple[int, int, int, int]]]:
    """48x16 atlas: tufts clinging to a rock's vertical rims — column 0 west,
    1 east, 2 both. Growth shouldn't only live on the lips; the sides that face
    open water collect it too."""
    clear = (0, 0, 0, 0)
    deep = hex_rgba(GROWTH_DEEP)
    mid = hex_rgba(GROWTH_MID)
    lite = hex_rgba(GROWTH_LITE)
    px = [[clear for _ in range(48)] for _ in range(16)]

    def cling(ox: int, west: bool, seed: int) -> None:
        for y in range(16):
            h = _hash2(y + 1, seed)
            if h % 5 >= 2:
                continue  # leave gaps: a continuous fringe reads as a border
            for i in range(1 + h % 3):
                x = i if west else 15 - i
                px[y][ox + x] = lite if i == 0 else (mid if i < 2 else deep)

    cling(0, True, 17)
    cling(16, False, 29)
    cling(32, True, 17)  # column 2 carries both rims
    cling(32, False, 29)
    return px


def gen_shadow(width: int = 16, height: int = 5) -> list[list[tuple[int, int, int, int]]]:
    """Soft elliptical drop shadow, black with an alpha falloff. Squashed hard
    on the vertical: it lies on the deck beneath a sprite that stands up, and a
    taller ellipse buries its own dense middle behind the sprite, leaving only
    the faint rim showing — which is invisible against a near-black seabed."""
    px = []
    cx = (width - 1) / 2.0
    cy = (height - 1) / 2.0
    for y in range(height):
        row = []
        for x in range(width):
            dx = (x - cx) / (cx + 0.5)
            dy = (y - cy) / (cy + 0.5)
            d = (dx * dx + dy * dy) ** 0.5
            # Squared falloff: a denser core with a rim that fades out, rather
            # than a uniform blob with a hard edge.
            fade = max(0.0, 1.0 - d) ** 1.6
            row.append((0, 0, 0, int(fade * 175)))
        px.append(row)
    return px


SUB_HULL_W = 296
SUB_HULL_H = 136
SUB_BOW = 52  # px of bow taper (right); long and pointed
SUB_STERN = 30  # px of stern taper (left); short and blunt
SUB_PLATE = 10  # thickness of the pressure hull around the deck


def _sub_half_height(x: int) -> float:
    """Hull half-height at a given station along the length. Asymmetric on
    purpose: a symmetric taper reads as a pill, not a boat."""
    top = SUB_HULL_H / 2.0 - 1.0
    if x < SUB_STERN:  # blunt, barely-tapered stern
        t = (x + 1) / float(SUB_STERN)
        return (0.55 + 0.45 * t ** 0.5) * top
    if x > SUB_HULL_W - 1 - SUB_BOW:  # long, pointed bow
        t = (SUB_HULL_W - 1 - x) / float(SUB_BOW)
        return (0.08 + 0.92 * t ** 0.8) * top
    return top


def gen_sub_hull() -> list[list[tuple[int, int, int, int]]]:
    """Top-down cutaway of the sub: pointed bow, blunt finned stern, sealed
    compartments at each end and a ribbed walkable deck between them. The
    interior used to be a plain rectangle of ColorRects, which read as a room
    rather than a boat (issue #32)."""
    clear = (0, 0, 0, 0)
    rim = hex_rgba("#6a8090")  # lit outer edge of the pressure hull
    hull = hex_rgba("#101a22")  # plating, well below the deck's value
    rib = hex_rgba("#243544")
    deck = hex_rgba("#1e3140")
    seam = hex_rgba("#15242f")
    px = [[clear for _ in range(SUB_HULL_W)] for _ in range(SUB_HULL_H)]
    cy = (SUB_HULL_H - 1) / 2.0
    # The deck only spans the midsection; bow and stern stay sealed hull, which
    # is what makes it read as a vessel with a crew space inside it.
    deck_from = SUB_STERN + 6
    deck_to = SUB_HULL_W - 1 - SUB_BOW - 6
    for x in range(SUB_HULL_W):
        half = _sub_half_height(x)
        for y in range(SUB_HULL_H):
            d = abs(y - cy)
            if d > half:
                continue
            if d > half - 2.0:
                px[y][x] = rim
            elif d > half - SUB_PLATE or not (deck_from <= x <= deck_to):
                px[y][x] = rib if x % 20 < 2 else hull
            else:
                px[y][x] = seam if x % 24 == 0 else deck
        # Bulkheads closing the crew space off from the end compartments.
        if x in (deck_from - 1, deck_to + 1):
            for y in range(SUB_HULL_H):
                if abs(y - cy) <= half - 2.0:
                    px[y][x] = rib

    # Stern fin: stands proud of the hull line, so the silhouette has a tail.
    fin_half = (SUB_HULL_H / 2.0 - 1.0) * 0.92
    for x in range(0, 9):
        for y in range(SUB_HULL_H):
            d = abs(y - cy)
            if d <= fin_half and d > _sub_half_height(x):
                px[y][x] = rim if d > fin_half - 2.0 else hull
    return px


def gen_motes(
    size: int = 64, count: int = 40, brightness: int = 70, seed: int = 5
) -> list[list[tuple[int, int, int, int]]]:
    """Tileable marine snow: sparse pale specks on transparency. Specks wrap
    around the edges, so the tile repeats without seams — two of these scroll
    at different rates to give the water column some volume."""
    px = [[(0, 0, 0, 0) for _ in range(size)] for _ in range(size)]
    for i in range(count):
        h = _hash2(i + 1, seed)
        cx = h % size
        cy = (h >> 8) % size
        radius = 2 if (h >> 16) % 4 == 0 else 1  # mostly motes, a few flakes
        alpha = brightness - (h >> 18) % 25
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if dx * dx + dy * dy > radius * radius:
                    continue
                # Wrapping the write is what makes the tile seamless.
                x = (cx + dx) % size
                y = (cy + dy) % size
                core = dx == 0 and dy == 0
                px[y][x] = (200, 225, 235, alpha if core else int(alpha * 0.45))
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
    write_png(os.path.join(OUT_DIR, "shadow.png"), gen_shadow())
    write_png(os.path.join(OUT_DIR, "sub_hull.png"), gen_sub_hull())
    # Sparse on purpose. Tiled across a 640x360 view these land at roughly
    # 250 specks across a 640x360 view; the first attempt was ~1100 and read as a blizzard.
    write_png(os.path.join(OUT_DIR, "motes_near.png"), gen_motes(128, 6, 58, 5))
    write_png(os.path.join(OUT_DIR, "motes_far.png"), gen_motes(128, 12, 30, 19))
    write_png(os.path.join(OUT_DIR, "ring.png"), gen_ring())
    write_png(os.path.join(OUT_DIR, "rock.png"), gen_rock_atlas())
    write_png(os.path.join(OUT_DIR, "rock_edge.png"), gen_rock_edge_atlas())
    write_png(os.path.join(OUT_DIR, "rock_face.png"), gen_rock_face_atlas())
    write_png(os.path.join(OUT_DIR, "rock_growth.png"), gen_rock_growth_atlas())
    write_png(os.path.join(OUT_DIR, "rock_tuft.png"), gen_rock_tuft_atlas())
    print(f"Wrote {len(SPRITES) + 12} sprites to {os.path.normpath(OUT_DIR)}")


if __name__ == "__main__":
    main()
