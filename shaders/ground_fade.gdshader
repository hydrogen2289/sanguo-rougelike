shader_type spatial;
// 地面(M2):米纸平铺 + 边缘向背景色渐隐(02 §4「卷轴渐隐」)。
// PlaneMesh 60×60,UV 0..1 覆盖全场,中心距 = length(UV-0.5)*60。
uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(12.0, 12.0);
uniform float fade_start = 18.0;
uniform float fade_end = 26.0;
uniform vec4 fade_color : source_color = vec4(0.949, 0.918, 0.827, 1.0);

void fragment() {
	vec4 tex = texture(base_tex, UV * uv_scale);
	float d = length(UV - vec2(0.5)) * 60.0;
	float t = clamp((d - fade_start) / max(0.001, fade_end - fade_start), 0.0, 1.0);
	ALBEDO = mix(tex.rgb, fade_color.rgb, t);
	ROUGHNESS = 1.0;
}
