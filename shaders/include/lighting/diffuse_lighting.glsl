#if !defined INCLUDE_LIGHTING_DIFFUSE_LIGHTING
#define INCLUDE_LIGHTING_DIFFUSE_LIGHTING

#include "/include/lighting/bsdf.glsl"
#include "/include/lighting/colors/blocklight_color.glsl"
#include "/include/misc/end_lighting_fix.glsl"
#include "/include/misc/lightning_flash.glsl"
#include "/include/surface/material.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/phase_functions.glsl"
#include "/include/utility/random.glsl"
#ifdef MC_GL_RENDERER_INTEL
#include "/include/utility/spherical_harmonics_fallback.glsl"
#else
#include "/include/utility/spherical_harmonics.glsl"
#endif

#ifdef DIRECTIONAL_LIGHTMAPS
#include "/include/lighting/directional_lightmaps.glsl"
#endif

#ifdef COLORED_LIGHTS
#include "/include/lighting/lpv/blocklight.glsl"
#endif

#ifdef HANDHELD_LIGHTING
#include "/include/lighting/handheld_lighting.glsl"
#endif

#if !defined WORLD_OVERWORLD
#undef CLOUD_SHADOWS
#endif

#if defined PHOTONICS_DIFFUSE
#include "/photonics/ph_samplers.glsl"

#ifndef PHOTONICS_RESTIR_COMBINED_GI
uniform sampler2D radiosity_indirect;
#endif

#endif

const float sss_density = 14.0 * SSS_DENSITY;
const float sss_scale = 5.0 * SSS_INTENSITY;
const float night_vision_scale = 1.5 * NIGHT_VISION_I;
float metal_diffuse_amount = 1.0
    * METAL_DIFFUSE; // Scales diffuse lighting on metals, ideally this would be
                     // zero but purely specular metals don't play well with SSR

float get_blocklight_falloff(float blocklight, float skylight, float ao) {
    float falloff = pow8(blocklight) + 0.18 * sqr(blocklight)
        + 0.16 * dampen(blocklight); // Base falloff
    falloff *= mix(
        cube(ao),
        1.0,
        clamp01(falloff)
    ); // Stronger AO further from the light source
    falloff *= mix(
        1.0,
        ao * dampen(abs(cos(2.0 * frameTimeCounter))) * 0.67 + 0.2,
        darknessFactor
    ); // Pulsing blocklight with darkness effect
    falloff *= 1.0 - 0.2 * time_noon * skylight
        - 0.2 * skylight; // Reduce blocklight intensity in daylight
    falloff += min(
        2.7 * pow12(blocklight),
        2.9
    ); // Strong highlight around the light source, visible even in the daylight
    falloff *= smoothstep(
        0.0,
        0.125,
        blocklight
    ); // Ease transition at edge of lightmap

    return falloff;
}

float get_skylight_falloff(float skylight) {
#if defined WORLD_OVERWORLD
    return sqr(skylight);
#else
    return 1.0;
#endif
}

