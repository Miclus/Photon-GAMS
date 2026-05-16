#if !defined INCLUDE_SKY_CLOUDS_COMMON
#define INCLUDE_SKY_CLOUDS_COMMON

#include "/include/sky/atmosphere.glsl"
#include "/include/sky/clouds/constants.glsl"
#include "/include/misc/lightning_flash.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/geometry.glsl"
#include "/include/utility/phase_functions.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/sampling.glsl"

// #define TERRAIN_SHADOWS_ON_CLOUDS

#ifdef TERRAIN_SHADOWS_ON_CLOUDS
#include "/include/lighting/shadows/sampling.glsl"
#endif

#if defined COLORED_LIGHTS && defined COLORED_LIGHTS_CLOUDS
#include "/include/lighting/lpv/blocklight.glsl"
#endif

uniform float day_factor;

// ----

struct CloudsResult {
    vec4 scattering; // w = ambient scattering, for lightning flashes
    float transmittance;
    float apparent_distance;
    float lightning_intensity;
};

const CloudsResult clouds_not_hit = CloudsResult(vec4(0.0), 1.0, 1e5, 0.0);

// ----

// from https://iquilezles.org/articles/gradientnoise/
vec2 perlin_gradient(vec2 coord) {
    vec2 i = floor(coord);
    vec2 f = fract(coord);

    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    vec2 g0 = hash2(i + vec2(0.0, 0.0));
    vec2 g1 = hash2(i + vec2(1.0, 0.0));
    vec2 g2 = hash2(i + vec2(0.0, 1.0));
    vec2 g3 = hash2(i + vec2(1.0, 1.0));

    float v0 = dot(g0, f - vec2(0.0, 0.0));
    float v1 = dot(g1, f - vec2(1.0, 0.0));
    float v2 = dot(g2, f - vec2(0.0, 1.0));
    float v3 = dot(g3, f - vec2(1.0, 1.0));

    return vec2(
        g0 + u.x * (g1 - g0) + u.y * (g2 - g0) + u.x * u.y * (g0 - g1 - g2 + g3)
        + // d/dx
        du * (u.yx * (v0 - v1 - v2 + v3) + vec2(v1, v2) - v0) // d/dy
    );
}

vec2 curl2D(vec2 coord) {
    vec2 gradient = perlin_gradient(coord);
    return vec2(gradient.y, -gradient.x);
}

float clouds_phase_single(float cos_theta) { // Single scattering phase function
    float forwards_a = klein_nishina_phase(
        cos_theta,
        2600.0
    ); // this gives a nice glow very close to the sun
    float forwards_b = henyey_greenstein_phase(cos_theta, 0.8);

    return 0.8
        * max(forwards_a,
              forwards_b) // forwards lobe (max'ing them is completely
                          // nonsensical but it looks nice)
        + 0.2 * henyey_greenstein_phase(cos_theta, -0.2); // backwards lobe
}

float clouds_phase_multi(
    float cos_theta,
    vec3 g
) { // Multiple scattering phase function
    return 0.65 * henyey_greenstein_phase(cos_theta, g.x) // forwards lobe
        + 0.10 * henyey_greenstein_phase(cos_theta, g.y) // forwards peak
        + 0.25 * henyey_greenstein_phase(cos_theta, -g.z); // backwards lobe
}

float clouds_powder_effect(float density, float cos_theta) {
    float powder = pi * density / (density + 0.15);
    powder = mix(powder, 1.0, 0.8 * sqr(cos_theta * 0.5 + 0.5));

    return powder;
}

// 0 outside the shell, ~1 near the middle of the layer (camera deep inside
// cloud volume)
float clouds_shell_immersion(
    vec3 air_viewer_pos,
    float inner_radius,
    float outer_radius
) {
    float r = length(air_viewer_pos);
    if (r <= inner_radius || r >= outer_radius) {
        return 0.0;
    }

    float mid = 0.5 * (inner_radius + outer_radius);
    float half_range = 0.5 * (outer_radius - inner_radius);
    float t = 1.0 - abs(r - mid) / max(half_range, 1.0);

    return sqr(clamp01(t));
}

// Extra primary steps when the viewer sits inside the layer (shorter
// world-space steps near the eye, less fog banding)
uint clouds_boost_steps_inside_shell(
    uint steps,
    vec3 air_viewer_pos,
    float inner_radius,
    float outer_radius
) {
    float r = length(air_viewer_pos);
    if (r <= inner_radius || r >= outer_radius) {
        return steps;
    }

    uint added = max(steps >> 1, 8u);
    added = min(added, 48u);
    return steps + added;
}

