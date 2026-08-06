# Diver sprite palette convention

The diver is recoloured at runtime from each player's chosen suit and helmet
screen colours. This is a **palette swap**: the shader looks for four specific
colours in the sprite and replaces them. Everything else is left untouched.

That means a replacement sprite recolours automatically **if it uses these four
hexes** for the parts that should be player-coloured.

## The four keys

| Hex | Generator key | Part | Replaced with |
| --- | --- | --- | --- |
| `#d9a521` | `Y` | suit, lit | the player's suit colour |
| `#8a6508` | `B` | suit, shadow | suit colour × `suit_shade` (0.62) |
| `#9fe8ff` | `W` | helmet screen, lit | the player's screen colour |
| `#0e3a52` | `C` | helmet screen, shadow | screen colour × `screen_shade` (0.36) |

Declared once in [`src/appearance.gd`](../src/appearance.gd) and passed to
[`assets/shaders/diver_recolor.gdshader`](../assets/shaders/diver_recolor.gdshader)
as uniforms, so the shader holds no hexes of its own.
`tests/palette_check.py` fails CI if these drift from the `DIVER` palette in
`tools/gen_pixel_art.py`.

## Drawing a replacement sprite

1. Use `#d9a521` / `#8a6508` for every pixel of the suit that should take the
   player's colour, and `#9fe8ff` / `#0e3a52` for the helmet screen.
2. Use **any other colours** for everything that should stay fixed — the air
   tank, boots, outlines, straps, tools. Those unchanged tones are what keep two
   players with similar suit colours still readable as the same kind of thing,
   so leave some of them.
3. Two steps per region is the minimum. The shader derives the shadow from the
   lit colour, so a single flat tone recolours but reads flat.
4. Save to `assets/sprites/diver.png` (or point `Appearance.SPRITE_PATH` at the
   new file). Nearest-neighbour filtering is already the project default.

Nothing else needs to change. Animations work the same way — every frame is
keyed independently, since the swap is per-pixel with no notion of frames.

## Gotchas

**Match the hexes exactly.** The shader matches within a tolerance of `0.02`,
about 5/255, which is there to absorb 8-bit rounding and nothing more. An
eyedropper that lands one step off still matches; a hand-mixed "close enough"
brass may not, and the failure is silent — those pixels simply stay the colour
you drew them.

**No anti-aliasing or gradients on the keyed regions.** Intermediate pixels
between two key colours match neither and will stay as drawn, which shows up as
a fringe of stock brass around a recoloured suit. This is a hard-edged pixel-art
convention by design.

**Don't reuse a key colour for something that shouldn't move.** If the boots are
also `#d9a521` they will recolour with the suit, because the shader can only see
colour — it has no idea what a boot is.

## Why not a mask texture?

A second texture marking which pixels are recolourable would free the art from
any palette constraint. It was rejected because it needs a mask authored and
maintained per sprite *and per animation frame*, and drifts silently when art
changes without the mask following. The palette convention costs one rule while
drawing and needs no second asset. If the art ever outgrows the constraint, a
mask is the upgrade path, and only `Appearance.make_material` and the shader
would change.