#if defined WORLD_END && defined END_STORM_FOG_LIGHTNING_ENABLE
vec3 end_storm_flash_point_lighting(
    vec3 scene_pos,
    vec3 normal,
    vec3 flat_normal,
    float ao
) {
    vec3 world_pos = scene_pos + cameraPosition;

    const float vol_top = END_STORM_FOG_CEILING_Y;
    const float vol_bot = END_STORM_FOG_FLOOR_Y;
    const float cell_size = max(5200.0, END_STORM_FOG_SPACING * 3.5);

    vec3 flash_space = world_pos;
    flash_space.xz += vec2(0.048, 0.036) * END_STORM_FOG_SPEED * frameTimeCounter;

    vec2 grid_pos = flash_space.xz / cell_size;
    vec2 cell_id = floor(grid_pos);

    float flash_speed = max(END_STORM_FOG_LIGHTNING_SPEED, 0.05);
    float total_light = 0.0;
    vec3 total_dir = vec3(0.0);

    for (int xi = -1; xi <= 1; ++xi) {
        for (int zi = -1; zi <= 1; ++zi) {
            vec2 current_cell = cell_id + vec2(xi, zi);

            const float block_duration = 0.5;
            float t = frameTimeCounter * flash_speed / block_duration;
            float t_floor = floor(t);
            vec4 hash = hash4(vec3(current_cell, t_floor));

            if (hash.w > END_STORM_FOG_LIGHTNING_FREQUENCY) {
                continue;
            }

            float start_offset = hash.x * 0.1;
            float duration = (0.2 + hash.y * 0.5) / block_duration;
            float local_time = fract(t) * block_duration;
            float start_time = start_offset * block_duration;

            if (local_time < start_time || local_time > start_time + duration) {
                continue;
            }

            vec2 cell_origin = current_cell * cell_size;
            vec2 pos_seed = fract(hash.xy * 12.3 + hash.zw * 45.6);
            vec2 center_xz = cell_origin + pos_seed * cell_size;

            float height_span = max(vol_top - vol_bot, 1.0);
            float center_y = vol_bot + height_span * (0.03 + 0.94 * hash.z);

            vec3 to_light = vec3(center_xz.x - flash_space.x, center_y - world_pos.y, center_xz.y - flash_space.z);
            float dist_sq = dot(to_light, to_light * vec3(1.0, 0.49, 1.0));
            float radius = 280.0 + hash.x * 1200.0;

            if (dist_sq > radius * radius) {
                continue;
            }

            float dist = sqrt(dist_sq);
            float falloff = smoothstep(radius, 0.0, dist);
            falloff = sqr(falloff);

            float flash_progress = (local_time - start_time) / duration;
            int type = int(fract(hash.x * 10.0 + hash.y * 20.0) * 6.0);
            float intensity = 0.0;
            float p = flash_progress;

            if (type == 0) {
                float flicker = noise_1d(frameTimeCounter * 80.0 * flash_speed + hash.w * 100.0);
                intensity = sin(p * pi) * (0.6 + 0.4 * flicker);
            } else if (type == 1) {
                float p1 = smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.3, 0.4, p));
                float p2 = smoothstep(0.5, 0.6, p) * (1.0 - smoothstep(0.9, 1.0, p));
                float flicker = noise_1d(frameTimeCounter * 120.0 * flash_speed);
                intensity = (p1 + p2) * (0.8 + 0.2 * flicker);
            } else if (type == 2) {
                float flicker = noise_1d(frameTimeCounter * 40.0 * flash_speed);
                intensity = smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.8, 1.0, p));
                intensity *= 0.5 + 0.5 * flicker;
            } else if (type == 3) {
                float p1 = smoothstep(0.0, 0.05, p) * (1.0 - smoothstep(0.15, 0.2, p));
                float p2 = smoothstep(0.3, 0.35, p) * (1.0 - smoothstep(0.45, 0.5, p));
                float p3 = smoothstep(0.6, 0.65, p) * (1.0 - smoothstep(0.75, 0.8, p));
                intensity = (p1 + p2 + p3) * (0.9 + 0.1 * noise_1d(frameTimeCounter * 150.0 * flash_speed));
            } else if (type == 4) {
                float flicker = noise_1d(frameTimeCounter * 200.0 * flash_speed + hash.y * 50.0);
                float envelope = smoothstep(0.0, 0.2, p) * (1.0 - smoothstep(0.4, 0.9, p));
                intensity = step(0.5, flicker) * envelope;
            } else {
                float flicker = noise_1d(frameTimeCounter * 60.0 * flash_speed);
                float envelope = pow(p, 3.0) * (1.0 - smoothstep(0.8, 1.0, p));
                intensity = envelope * (0.7 + 0.3 * flicker) * 2.0;
            }

            float contrib = falloff * intensity;
            total_light += contrib;
            total_dir += normalize_safe(to_light) * contrib;
        }
    }

    if (total_light <= 0.0) {
        return vec3(0.0);
    }

    vec3 flash_dir = normalize_safe(total_dir);
    float wrapped_lambert = clamp01(dot(normal, flash_dir) * 0.7 + 0.3);
    float face_visibility = 0.6 + 0.4 * abs(dot(flat_normal, flash_dir));
    vec3 flash_rgb = vec3(
            END_STORM_FOG_LIGHTNING_COLOR_R,
            END_STORM_FOG_LIGHTNING_COLOR_G,
            END_STORM_FOG_LIGHTNING_COLOR_B
        )
        * END_STORM_FOG_LIGHTNING_INTENSITY;

    return flash_rgb * total_light * wrapped_lambert * face_visibility * mix(0.45, 1.0, ao) * 0.5;
}
#endif

