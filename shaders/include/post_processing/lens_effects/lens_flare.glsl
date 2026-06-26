/*
Catman's lens flare from Seus Forum, also used by Chocapic13 and Continuum. Encapsulated repeated codes into functions
https://www.sonicether.com/forum/viewtopic.php?f=4&t=175 (Original site, no longer available)
https://www.neocodex.us/forum/topic/126112-guide-add-lens-flare-to-seus-shader-pack/
*/

//--------------------HELPERS--------------------//

// Calculates position for "Ghost" flares (artifacts moving opposite to light)
vec2 get_ghost_pos(float offset, vec2 scale_vec) {
    return vec2(
        ((1.0 - light_pos.x) * (offset + 1.0) - (offset * 0.5)) * scale_vec.x,
        ((1.0 - light_pos.y) * (offset + 1.0) - (offset * 0.5)) * scale_vec.y
    );
}

// Calculates the base intensity (0.0 to 1.0) based on distance
float get_radial_falloff(vec2 center_pos, vec2 scale_vec, float fill) {
    float dist = distance(center_pos, uv * scale_vec);
    float value = 0.5 - dist;
    return clamp01(value * fill);
}

// Applies Sine shaping, Power, and Masking
float apply_shaping(float value, float sin_freq, float pow_exp, float intensity, float mask) {
    if (sin_freq > 0.0) {
        value = sin(value * sin_freq);
    }
    value = pow(value, pow_exp);
    return value * intensity * mask;
}

// Final color composition
vec3 flare_color(float intensity, vec3 color, float noise) {
    return color * intensity * noise;
}

float get_luminance(vec3 color) {
    return dot(color, luminance_weights_rec709);
}

//--------------------FLARES--------------------//

// Rainbow
vec3 draw_rainbow_flare(
     
    float scale, float pow_val, float fill, float offset,
    float subtract_scale, float subtract_pow, float subtract_fill, float subtract_offset,
    float sunmask, vec3 color, float noise_stripe_pattern
) {
    vec2 flare_scale = vec2(aspectRatio, 1.0) * scale;
    vec2 flare_pos = get_ghost_pos(0.0, flare_scale); 
    
    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
          flare = apply_shaping(flare, half_pi, 1.1, pow_val, 1.0);

    vec2 flare_subtract_scale = vec2(aspectRatio, 1.0) * subtract_scale;
    vec2 flare_subtract_pos = 0.9 * flare_subtract_scale - light_pos * 0.8 * flare_subtract_scale;
    
    float flare_subtract = get_radial_falloff(flare_subtract_pos, flare_subtract_scale, subtract_fill);
          flare_subtract = apply_shaping(flare_subtract, half_pi, 0.9, subtract_pow, 1.0);

          flare = clamp(flare - flare_subtract, 0.0, 10.0);
          flare *= sunmask;

    return flare_color(flare, color, noise_stripe_pattern);
}

// Far blue flare & far small pink flare
vec3 draw_far_flare(
     
    float scale, float pow_val, float fill, float offset,
    float subtract_scale, float subtract_pow, float subtract_fill, float subtract_offset,
    float sunmask, vec3 color, float noise_stripe_pattern
) {
    vec2 flare_scale = vec2(scale * aspectRatio, scale);
    vec2 flare_pos = get_ghost_pos(offset, flare_scale);
    
    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
          flare = apply_shaping(flare, half_pi, 1.1, pow_val, 1.0);

    vec2 flare_subtract_scale = vec2(subtract_scale * aspectRatio, subtract_scale);
    vec2 flare_subtract_pos = get_ghost_pos(subtract_offset, flare_subtract_scale);
    
    float flare_subtract = get_radial_falloff(flare_subtract_pos, flare_subtract_scale, subtract_fill);
          flare_subtract = apply_shaping(flare_subtract, half_pi, 0.9, subtract_pow, 1.0);

          flare = clamp(flare - flare_subtract, 0.0, 10.0);
          flare *= sunmask;

    return flare_color(flare, color, noise_stripe_pattern);
}

