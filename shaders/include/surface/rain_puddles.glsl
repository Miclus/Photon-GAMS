#if !defined INCLUDE_MISC_RAIN_PUDDLES
#define INCLUDE_MISC_RAIN_PUDDLES

#include "/include/misc/material_masks.glsl"

float get_ripple_height(vec2 coord) {
    const float ripple_frequency = 0.3;
    const float ripple_speed = 0.1;
    const vec2 ripple_dir_0 = vec2(3.0, 4.0) / 5.0;
    const vec2 ripple_dir_1 = vec2(-5.0, -12.0) / 13.0;

    float ripple_noise_1
        = texture(
              noisetex,
              coord * ripple_frequency
                  + frameTimeCounter * ripple_speed * ripple_dir_0
        )
              .y;
    float ripple_noise_2
        = texture(
              noisetex,
              coord * ripple_frequency
                  + frameTimeCounter * ripple_speed * ripple_dir_1
        )
              .y;

    return mix(ripple_noise_1, ripple_noise_2, 0.5);
}

float get_puddle_noise(vec3 world_pos, vec3 flat_normal, vec2 light_levels) {
    // Removed the hard 'if (biome_may_rain < 0.5)' check to prevent snapping

    const float puddle_frequency = 0.025;

    const float fade_in_curve  = 1;
    const float fade_out_curve = 0.175; 

    float current_curve = mix(fade_out_curve, fade_in_curve, rainStrength);
    
    float smooth_wetness = pow(wetness, current_curve);
    smooth_wetness = smoothstep(0.05, 1.0, smooth_wetness);

    // Apply the biome fade AFTER the smoothstep so it scales from 0.0 to 1.0 
    // instead of jumping to 5% instantly.
    smooth_wetness *= smoothstep(0.0, 1.0, biome_may_rain);

    float puddle_noise  = texture(noisetex, world_pos.xz * puddle_frequency).w;
    
    float lower_bound   = mix(1.0, 0.45, smooth_wetness);
    float upper_bound   = lower_bound + 0.1;

    float puddle = linear_step(lower_bound, upper_bound, puddle_noise)
                 * step(0.99, flat_normal.y);

    // Prevent puddles from appearing indoors
    puddle *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    return puddle;
}

bool get_rain_puddles(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 light_levels,
    float porosity,
    uint material_mask,
    inout vec3 normal,
    inout vec3 albedo,
    inout vec3 f0,
    inout float roughness,
    inout float ssr_multiplier
) {
#ifndef RAIN_PUDDLES
    return false;
#endif

    const float puddle_f0 = 0.02;
    const float puddle_roughness = 0.002;
    const float puddle_darkening_factor = 0.33;
    const float puddle_darkening_factor_porous = 0.67;

    if (wetness < 0.0 || biome_may_rain < 0.0) {
        return false;
    }

    float puddle = get_puddle_noise(world_pos, flat_normal, light_levels);

    if (puddle < eps) {
        return false;
    }

    // Puddle darkening
    albedo *= 1.0 - puddle_darkening_factor_porous * porosity * puddle;
    puddle *= 1.0 - porosity;
    albedo *= 1.0 - puddle_darkening_factor * puddle;

    // Replace material with puddle material
    f0 = max(f0, mix(f0, vec3(puddle_f0), puddle));
    roughness = puddle_roughness * rainStrength;
    ssr_multiplier = max(ssr_multiplier, puddle);

    // Ripple animation
    const float h = 0.1;
    float ripple0 = get_ripple_height(world_pos.xz);
    float ripple1 = get_ripple_height(world_pos.xz + vec2(h, 0.0));
    float ripple2 = get_ripple_height(world_pos.xz + vec2(0.0, h));

    vec3 ripple_normal = vec3(ripple1 - ripple0, ripple2 - ripple0, h);
    ripple_normal.xy
        *= 0.05
        * smoothstep(
               0.0,
               0.1,
               abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
        );
    ripple_normal = normalize(ripple_normal);
    ripple_normal = ripple_normal.xzy; // convert to world space

    normal = mix(normal, flat_normal, puddle);
    normal = mix(normal, ripple_normal, puddle * rainStrength);
    normal = normalize_safe(normal);

    return true;
}

#endif // INCLUDE_MISC_RAIN_PUDDLES
