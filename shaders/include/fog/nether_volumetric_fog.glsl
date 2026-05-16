#ifndef INCLUDE_FOG_NETHER_VOLUMETRIC_FOG
#define INCLUDE_FOG_NETHER_VOLUMETRIC_FOG

#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/phase_functions.glsl"

// Nether Fog by Daytendo

#ifdef NETHER_USE_BIOME_COLOR
uniform vec3 fogColor;
#endif

float nether_volumetric_density(vec3 world_pos) {
    vec3 wind = vec3(0.41, 0.07, 0.29) * NETHER_VL_FOG_SPEED * frameTimeCounter;
    vec3 wind_slow = wind * 0.32;
    float sc = NETHER_VL_FOG_SCALE;
    vec3 p = world_pos / (sc * 3);

    // Large-scale patches: slower wind so banks drift as coherent blobs
    float patch_a = texture(colortex0, p * 0.0036 + wind_slow + vec3(103.0, 17.0, 61.0)).x;
    float patch_b = texture(colortex0, p * 0.0075 + wind_slow * 1.05 + vec3(37.0, 201.0, 9.0)).x;
    float patches = 0.52 * patch_a + 0.48 * patch_b;
    float patch_mask = smoothstep(0.14, 0.68, patches);
    patch_mask *= patch_mask;
    float patchiness = mix(0.0, 0.4, patch_mask);

    float n0 = texture(colortex0, p * 0.017 + wind).x;
    float n1 = texture(colortex0, p * 0.052 + wind * 1.31 + vec3(13.7, 4.2, 21.0)).x;
    float n2 = texture(colortex0, p * 0.11 + wind * 0.58 + vec3(51.0, 9.0, 3.0)).x;

    // Slightly tighter smoothstep + mild pow => puffier, less uniform billows
    float billows = smoothstep(0.26, 0.88, n0);
    billows = pow(billows, 1.12);
    float detail = 0.4 * n1 + 0.22 * n2;
    float d = billows * (0.45 + 0.55 * detail);
    d = d * d;
    d = mix(0.07, d, 0.93);
    d *= patchiness;

    return d * NETHER_VL_FOG_DENSITY * 0.24;
}

vec3 nether_volumetric_fog_tint() {
#ifdef NETHER_USE_BIOME_COLOR
    vec3 biome_srgb = clamp(fogColor, vec3(0.0), vec3(1.0));
    float blue_biome = smoothstep(0.02, 0.18, biome_srgb.b - max(biome_srgb.r, biome_srgb.g));

    vec3 orange_srgb = vec3(1.0, 0.45, 0.0);
    vec3 blue_srgb = vec3(0.0, 0.0, 1.0);
    vec3 warm_srgb = mix(biome_srgb, orange_srgb, 0.85);
    vec3 cool_srgb = mix(biome_srgb, blue_srgb, 0.75);
    vec3 fog_srgb = mix(warm_srgb, cool_srgb, blue_biome);
    fog_srgb = mix(vec3(1.0), fog_srgb, NETHER_S);

    return srgb_eotf_inv(fog_srgb) * rec709_to_rec2020;
#else
    return from_srgb(vec3(NETHER_R, NETHER_G, NETHER_B));
#endif
}