// Close ring flare (rainbow halo around the sun)
vec3 draw_close_ring_flare(
     
    float scale, float pow_val, float fill, float offset, float pow_exp, float sin_freq, float sunmask, vec3 color, float noise_stripe_pattern
) {
    vec2 flare_scale = vec2(scale * aspectRatio, scale);
    vec2 flare_pos = get_ghost_pos(offset, flare_scale);
    
    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
    flare = apply_shaping(flare, sin_freq, pow_exp, pow_val, sunmask);

    return flare_color(flare, color, noise_stripe_pattern);
}

// Anamorphic flare center
vec3 draw_anamorphic_center(
     
    vec2 scale, float pow_exp, float fill, float flare_pow, vec3 color) {
    vec2 flare_scale = vec2(aspectRatio * scale.x, scale.y);
    vec2 flare_pos = vec2(light_pos.x * flare_scale.x, light_pos.y * flare_scale.y);

    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
    
          flare = pow(flare, pow_exp);
          flare *= flare_pow;

    return flare_color(flare, color, 1.0);
}

/*// X cross flare
vec3 draw_xcross_flare(
    
    vec2 scale, float pow_exp, float fill, float flare_pow,
    float multR, float multG, float multB
) {
    vec2 rel_uv = uv - light_pos;
    float angle1 = pi / 3.5;
    float c1 = cos(angle1); float s1 = sin(angle1);
    vec2 rot1 = vec2(rel_uv.x * c1 - rel_uv.y * s1, rel_uv.x * s1 + rel_uv.y * c1);

    float angle2 = -pi / 3.5;
    float c2 = cos(angle2); float s2 = sin(angle2);
    vec2 rot2 = vec2(rel_uv.x * c2 - rel_uv.y * s2, rel_uv.x * s2 + rel_uv.y * c2);

    float flare1 = draw_anamorphic_center(
        rot1 + light_pos, light_pos,
        scale, pow_exp, fill, flare_pow, 1.0, 1.0, 1.0
    ).r;
    
    float flare2 = draw_anamorphic_center(
        rot2 + light_pos, light_pos,
        scale, pow_exp, fill, flare_pow, 1.0, 1.0, 1.0
    ).r;

    return vec3(flare1 + flare2) * vec3(multR, multG, multB);
}//*/

// Mid orange sweep
vec3 draw_mid_orange_sweep(
     
    float scale, float pow_val, float fill, float offset, float pow_exp, float sin_freq,
    float subtract_scale, float subtract_pow_val, float subtract_fill, float subtract_offset, float subtract_pow_exp, float subtract_sin_freq,
    float sunmask, vec3 color
) {
    // Main
    vec2 flare_scale = vec2(scale * aspectRatio, scale);
    vec2 flare_pos = get_ghost_pos(offset, flare_scale);
    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
          flare = apply_shaping(flare, sin_freq, pow_exp, pow_val, 1.0);

    // Subtract
    vec2 flare_subtract_scale = vec2(subtract_scale * aspectRatio, subtract_scale);
    vec2 flare_subtract_pos = get_ghost_pos(subtract_offset, flare_subtract_scale);
    float flare_subtract = get_radial_falloff(flare_subtract_pos, flare_subtract_scale, subtract_fill);
          flare_subtract = apply_shaping(flare_subtract, subtract_sin_freq, subtract_pow_exp, subtract_pow_val, 1.0);

          flare = clamp(flare - flare_subtract, 0.0, 10.0);
          flare *= sunmask;

    return flare_color(flare, color, 1.0);
}

// Anamorphic lens edge
vec3 draw_anamorphic_edge(
     
    vec2 scale, float pow_val, float fill, vec2 offset, float pow_exp,
    float sunmask, float edge_mask_x, vec3 color
) {
    vec2 flare_scale = vec2(scale.x *  scale.y);
    vec2 flare_pos = vec2(
        ((1.0 - light_pos.x) * (offset.x + 1.0) - (offset.x * 0.5)) * flare_scale.x,
        ((offset.y == 0.0 ? 1.0 - light_pos.y : light_pos.y) * (offset.y + 1.0) - (offset.y * 0.5)) * flare_scale.y
    );
    
    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
          flare = apply_shaping(flare, 0.0, pow_exp, pow_val, sunmask);
          flare *= edge_mask_x;
    
    return flare_color(flare, color, 1.0);
}