float clouds_immersed_fog_factor(float clouds_transmittance, float immersion) {
    float immersion_weight = cubic_smooth(linear_step(0.15, 0.75, immersion));
    float dense_weight = cubic_smooth(linear_step(0.95, 0.25, clouds_transmittance));

    return immersion_weight * dense_weight;
}

float clouds_stabilize_immersed_transmittance(
    float clouds_transmittance,
    float immersion
) {
    float fog_factor
        = clouds_immersed_fog_factor(clouds_transmittance, immersion);

    return mix(clouds_transmittance, 0.0, 0.92 * fog_factor);
}

vec3 clouds_aerial_perspective_immersed(
    vec3 clouds_scattering,
    float clouds_transmittance,
    float distance_to_terrain,
    vec3 ray_origin,
    vec3 ray_end,
    vec3 ray_dir,
    vec3 clear_sky,
    float immersion
) {
    vec3 air_transmittance;

    // if (distance_to_terrain >= 0.0) return clouds_scattering; //ray_end =
    // ray_origin + distance_to_terrain;

#if CLOUDS_AERIAL_PERSPECTIVE_BOOST != 0
    ray_end
        = mix(ray_origin, ray_end, float(1 << CLOUDS_AERIAL_PERSPECTIVE_BOOST));
#endif // CLOUDS_AERIAL_PERSPECTIVE_BOOST

    if (length_squared(ray_origin) < length_squared(ray_end)) {
        vec3 trans_0 = atmosphere_transmittance(ray_origin, ray_dir);
        vec3 trans_1 = atmosphere_transmittance(ray_end, ray_dir);

        air_transmittance = clamp01(trans_0 / trans_1);
    } else {
        vec3 trans_0 = atmosphere_transmittance(ray_origin, -ray_dir);
        vec3 trans_1 = atmosphere_transmittance(ray_end, -ray_dir);

        air_transmittance = clamp01(trans_1 / trans_0);
    }

    // Blend to rain color during rain
    clear_sky = mix(
        clear_sky,
        sky_color * rcp(tau),
        rainStrength * mix(1.0, 0.9, time_sunrise + time_sunset)
    );
    air_transmittance
        = mix(air_transmittance, vec3(air_transmittance.x), 0.8 * rainStrength);

    float imm = clamp01(immersion);
    float clear_sky_weight = mix(1.0, 0.36, imm);
    float fog_factor
        = clouds_immersed_fog_factor(clouds_transmittance, imm);
    vec3 fog_fill
        = (1.0 - clouds_transmittance) * clear_sky * clear_sky_weight;

    vec3 result = mix(
        fog_fill,
        clouds_scattering,
        air_transmittance
    );

    return mix(result, fog_fill, 0.7 * fog_factor);
}

vec3 clouds_aerial_perspective(
    vec3 clouds_scattering,
    float clouds_transmittance,
    float distance_to_terrain,
    vec3 ray_origin,
    vec3 ray_end,
    vec3 ray_dir,
    vec3 clear_sky
) {
    return clouds_aerial_perspective_immersed(
        clouds_scattering,
        clouds_transmittance,
        distance_to_terrain,
        ray_origin,
        ray_end,
        ray_dir,
        clear_sky,
        0.0
    );
}

CloudsResult blend_layers(CloudsResult old, CloudsResult new, uint iter) {
    if (iter < 1u) {
        return new;
    }

    bool new_in_front = new.apparent_distance < old.apparent_distance;

    vec4 scattering_behind = new_in_front ? old.scattering : new.scattering;
    vec4 scattering_in_front = new_in_front ? new.scattering : old.scattering;
    float transmittance_in_front
        = new_in_front ? new.transmittance : old.transmittance;

    float lightning_behind
        = new_in_front ? old.lightning_intensity : new.lightning_intensity;
    float lightning_in_front
        = new_in_front ? new.lightning_intensity : old.lightning_intensity;

    return CloudsResult(
        scattering_in_front + transmittance_in_front * scattering_behind,
        old.transmittance * new.transmittance,
        min(old.apparent_distance, new.apparent_distance),
        lightning_in_front + transmittance_in_front * lightning_behind
    );
}

#endif // INCLUDE_SKY_CLOUDS_COMMON
