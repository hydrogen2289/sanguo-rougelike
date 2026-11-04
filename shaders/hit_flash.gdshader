shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// 受击白闪(M1):以 material_overlay 挂在 Sprite3D 上,
// flash_strength 由 unit_base 在 take_damage 时 tween 回 0。
uniform sampler2D base_tex : source_color, filter_linear;
uniform vec4 flash_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(base_tex, UV);
	ALBEDO = flash_color.rgb;
	ALPHA = tex.a * flash_strength;
}
