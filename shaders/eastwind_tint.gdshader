shader_type canvas_item;
// 借东风全屏罩(M4 接入;M1 由 WeatherManager 预先落位):
// 12% 透明度春青色罩 + 斜向风线粒子(01 §11)。
uniform vec4 tint_color : source_color = vec4(0.561, 0.682, 0.545, 0.12);
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float wind = sin((SCREEN_UV.x * 2.0 + SCREEN_UV.y * 6.0) * 20.0 + TIME * 4.0);
	float lines = smoothstep(0.92, 1.0, wind) * 0.10;
	COLOR = vec4(tint_color.rgb, tint_color.a * strength + lines * strength);
}
