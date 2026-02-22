shader_type spatial;

// unshaded: la luz no lo afecta. 
// depth_test_disabled: siempre se dibuja por encima de la geometría 3D, para no "chocar" con las paredes.
render_mode unshaded, depth_test_disabled;

#define MAXCOLORS 16

uniform bool enabled = true;
uniform bool dithering = true;
uniform int colors : hint_range(1, MAXCOLORS) = 12;
uniform int dither_size: hint_range(1, 8) = 1;

// Captura la pantalla detrás del plano
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

float dithering_pattern(ivec2 fragcoord) {
    const float pattern[] = {
        0.00, 0.50, 0.10, 0.65, 
        0.75, 0.25, 0.90, 0.35, 
        0.20, 0.70, 0.05, 0.50, 
        0.95, 0.40, 0.80, 0.30
    };
    
    int x = fragcoord.x % 4;
    int y = fragcoord.y % 4;
    
    return pattern[y * 4 + x];
}

float reduce_color(float raw, float dither, int depth) {
    float div = 1.0 / float(depth);
    float val = 0.0;
    int i = 0;

    while (i <= MAXCOLORS) {
        if (raw > div * (float(i + 1))) {
            i = i + 1;
            continue;
        }

        if (raw * float(depth) - float(i) <= dither * 0.999) {
            val = div * float(i);
        } else {
            val = div * float(i + 1);
        }
        return val;

        i = i+1;
    }

    return val;
}

void fragment() {
    vec4 raw = texture(screen_texture, SCREEN_UV);
    ivec2 uv = ivec2(FRAGCOORD.xy / float(dither_size));

    if (enabled) {
        float dithering_value = 1.0;
        if (dithering) {
            dithering_value = dithering_pattern(uv);
        }
        
        // En 3D usamos ALBEDO en lugar de COLOR
        ALBEDO.r = reduce_color(raw.r, (dithering_value - 0.5) * dithering_value + 0.5, colors - 1);
        ALBEDO.g = reduce_color(raw.g, (dithering_value - 0.5) * dithering_value + 0.5, colors - 1);
        ALBEDO.b = reduce_color(raw.b, (dithering_value - 0.5) * dithering_value + 0.5, colors - 1);
    } else {
        ALBEDO = raw.rgb;
    }
}