shader_type spatial;
render_mode unshaded, cull_front;

uniform bool enable = true;
uniform float outline_thickness = 0.03;
uniform vec4 color : source_color = vec4(0.0);


void vertex() {
	if (enable==true) {
	VERTEX += NORMAL*outline_thickness;
	}
}

void fragment() {
	if (enable==true) {
	ALBEDO = color.rgb;
	}
}