#ifdef SHADOW_VPS
vec3 sss_approx(
    vec3 albedo,
    float sss_amount,
    float sheen_amount,
    float sss_depth,
    float LoV,
    float shadow
) {
    // Transmittance-based SSS
    if (sss_amount < eps) {
        return vec3(0.0);
    }

    vec3 coeff = albedo * inversesqrt(dot(albedo, luminance_weights) + eps);
    coeff = 0.75 * clamp01(coeff);
    coeff = (1.0 - coeff) * sss_density / sss_amount;

    float phase
        = mix(isotropic_phase, henyey_greenstein_phase(-LoV, 0.7), 0.33);

    vec3 sss = sss_scale * phase * exp2(-coeff * sss_depth) * dampen(sss_amount)
        * pi;

#ifdef SSS_SHEEN
    vec3 sheen = (0.8 * SSS_INTENSITY) * rcp(albedo + eps)
        * exp2(-1.0 * coeff * sss_depth) * henyey_greenstein_phase(-LoV, 0.5)
        * linear_step(-0.8, -0.2, -LoV);
    sss += sheen * sheen_amount;
#endif

    return sss;
}
#else
vec3 sss_approx(
    vec3 albedo,
    float sss_amount,
    float sheen_amount,
    float sss_depth,
    float LoV,
    float shadow
) {
    // Blur-based SSS
    float sss = 0.06 * sss_scale * pi;
    vec3 sheen = 0.8 * rcp(albedo + eps) * henyey_greenstein_phase(-LoV, 0.5)
        * linear_step(-0.8, -0.2, -LoV) * shadow;

    return sss + sheen * sheen_amount;
}
#endif

vec3 get_block_lighting(
    vec3 scene_pos,
    vec3 normal,
    vec3 flat_normal,
    vec2 light_levels,
    float ao,
    float directional_lighting,
    Material material
) {
    vec3 lighting = vec3(0.0);

    float blocklight_falloff
        = get_blocklight_falloff(light_levels.x, light_levels.y, ao);
    vec3 mc_blocklight = (blocklight_falloff * directional_lighting)
        * (blocklight_scale * blocklight_color);

#ifdef COLORED_LIGHTS
    lighting += get_lpv_blocklight(
        scene_pos,
        normal,
        flat_normal,
        mc_blocklight,
        ao * directional_lighting,
        material
    );
#else
    lighting += mc_blocklight;
#endif

#ifdef HANDHELD_LIGHTING
    vec3 handheld_lighting_pos = scene_pos;
#ifdef DIRECTIONAL_LIGHTMAPS
    vec3 normal_diff = normal - flat_normal;
    normal_diff
        += sqrt(
               1.0
               - clamp01(dot(normalize(normal_diff), normalize(flat_normal)))
           )
        * normal_diff * 4.0;
    handheld_lighting_pos += normal_diff + flat_normal * 0.5;
#else
    handheld_lighting_pos += flat_normal * 0.5;
#endif

    vec3 handheld_lighting = get_handheld_lighting(handheld_lighting_pos, ao);
#if defined(DIRECTIONAL_LIGHTMAPS) && DIRECTIONAL_LIGHTMAPS_INTENSITY > 0.0
// handheld_lighting *= get_directional_lpv(normal, scene_pos,
// handheld_lighting);
#endif
    lighting += handheld_lighting;
#endif

    return lighting;
}