mat2x3 raymarch_nether_volumetric_fog(
    vec3 world_start_pos,
    vec3 world_end_pos,
    float dither
) {
    vec3 world_dir = world_end_pos - world_start_pos;
    float ray_length;
    length_normalize(world_dir, world_dir, ray_length);

    ray_length = min(ray_length, far);

    if (ray_length < eps) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    const uint min_steps = 14u;
    const uint max_steps = 32u;
    const float growth = 0.13;

    uint step_count = uint(float(min_steps) + growth * ray_length);
    step_count = clamp(step_count, min_steps, max_steps);

    float step_length = ray_length * rcp(float(step_count));
    vec3 world_step = world_dir * step_length;

    vec3 world_pos = world_start_pos + world_dir * (step_length * dither);

    vec3 nether_tint = nether_volumetric_fog_tint();

    float LoV = dot(world_dir, light_dir);
    float mie_phase = henyey_greenstein_phase(LoV, 0.42);

    vec3 scattering = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    for (uint i = 0u; i < step_count; ++i) {
        float density = nether_volumetric_density(world_pos);

        vec3 sigma_s = vec3(density);
        vec3 sigma_a = density * vec3(0.24, 0.19, 0.15);
        vec3 extinction = sigma_a + sigma_s;

        vec3 step_optical_depth = extinction * step_length;
        vec3 step_transmittance = exp(-step_optical_depth);
        vec3 step_transmitted_fraction
            = (1.0 - step_transmittance) / max(step_optical_depth, vec3(eps));

        vec3 visible_scattering = step_transmitted_fraction * transmittance;

        vec3 fog_color = nether_tint;

        vec3 S = fog_color * sigma_s
            * (light_color * mie_phase + ambient_color * isotropic_phase * 300.0);

        scattering += S * visible_scattering * step_length;
        transmittance *= step_transmittance;

        world_pos += world_step;
    }

    scattering *= 3.0;
    transmittance = pow(transmittance, vec3(0.84));

    return mat2x3(scattering, transmittance);
}

#endif

// Nether Smoke by CChex

#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

mat2x3 raymarch_nether_volumetric_smoke(vec3 world_start_pos, vec3 world_end_pos, float dither) {
    vec3 vl_scattering    = vec3(0.0);
    vec3 vl_transmittance = vec3(1.0);

    const int steps = 24;
    const float col_intensity = 5.0;
    const float smoke_spatial_scale = NETHER_VL_FOG_SCALE;

    const mat3  rot      = mat3(0.81,-0.46,0.36, 0.44,0.88,0.18, -0.39,0.02,0.92);
    vec3 col = ambient_color * col_intensity;

    vec3  ray_step   = (world_end_pos - world_start_pos) / float(steps);
    vec3  cur        = world_start_pos + ray_step * r1(frameCounter, dither);
    
    for (int i = 0; i < steps; i++, cur += ray_step) {
        float vertical_fade = smoothstep(115.0, 85.0, cur.y);
        float dist_sq       = dot(cur - world_start_pos, cur - world_start_pos);
        float dist_mask     = smoothstep(76.0, 400.0, dist_sq);

        vec2 warp = texture(noisetex, cur.xz * (0.01 / smoke_spatial_scale) + frameTimeCounter * (NETHER_VL_FOG_SPEED / 10)).rg * 2.0;
        vec3 tp   = rot * (cur / smoke_spatial_scale + vec3(warp.x, 0.0, warp.y) * 5.0);

        float n1        = texture(noisetex, tp.xz * vec2(0.01,  0.005) + frameTimeCounter * 0.01).r;
        float n2        = texture(noisetex, tp.zy * vec2(0.015, 0.008) - frameTimeCounter * 0.01).r;
        float detail    = texture(noisetex, tp.xz * 0.1).r;
        float noise     = smoothstep(0.18, 0.45, abs(n1 - n2)) * mix(0.7, 1.3, detail);

        float density   = noise * 0.096 * dist_mask * vertical_fade; // 0.08*1.2 = 0.096

        vec3  sview     = scene_to_view_space(cur - cameraPosition);
        vec3  sclip     = project_and_divide(gbufferProjection, sview);
        vec2  suv       = sclip.xy * 0.5 + 0.5;

        if (all(greaterThanEqual(suv, vec2(0.0))) && all(lessThanEqual(suv, vec2(1.0))))
            density *= smoothstep(-0.8, 0.8, (sclip.z * 0.5 + 0.5) - texture(depthtex0, suv).r) * (NETHER_VL_FOG_DENSITY * 0.5);

        vec3 color = col * mix(0.8, 1.2, n1);
        vl_scattering  += color * density * vl_transmittance;
        vl_transmittance *= 1.0 - density;
    }

    return mat2x3(vl_scattering, vl_transmittance);
}