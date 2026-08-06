shader_type canvas_item;
// Two-colour palette swap for the diver sprite. The suit and the helmet screen
// are each drawn as a two-step ramp (a lit tone and a shadow tone), and we
// replace the ramp rather than flat-filling it — flat colour reads as a sticker
// and loses the pixel shading entirely.
//
// The key colours are uniforms, not constants, so the palette lives in exactly
// one place: Appearance in src/appearance.gd. See docs/sprite-palette.md for the
// convention a hand-drawn replacement sprite needs to follow.
//
// Deliberately no `source_color` hint on any of these. That hint asks Godot to
// convert an sRGB Color into linear space, which would put the replacement
// values in a different space from what texture() returns and break both the
// key comparison and the output. Raw values on both sides keeps this a literal
// "this pixel value becomes that pixel value" swap, which is what pixel-art
// palette swapping wants.

uniform vec4 key_suit_lit;
uniform vec4 key_suit_dark;
uniform vec4 key_screen_lit;
uniform vec4 key_screen_dark;

uniform vec4 suit;
uniform vec4 screen;

// How far a shadow tone sits below its lit tone. Derived from the source art's
// own ramp ratios so a recoloured diver keeps the contrast the original had.
uniform float suit_shade = 0.62;
uniform float screen_shade = 0.36;

// Downed/hit look. This used to be $Sprite.modulate, but modulate multiplies
// into COLOR before fragment() runs, which would fight the swap. Routing it
// through the shader leaves the shader as the only thing colouring this sprite.
// `alpha` is here for the same reason: the downed tint carried a 0.9 alpha, and
// writing COLOR outright would otherwise drop that transparency on the floor.
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_tint = vec4(1.0, 0.55, 0.55, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

// Nearest-neighbour sampling with no mipmaps means an exact palette hit, so this
// only has to absorb 8-bit quantisation (1/255 ~ 0.004).
const float TOL = 0.02;

bool matches(vec3 c, vec3 key) {
	return distance(c, key) < TOL;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = tex.rgb;

	if (matches(tex.rgb, key_suit_lit.rgb)) {
		rgb = suit.rgb;
	} else if (matches(tex.rgb, key_suit_dark.rgb)) {
		rgb = suit.rgb * suit_shade;
	} else if (matches(tex.rgb, key_screen_lit.rgb)) {
		rgb = screen.rgb;
	} else if (matches(tex.rgb, key_screen_dark.rgb)) {
		rgb = screen.rgb * screen_shade;
	}
	// Anything else — the tank, the boots, outlines — is left alone on purpose.
	// Those unchanged tones are what keep two players with similar suit colours
	// still readable as the same species of thing.

	rgb = mix(rgb, flash_tint.rgb, flash);
	COLOR = vec4(rgb, tex.a * alpha);
}
