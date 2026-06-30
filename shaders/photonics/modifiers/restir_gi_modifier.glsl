const float blocklight_scale = 6.0f * LIGHTMAP_MIX_I;
const float rcp_blocklight_scale = 1.0 / max(blocklight_scale, 1e-4);

void modify_restir_gi(inout vec3 color) {
    color*= rcp_blocklight_scale * SKYLIGHT_I;
}