shader_type spatial;
render_mode specular_disabled;

// Realistic scenery look (default): the toon shader's surfaces and detail, lit with plain Lambert, leafy
// normal relief on foliage and no rim light. Ink outlines are left off by ToonUtil. See toon_body.gdshaderinc.
#define NG_REAL
#include "res://shaders/toon_body.gdshaderinc"