vec3 get_sky_lighting(
    Material material,
    vec3 bent_normal,
    vec2 light_levels,
    float ao,
    float ambient_sss,
    float directional_lighting
) {
    vec3 lighting = vec3(0.0);

#if defined WORLD_OVERWORLD && defined PROGRAM_DEFERRED4 && defined SH_SKYLIGHT
#ifdef MC_GL_RENDERER_INTEL
    sh3 sky_sh_compat;
    for (uint band = 0u; band < 3u; ++band) {
        sky_sh_compat.f1[band] = sky_sh[band];
        sky_sh_compat.f2[band] = sky_sh[band + 3u];
        sky_sh_compat.f3[band] = sky_sh[band + 6u];
    }
    vec3 skylight = sh_evaluate_irradiance(sky_sh_compat, bent_normal, ao);
#else
    vec3 skylight = sh_evaluate_irradiance(sky_sh, bent_normal, ao);
#endif
    skylight = mix(skylight_up, skylight, sqr(light_levels.y));
#else
    vec3 skylight = ambient_color * ao;
    vec3 skylight_up = skylight;
#endif

    skylight = mix(skylight, 0.5 * skylight_up * ao, material.sss_amount);
    skylight += ambient_sss * skylight_up * material.sss_amount * 2.0;

#if defined WORLD_NETHER
    skylight = 16.0 * directional_lighting
        * mix(skylight, vec3(dot(skylight, luminance_weights_rec2020)), 0.5);
#endif

    lighting += skylight * get_skylight_falloff(light_levels.y) * SKYLIGHT_I;

    return lighting;
}