// SMALL SWEEPS
vec3 draw_small_sweep(
     
    float scale, float pow_val, float fill, float offset, float pow_exp,
    float subtract_scale, float subtract_pow_val, float subtract_fill, float subtract_offset, float subtract_pow_exp, float sunmask, vec3 color) {
    vec2 flare_scale = vec2(scale * aspectRatio, scale);
    vec2 flare_pos = get_ghost_pos(offset, flare_scale);
    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
          flare = apply_shaping(flare, half_pi, pow_exp, pow_val, sunmask);

    vec2 flare_subtract_scale = vec2(subtract_scale * aspectRatio, subtract_scale);
    vec2 flare_subtract_pos = get_ghost_pos(subtract_offset, flare_subtract_scale);
    float flare_subtract = get_radial_falloff(flare_subtract_pos, flare_subtract_scale, subtract_fill);
          flare_subtract = apply_shaping(flare_subtract, half_pi, subtract_pow_exp, subtract_pow_val, sunmask);

          flare = clamp(flare - flare_subtract, 0.0, 10.0);

    return flare_color(flare, color, 1.0);
}

// Pointy fuzzy glow dots
vec3 draw_glow_dots(
     
    float scale, float pow_val, float fill, float offset, float pow_exp, float sunmask, vec3 color) {
    vec2 flare_scale = vec2(scale * aspectRatio, scale);
    vec2 flare_pos = get_ghost_pos(offset, flare_scale);
    
    float flare = get_radial_falloff(flare_pos, flare_scale, fill);
    flare = apply_shaping(flare, 0.0, pow_exp, pow_val, sunmask);
    
    return flare_color(flare, color, 1.0);
}

//--------------------MAIN--------------------//

