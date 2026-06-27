vec2 uv_distortion(float noise_scale, float wave_speed, float intensity) {
    return uv + (texture(noisetex, uv * noise_scale + vec2(0.0, frameTimeCounter * wave_speed)).rg - 0.5) * intensity * camera_water_state;
}

vec3 color_distortion(vec2 uv) {
    return texture(colortex0, uv).rgb;
}

void leave_water_distortion(inout vec3 scene_color) {
    vec2 distorted_uv = uv_distortion(0.25, 0.1, 0.15);

    scene_color = color_distortion(distorted_uv);
}

void underwater_distortion(inout vec3 scene_color) {
    vec2 distorted_uv = uv_distortion(0.05, 0.01, 0.05);

    scene_color = color_distortion(distorted_uv);
}