vec3 get_diffuse_lighting(
    Material material,
    vec3 scene_pos,
    vec3 normal,
    vec3 flat_normal,
    vec3 bent_normal,
    vec3 shadows,
    vec2 light_levels,
    float ao,
    float ambient_sss,
    float sss_depth,
#ifdef CLOUD_SHADOWS
    float cloud_shadows,
#endif
    float shadow_distance_fade,
#ifdef PHOTONICS_DIFFUSE
    bool is_lod,
#endif
    float NoL,
    float NoV,
    float NoH,
    float LoV
) {
#if defined PROGRAM_GBUFFERS_WATER
    // Small optimization, don't calculate diffuse lighting when albedo is 0 (eg
    // water)
    if (max_of(material.albedo) < eps) {
        return vec3(0.0);
    }
#endif

    vec3 lighting = vec3(0.0);

    // Arbitrary directional shading to make faces easier to distinguish
    float directional_lighting
        = (0.9 + 0.1 * normal.x) * (0.8 + 0.2 * abs(flat_normal.y))
        + 2.0 * ambient_sss * material.sss_amount;
    // Negative SSS depth => SSS blocked by occluder (SSRT SSS)
    bool sss_blocked = sss_depth < 0.0 || light_levels.y < 0.1;
    sss_depth = max0(sss_depth);

#if defined WORLD_OVERWORLD || defined WORLD_END || defined WORLD_SPACE

    // Sunlight/moonlight

#ifdef SHADOW
    vec3 diffuse = vec3(
                       lift(max0(NoL), 0.25 * rcp(SHADING_STRENGTH))
                       * (1.0 - 0.5 * material.sss_amount)
                   )
        * SHADING_STRENGTH;

#if defined PHOTONICS_DIFFUSE
#define DO_BOUNCED_LIGHTING is_lod
#else
#define DO_BOUNCED_LIGHTING true
#endif

    vec3 bounced = vec3(0.0);
    if (DO_BOUNCED_LIGHTING) {
        bounced = 0.033 * (1.0 - shadows) * (1.0 - 0.1 * max0(normal.y))
            * pow1d5(ao + eps) * pow4(light_levels.y) * BOUNCED_LIGHT_I;
#ifdef WORLD_SPACE
        bounced *= clamp01(smoothstep(0.0, 0.1, light_dir.y));
#endif
    }

    vec3 sss = sss_approx(
                   material.albedo,
                   material.sss_amount,
                   material.sheen_amount,
                   mix(sss_depth, 0.0, shadow_distance_fade),
                   LoV,
                   shadows.x
               )
        * float(!sss_blocked);

    // Adjust SSS outside of shadow distance
    sss *= mix(
        1.0,
        (ao + pi * ambient_sss) * (clamp01(NoL) * 0.8 + 0.2),
        clamp01(shadow_distance_fade)
    );

#ifdef AO_IN_SUNLIGHT
    diffuse *= sqr(ao);
#else // TODO: More ao control
    diffuse *= 0.4 + 0.6 * sqr(ao);
#endif

#ifdef SHADOW_VPS
    // Add SSS and diffuse
    lighting += diffuse * shadows + bounced + sss;
#else
    // Blend SSS and diffuse
    lighting += mix(diffuse, sss, material.sss_amount) * shadows + bounced;
#endif
#else
    // Simple shading for when shadows are disabled
    vec3 sss = 0.08 * sss_scale * pi
        + 0.5 * material.sheen_amount * rcp(material.albedo + eps)
            * henyey_greenstein_phase(-LoV, 0.5)
            * linear_step(-0.8, -0.2, -LoV);

    vec3 diffuse
        = vec3(lift(max0(NoL), 0.5 * rcp(SHADING_STRENGTH)) * 0.6 + 0.4)
        * (shadows * 0.8 + 0.2);
    diffuse = diffuse + max0(sss * lift(material.sss_amount, 5.0));
    diffuse *= 1.0 * (0.9 + 0.1 * normal.x) * (0.8 + 0.2 * abs(flat_normal.y));
    diffuse *= ao * pow4(light_levels.y) * (dampen(light_dir.y) * 0.5 + 0.5);

    lighting += diffuse;
#endif

    lighting *= light_color;

#ifdef CLOUD_SHADOWS
    lighting *= cloud_shadows;
#endif

#endif

    // Skylight

#if defined PHOTONICS_DIFFUSE
    if (is_lod) {
        lighting += get_sky_lighting(
            material,
            bent_normal,
            light_levels,
            ao,
            ambient_sss,
            directional_lighting
        );
    } else {
#ifndef PHOTONICS_RESTIR_COMBINED_GI
        lighting += texture(radiosity_indirect, uv).xyz * SKYLIGHT_I;
#endif
    }

#else
    lighting += get_sky_lighting(
        material,
        bent_normal,
        light_levels,
        ao,
        ambient_sss,
        directional_lighting
    );
#endif

    // Blocklight

#if defined PHOTONICS_DIFFUSE
    if (!is_lod) {
        vec3 blocklight = vec3(0.0);

        blocklight += sample_photonics_direct(uv);

#ifdef HANDHELD_LIGHTING
        blocklight += sample_photonics_handheld(uv);
#endif

        lighting += blocklight * blocklight_scale;
    } else {
        lighting += get_block_lighting(
            scene_pos,
            normal,
            flat_normal,
            light_levels,
            ao,
            directional_lighting,
            material
        );
    }
#else
    lighting += get_block_lighting(
        scene_pos,
        normal,
        flat_normal,
        light_levels,
        ao,
        directional_lighting,
        material
    );
#endif

    lighting += material.emission * emission_scale;

#if defined WORLD_OVERWORLD
    lighting += lightning_flash_point_lighting(scene_pos, normal, flat_normal, ao);

    // Cave lighting

    lighting += 0.15 * CAVE_LIGHTING_I * directional_lighting * ao
        * (1.0 - light_levels.y * light_levels.y)
        * (1.0 - 0.7 * darknessFactor);
#endif
#if defined WORLD_END && defined END_STORM_FOG_LIGHTNING_ENABLE
    lighting += end_storm_flash_point_lighting(scene_pos, normal, flat_normal, ao);
#endif
    if (nightVision > 0.0) {
        const vec3 nv_color
            = vec3(NIGHT_VISION_R, NIGHT_VISION_G, NIGHT_VISION_B)
            * night_vision_scale;

        float lum = dot(lighting, luminance_weights);
        float nv_strength = nightVision * directional_lighting * sqr(ao);
        vec3 nv_lighting = nv_color * nv_strength;
        lighting += nv_lighting * clamp01(1.0 - lum)
            * mix(1.0, 4.0, clamp01((0.25 - lum) * 4.0));
    }

    return max0(lighting) * material.albedo * rcp_pi
        * mix(1.0, metal_diffuse_amount, float(material.is_metal));
}

#endif // INCLUDE_LIGHTING_DIFFUSE_LIGHTING