void lens_flare(inout vec3 scene_color) {

// Detect if sun is on edge of screen
float edge_mask_x = 1.0 - clamp(distance(light_pos.x, 0.5f)*9.0f - 4.5f, 0.0f, 1.0f);
float edge_mask_y = 1.0 - clamp(distance(light_pos.y, 0.5f)*9.0f - 4.5f, 0.0f, 1.0f);
float edge_mask = edge_mask_x * edge_mask_y;

const float LF_OCCLUSION_SAMPLES = 16.0;
float total_occlusion = 0.0;
    for (int i = 0; i < LF_OCCLUSION_SAMPLES; i++) {
        // Generate Fibonacci spiral sample pattern at center of the sun/moon
        float r = sqrt(float(i) + 0.5) / sqrt(float(LF_OCCLUSION_SAMPLES));
        float angle = float(i) * golden_angle;
        float sample_radius = 0.02;

        vec2 offset = polar_to_cartesian2(r * sample_radius, angle);
        offset.x /= aspectRatio;

        vec2 checkcoord = light_pos.xy + offset;

        if (checkcoord.x > -0.12 && checkcoord.x < 1.12 && checkcoord.y > -0.12 && checkcoord.y < 1.12) {
            float depth_sample = texture(depthtex0, checkcoord).r;

            #if defined TAA && defined TAAU
                vec2 original_uv = checkcoord * taau_render_scale;
                depth_sample = texture(depthtex0, original_uv).r;
            #else
                depth_sample = texture(depthtex0, checkcoord).r;
            #endif

            #ifdef LOD_MOD_ACTIVE
                float depth_lod = texture(lod_depth_tex, checkcoord).r;
            #else
                float depth_lod = 1.0;
            #endif
            float min_depth = min(depth_sample, depth_lod);
            float terrain_visibility = step(1.0 - eps, min_depth);
        
            float cloud_visibility = 1.0;
            #if defined CLOUDS_CUMULUS || defined CLOUDS_CUMULUS_CONGESTUS || defined CLOUDS_CUMULONIMBUS || defined CLOUDS_ALTOCUMULUS || defined CLOUDS_TOWERING_CUMULUS || defined CLOUDS_THUNDERHEAD || defined CLOUDS_CIRRUS || defined CLOUDS_NOCTILUCENT
                if (terrain_visibility > 0.5) {
                    float cloud_sample = texture(colortex11, checkcoord).g;
                    cloud_visibility = step(cloud_sample, eps);
                }
            #endif

        total_occlusion += terrain_visibility * clamp(cloud_visibility, LF_CLOUD_VISIBILITY, 1.0);
        }
    }
    total_occlusion /= LF_OCCLUSION_SAMPLES;

float sunmask = total_occlusion * cloud_occlusion * edge_mask * float(isEyeInWater <= 0.1 && blindness == 0.0) * (1.0 - rainStrength);

// Determine if it's sun or moon rendering
bool is_moon = sun_vec.z > 0.0;

#ifdef LF_MOONPHASE
    if (is_moon) { // Moon phase influence
        sunmask *= (moon_phase_brightness * 2.0 - 1.0);
    }
#endif

    if (sunmask > 0.02) { // main logic
    // Detect if sun is on edge of screen
    float edge_mask_x = clamp(distance(light_pos.x, 0.5f)*9.0f - 3.0f, 0.0f, 1.0f)*2.0;

    // Darken Colors if the sun is visible
    float center_mask = 1.0 - clamp(distance(light_pos.xy, vec2(0.5, 0.5))*2.0, 0.0, 1.0);
        center_mask = pow(center_mask, 1.0);
        center_mask *= sunmask;

    float perceived_luminance = get_luminance(scene_color);
    float inverse_response = 1.0 - smoothstep(0.1, 0.9, perceived_luminance);
        inverse_response = sqrt(inverse_response) * 2.2;

    vec3 lens_color = vec3(1.0); // Flare color

    // Prevent sun/moon flare visible below the horizon at night/day
    float moon_visibility = clamp(SoU + 0.125, 0.0, 0.125) / 0.125;
    float sun_visibility = 1.0 - moon_visibility;

    #if LENS_FLARE_MODE == 2 // Sun and moon
        if (is_moon) {
            lens_color = get_luminance(lens_color) * vec3(0.02, 0.05, 0.1);
            float lum = get_luminance(lens_color);
            lens_color = mix(lens_color, vec3(lum), 0.75); // 75% desaturation
            lens_color *= sun_visibility;
        } else {
            lens_color = normalize(sqrt(scene_color)) * inverse_response;
            lens_color *= moon_visibility;
        }
    #else // Sun only
        if (is_moon) {
            lens_color = vec3(0.0);
        } else {
            lens_color = normalize(sqrt(scene_color)) * inverse_response;
            lens_color *= moon_visibility;
        }
    #endif

    #ifdef WORLD_END
        lens_color = get_luminance(lens_color) * vec3(0.4, 0.2, 1.0);
    #endif

    lens_color *= vec3(1.0 - center_mask);
    lens_color *= LENS_FLARE_INTENSITY * 0.25;

    #ifdef LENS_DIRT
        vec3 lens_dirt = texture(colortex17, uv).rgb * 1.5;
        lens_color += lens_dirt * LENS_DIRT_LENS_FLARE_INTENSITY;
    #endif

    // Adjust global flare settings
    vec3 flare_tint = lens_color * vec3(LF_COLOR_R, LF_COLOR_G, LF_COLOR_B);

    //float flare_scale_global = mix(1.0, 1.0 * 0.1, (SUN_ANGULAR_RADIUS - 0.1) / (10.0 - 0.1));
    float flare_scale_global = 1.0;
    const float FLARE_SCALE_CONST = 1.0;

    /*
    //Flare gets bigger at center of screen
    flare_scale_global *= (1.0 - center_mask);
    */

    // RAINBOW

    // Lens

    float flare_scale_2 = 1.1;
    float flare_scale_3 = 2.0;
    float flare_scale_4 = 1.5;

    vec3 rainbow_color = vec3(0.0);
    vec3 rainbow2_color = vec3(0.0);

    // Calculate noise stripe pattern for rainbow & close ring
    vec2 uv_from_light = uv - light_pos;
        uv_from_light.x *= aspectRatio;

    float angle = atan(uv_from_light.y, uv_from_light.x);
    float dist = length(uv_from_light);

    vec2 noise_uv = vec2(angle / tau, dist * 0.005);
    float noise_sample = texture(noisetex, noise_uv).b;

    float noise_stripe_pattern = mix(1.0, noise_sample, LF_NOISE_INTENSITY);

    //(1-x)*(0.8)+0.1 = 0.8-0.8x-0.1 = 0.9-0.8x

    #ifdef LF_BIG_RAINBOW
    // Red
        rainbow_color += draw_rainbow_flare(
            0.9 * flare_scale_2, 4.25, 10.0, 0.0,
            0.58 * flare_scale_2, 8.0, 1.4, -0.2,
            sunmask, vec3(0.55, 0.0, 0.0) * flare_tint, noise_stripe_pattern
        );

    // Orange
        rainbow_color += draw_rainbow_flare(
            0.86 * flare_scale_2, 4.25, 10.0, 0.0,
            0.5446 * flare_scale_2, 8.0, 1.4, -0.2,
            sunmask, vec3(0.55, 0.55, 0.0) * flare_tint, noise_stripe_pattern
        );

    // Green
        rainbow_color += draw_rainbow_flare(
            0.82 * flare_scale_2, 4.25, 10.0, -0.0,
            0.5193 * flare_scale_2, 8.0, 1.4, -0.2,
            sunmask, vec3(0.0, 0.55, 0.0) * flare_tint, noise_stripe_pattern
        );

    // Blue
        rainbow_color += draw_rainbow_flare(
            0.78 * flare_scale_2, 4.25, 10.0, 0.0,
            0.4863 * flare_scale_2, 8.0, 1.4, -0.2,
            sunmask, vec3(0.0, 0.0, 0.55) * flare_tint, noise_stripe_pattern
        );

    scene_color += rainbow_color;
    #endif

    #ifdef LF_RAINBOW
    // Rainbow inner layer
    // Red2
        rainbow2_color += draw_rainbow_flare(
            0.9 * flare_scale_3, 4.25, 10.0, -0.0,
            0.58 * flare_scale_3, 8.0, 1.4, -0.2,
            sunmask, vec3(10.0, 0.0, 0.0) * flare_tint, noise_stripe_pattern / 16.0
        );
    // Orange2
        rainbow2_color += draw_rainbow_flare(
            0.86 * flare_scale_3, 4.25, 10.0, -0.0,
            0.5446 * flare_scale_3, 8.0, 1.4, -0.2,
            sunmask, vec3(10.0, 5.0, 0.0) * flare_tint, noise_stripe_pattern / 16.0
        );
    // Green2
        rainbow2_color += draw_rainbow_flare(
            0.82 * flare_scale_3, 4.25, 10.0, -0.0,
            0.5193 * flare_scale_3, 8.0, 1.4, -0.2,
            sunmask, vec3(0.0, 1.0, 0.0) * flare_tint, noise_stripe_pattern / 2.0
        );
    // Blue2
        rainbow2_color += draw_rainbow_flare(
            0.78 * flare_scale_3, 4.25, 10.0, -0.0,
            0.494 * flare_scale_3, 8.0, 1.4, -0.2,
            sunmask, vec3(0.0, 0.0, 1.0) * flare_tint, noise_stripe_pattern / 2.0
        );

    scene_color += (rainbow2_color / 4.0);
    #endif

    // Far blue flare MAIN
    scene_color += draw_far_flare(
        2.0 * flare_scale_global, 0.7, 10.0, -0.5,
        1.4 * flare_scale_global, 1.0, 2.0, -0.65,
        sunmask, vec3(0.5, 0.3, 0.0) * flare_tint, 1.0
    );

    // Far blue flare MAIN 2
    scene_color += draw_far_flare(
        3.2 * flare_scale_global, 1.4, 10.0, 0.0,
        2.1 * flare_scale_global, 2.7, 1.4, -0.05,
        sunmask, vec3(0.5, 0.3, 0.0) * flare_tint, 1.0
    );

    // Far small pink flare
    scene_color += draw_far_flare(
        4.5 * flare_scale_global, 0.3, 3.0, -0.1,
        0.0, 0.0, 1.0, 0.0,
        sunmask, vec3(0.6, 0.0, 0.8) * flare_tint, 1.0
    );

    // Far small pink flare_2
    scene_color += draw_far_flare(
        7.5 * flare_scale_global, 0.4, 2.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        sunmask, vec3(0.4, 0.0, 0.8) * flare_tint, 1.0
    );

    // Far small pink flare3
    scene_color += draw_far_flare(
        37.5 * flare_scale_global, 2.0, 2.0, -0.3,
        0.0, 0.0, 1.0, 0.0,
        sunmask, vec3(0.6, 0.3, 0.1) * flare_tint, 1.0
    );

    // Far small pink flare4
    scene_color += draw_far_flare(
        67.5 * flare_scale_global, 1.0, 2.0, -0.35,
        0.0, 0.0, 1.0, 0.0,
        sunmask, vec3(0.2, 0.2, 0.2) * flare_tint, 1.0
    );

    // Far small pink flare5
    scene_color += draw_far_flare(
        60.5 * flare_scale_global, 1.0, 3.0, -0.3393,
        0.0, 0.0, 1.0, 0.0,
        sunmask, vec3(0.2, 0.2, 0.0) * flare_tint, 1.0
    );

    #ifdef LF_CLOSERING
    // Close ring flare red
    scene_color += draw_close_ring_flare(
        1.0 * flare_scale_global, 0.2, 5.0, -1.9, 1.4, pi,
        sunmask, vec3(0.55, 0.0, 0.0) * flare_tint, noise_stripe_pattern
    );

    // Close ring flare green
    scene_color += draw_close_ring_flare(
        1.1 * flare_scale_global, 0.2, 5.0, -1.9, 1.6, pi,
        sunmask, vec3(0.0, 0.55, 0.0) * flare_tint, noise_stripe_pattern
    );

    // Close ring flare blue
    scene_color += draw_close_ring_flare(
        1.2 * flare_scale_global, 0.2, 5.0, -1.9, 1.8, pi,
        sunmask, vec3(0.0, 0.0, 0.55) * flare_tint, noise_stripe_pattern
    );
    #endif

    #ifdef LF_CENTER_STRIP
    // Anamorphic lens center
    // Edge orange glow
    if (is_moon) {
    } else {
        scene_color += draw_anamorphic_center(
            vec2(0.2 * flare_scale_global, 5.0 * flare_scale_global), 1.4, 2.0, 1.0,
            vec3(1.0, 0.6, 0.0) * flare_tint * sunmask
        );
        #ifdef WORLD_END
        scene_color += draw_anamorphic_center(
            vec2(0.2 * flare_scale_global, 5.0 * flare_scale_global), 1.4, 2.0, 1.0,
            vec3(0.4, 0.2, 0.3) * flare_tint * sunmask
        );
        #endif
    }

    // Center white glow
    vec3 strip_1 = draw_anamorphic_center(
        vec2(0.5 * flare_scale_global, 15.0 * flare_scale_global), 1.6, 2.0, 0.25, vec3(1.0));

    #ifdef WORLD_END
        scene_color.r += strip_1.r * 0.4 * sun_visibility * sunmask;
        scene_color.g += strip_1.g * 0.2 * sun_visibility * sunmask;
        scene_color.b += strip_1.b * 0.3 * sun_visibility * sunmask;
    #endif

    #if !defined WORLD_END && LENS_FLARE_MODE == 2
        if (is_moon) {
            scene_color.r += strip_1.r * 0.12 * sun_visibility * sunmask;
            scene_color.g += strip_1.g * 0.2 * sun_visibility * sunmask;
            scene_color.b += strip_1.b * 0.25 * sun_visibility * sunmask;
        } else {
            scene_color.r += strip_1.r * 0.4 * moon_visibility * sunmask;
            scene_color.g += strip_1.g * 0.35 * moon_visibility * sunmask;
            scene_color.b += strip_1.b * 0.2 * moon_visibility * sunmask;
    }
    #else
        if (is_moon) {
    } else {
            scene_color.r += strip_1.r * 0.4 * moon_visibility * sunmask;
            scene_color.g += strip_1.g * 0.35 * moon_visibility * sunmask;
            scene_color.b += strip_1.b * 0.2 * moon_visibility * sunmask;
    }
    #endif
    #endif

    /*//
    #ifdef LF_XCROSS_STRIP
    // X cross flare
    vec3 x_cross = draw_xcross_flare(
        vec2(1.2 * flare_scale_global, 25.0 * flare_scale_global),
        2.4, 2.0, 0.25, vec3(1.0));

    #ifdef WORLD_END
        scene_color.r += x_cross.r * 0.4 * sunmask;
        scene_color.g += x_cross.g * 0.2 * sunmask;
        scene_color.b += x_cross.b * 0.3 * sunmask;
    #endif

    #if LENS_FLARE_MODE == 2
        if (is_moon) {
            scene_color.r += x_cross.r * 0.12 * sun_visibility * sunmask;
            scene_color.g += x_cross.g * 0.2 * sun_visibility * sunmask;
            scene_color.b += x_cross.b * 0.25 * sun_visibility * sunmask;
        } else {
            scene_color.r += x_cross.r * 0.4 * moon_visibility * sunmask;
            scene_color.g += x_cross.g * 0.35 * moon_visibility * sunmask;
            scene_color.b += x_cross.b * 0.2 * moon_visibility * sunmask;
    }
    #else
        if (is_moon) {
        } else {
            scene_color.r += x_cross.r * 0.4 * moon_visibility * sunmask;
            scene_color.g += x_cross.g * 0.35 * moon_visibility * sunmask;
            scene_color.b += x_cross.b * 0.2 * moon_visibility * sunmask;
    }
    #endif
    #endif
    //*/

    // Mid orange sweep
    scene_color += draw_mid_orange_sweep(
        32.0 * flare_scale_global, 2.5, 1.1, -1.3, 1.1, half_pi,
        5.1 * flare_scale_global, 1.5, 1.0, -0.77, 0.9, half_pi,
        sunmask, vec3(0.5, 0.4, 0.1) * flare_tint);

    scene_color += draw_mid_orange_sweep(
        35.0 * flare_scale_global, 1.0, 1.1, -1.2, 1.1, half_pi,
        5.1 * flare_scale_global, 1.5, 1.0, -0.77, 0.9, half_pi,
        sunmask, vec3(0.6, 0.4, 0.1) * flare_tint);

    scene_color += draw_mid_orange_sweep(
        25.0 * flare_scale_global, 4.0, 1.1, -0.9, 1.1, half_pi,
        5.1 * flare_scale_global, 1.5, 1.0, -0.77, 0.9, half_pi,
        sunmask, vec3(0.5, 0.3, 0.0) * flare_tint);

    #ifdef LF_EDGE_STRIP
    // Anamorphic flare edge
    // Edge blue strip 1
    scene_color += draw_anamorphic_edge(
        vec2(0.3 * flare_scale_global, 40.5 * flare_scale_global), 0.5, 12.0, vec2(1.0, 1.0), 1.4,
        sunmask, edge_mask_x, vec3(0.0, 0.15, 0.4) * flare_tint);

    // Edge blue strip 2
    scene_color += draw_anamorphic_edge(
        vec2(0.2 * flare_scale_global, 5.5 * flare_scale_global), 1.9, 2.0, vec2(1.0, 0.0), 1.4,
        sunmask, edge_mask_x, vec3(0.1, 0.2, 0.45) * flare_tint);
    #endif

    // SMALL SWEEPS
    // Mid orange sweep
    scene_color += draw_small_sweep(
        6.0 * flare_scale_global, 1.9, 1.1, -0.7, 1.1,
        5.1 * flare_scale_global, 1.5, 1.0, -0.77, 0.9,
        sunmask, vec3(0.5, 0.3, 0.0) * flare_tint);

    // Mid blue sweep
    scene_color += draw_small_sweep(
        6.0 * flare_scale_global, 1.9, 1.1, -0.6, 1.1,
        5.1 * flare_scale_global, 1.5, 1.0, -0.67, 0.9,
        sunmask, vec3(0.5, 0.3, 0.0) * flare_tint);

    #ifdef LF_GLOWDOTS
    // Pointy fuzzy glow dots
    // RedGlow1
    scene_color += draw_glow_dots(
        1.5 * flare_scale_global, 1.1, 2.0, -0.523, 2.9,
        sunmask, vec3(0.5, 0.1, 0.0) * flare_tint);

    // PurpleGlow2
    scene_color += draw_glow_dots(
        2.5 * flare_scale_global, 0.5, 2.0, -0.323, 2.9,
        sunmask, vec3(0.35, 0.15, 0.0) * flare_tint);

    // BlueGlow3
    scene_color += draw_glow_dots(
        1.0 * flare_scale_global, 1.5, 2.0, 0.138, 2.9,
        sunmask, vec3(0.5, 0.3, 0.0) * flare_tint);
    #endif
   }
}
