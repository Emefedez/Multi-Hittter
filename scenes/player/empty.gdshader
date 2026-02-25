shader_type spatial;

// Color del flash (blanco por defecto) y su intensidad (alpha)
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

void fragment() {
	// Aquí iría tu lógica de textura normal. 
	// Por ahora, mezclamos el color base con el color del flash.
	// Si el alpha de flash_color es 0, el modelo se ve normal.
	ALBEDO = mix(ALBEDO, flash_color.rgb, flash_color.a);
}