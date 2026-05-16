#if !defined INCLUDE_SKY_CLOUDS_THUNDERHEAD
#define INCLUDE_SKY_CLOUDS_THUNDERHEAD

#define CLOUDS_THUNDERHEAD_EGG_SOFTNESS 0.98
#define CLOUDS_THUNDERHEAD_ANVIL_SOFTNESS 100.0
#define CLOUDS_THUNDERHEAD_BRIGHTNESS 3.0
#define CLOUDS_THUNDERHEAD_ANVIL_COVERAGE 500.00
#define CLOUDS_THUNDERHEAD_BASE_BLUE_STRENGTH 1.0
#define CLOUDS_THUNDERHEAD_BASE_BLUE_HEIGHT 0.10

// Volumetric towering anvil clouds

#include "common.glsl"

#if defined CLOUDS_ALTOCUMULUS \
    && !defined PHOTON_ALTOCUMULUS_OCCLUSION_LOWER_DEFINED
float clouds_altocumulus_occlusion_on_lower_layers(
    vec3 ray_pos,
    vec3 light_dir,
    float dither
);
#endif

vec2 clouds_thunderhead_coverage_at_sample() {
    vec2 c = clouds_thunderhead_coverage;
#ifdef CLOUDS_THUNDERHEAD_STORM_FULL_COVERAGE
    float r = clamp01(rainStrength);
    float w = clamp01(wetness);
    float w_rise = pow(w, 1.3);
    float storm_blend = (r > w) ? w_rise : r;
    c = mix(c, vec2(1.7), clamp01(storm_blend));
#endif
    return c;
}

// altitude_fraction := 0 at the bottom of the cloud layer and 1 at the top
float clouds_thunderhead_altitude_shaping(
    float density,
    float altitude_fraction,
    float noise
) {
    // Carve egg shape to make the cloud more vertical and create anvil shape
    density -= smoothstep(-10.0, 25.0, altitude_fraction) * 0.3;

    // Reduce density at the top and bottom of the cloud
    density *= smoothstep(0.0, 0.2, altitude_fraction);

    return density;
}

float clouds_thunderhead_density(vec3 pos) {
    const float wind_angle = CLOUDS_THUNDERHEAD_WIND_ANGLE * degree;
    const vec2 wind_velocity = CLOUDS_THUNDERHEAD_WIND_SPEED
        * vec2(cos(wind_angle), sin(wind_angle));

    float r = length(pos);
    if (r < clouds_thunderhead_radius || r > clouds_thunderhead_top_radius) {
        return 0.0;
    }

    float altitude_fraction = (r - clouds_thunderhead_radius)
        * clouds_params.thunderhead_altitude_scale;
    float normalized_height = clamp01(
        (r - clouds_thunderhead_radius)
        / (clouds_thunderhead_top_radius - clouds_thunderhead_radius)
    );

    pos.xz += cameraPosition.xz * CLOUDS_SCALE + wind_velocity * world_age;

    // 2D noise for base shape and coverage
    vec2 noise = vec2(
        texture(noisetex, (0.00000015 / CLOUDS_THUNDERHEAD_SIZE) * pos.xz)
            .x, // cloud coverage
        texture(noisetex, (0.00000015 / CLOUDS_THUNDERHEAD_SIZE) * pos.xz)
            .x // cloud shape
    );

    float anvil_amount = smoothstep(0.6, 2.0, normalized_height);

    vec2 th_cov = clouds_thunderhead_coverage_at_sample();
    float base_density = mix(th_cov.x, th_cov.y, noise.x);
    float density = linear_step(1.0 - base_density * 0.75, 1.0, noise.y * 1.0);
    float anvil_mul = 1.3
        + anvil_amount * CLOUDS_THUNDERHEAD_ANVIL_COVERAGE
            * smoothstep(0.3, 0.7, base_density);
    density *= anvil_mul;
    density = clouds_thunderhead_altitude_shaping(
        density,
        altitude_fraction,
        noise.x
    );

    if (density < eps) {
        return 0.0;
    }

#if !defined PROGRAM_PREPARE
    vec3 wind = vec3(wind_velocity * world_age, 0.0).xzy;

    // 3D worley noise for detail
    float worley_0
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.2 * wind) * 0.00003).x;
    float worley_1
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.4 * wind) * 0.0008).x;
    float worley_body
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.6 * wind) * 0.000001)
              .x; // Body detail
    float worley_body_2
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.8 * wind) * 0.0001)
              .x; // Body detail
    float worley_anvil_a
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.33 * wind) * 0.000095).x;
    float worley_anvil_b
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.61 * wind) * 0.00022).x;
#elif defined ENABLE_THUNDERHEAD_SHADOW_DETAIL
    vec3 wind = vec3(wind_velocity * world_age, 0.0).xzy;

    float worley_0
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.2 * wind) * 0.00003).x;
    float worley_body
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.6 * wind) * 0.00002)
              .x; // Body detail
    float worley_anvil_a
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.33 * wind) * 0.000095).x;
    float worley_anvil_b
        = texture(SAMPLER_WORLEY_BUBBLY, (pos + 0.61 * wind) * 0.00018).x;

    const float worley_1 = 0.5;
    const float worley_body_2 = 0.5;
#else
    const float worley_0 = 0.5;
    const float worley_1 = 0.5;
    const float worley_body = 0.5;
    const float worley_body_2 = 0.5;
    const float worley_anvil_a = 0.5;
    const float worley_anvil_b = 0.5;
#endif // !PROGRAM_PREPARE

    float detail_fade = 0.20 * smoothstep(0.85, 1.0, 1.0 - altitude_fraction)
        - 0.70 * smoothstep(0.05, 0.5, altitude_fraction) + 0.6;

    float bottom_detail_boost
        = 1.0 + (1.0 - smoothstep(-4.0, 1.5, altitude_fraction)) * 100.0;
    density -= clouds_params.thunderhead_detail_weights.x * sqr(worley_0)
        * dampen(clamp01(1.0 - density)) * bottom_detail_boost;
    density -= clouds_params.thunderhead_detail_weights.y * sqr(worley_1)
        * dampen(clamp01(1.0 - density)) * detail_fade;

    // Apply extra detail to the egg shape body
    float body_mask = 1.0 - smoothstep(0.6, 0.9, normalized_height);
    density
        -= 0.3 * body_mask * sqr(worley_body) * dampen(clamp01(1.0 - density));
    density -= 0.1 * body_mask * sqr(worley_body_2)
        * dampen(clamp01(1.0 - density));

    // Adjust density so that the clouds are wispy at the bottom and hard at the
    // top
    density = max0(density);

    float edge_sharpness = mix(
        clouds_params.thunderhead_edge_sharpening.x,
        clouds_params.thunderhead_edge_sharpening.y,
        altitude_fraction
    );

    // --- Egg softness ---
    float egg_softness = max(CLOUDS_THUNDERHEAD_EGG_SOFTNESS, 0.0);
    float egg_edge_soften = min(egg_softness, 1.0);
    float egg_extra_soften = max(egg_softness - 1.0, 0.0);

    // --- Anvil softness ---
    float anvil_softness = max(CLOUDS_THUNDERHEAD_ANVIL_SOFTNESS, 0.0);
    float anvil_edge_soften = min(anvil_softness, 1.0);
    float anvil_extra_soften = max(anvil_softness - 1.0, 0.0);

    // Soften edges: egg applies everywhere, anvil applies only where
    // anvil_amount > 0
    edge_sharpness = mix(edge_sharpness, 0.0, egg_edge_soften);
    edge_sharpness = mix(edge_sharpness, 0.0, anvil_edge_soften * anvil_amount);

    density = lift(density, edge_sharpness);
    density *= CLOUDS_ROUGHNESS + 1.0 * smoothstep(0.2, 0.7, altitude_fraction);

    // Past softness = 1.0, thin density for wispy look
    // Egg thinning applies to the whole cloud
    density *= exp(-egg_extra_soften * 0.6);
    // Anvil thinning applies only to the anvil region
    density *= exp(-anvil_extra_soften * 0.6 * anvil_amount);

    // Frayed / choppy anvil rim (Worley erosion on the outer density roll-off)
    float anvil_chop_mask = anvil_amount * smoothstep(0.38, 0.96, normalized_height)
        * dampen(clamp01(1.0 - density * 2.8));
    float edge_chop = sqr(worley_anvil_a) * 0.52 + sqr(worley_anvil_b) * 0.42;
    density -= edge_chop * anvil_chop_mask * 1.0;
    density = max0(density);

    density = lift(density, edge_sharpness);
    density *= CLOUDS_ROUGHNESS * 0.9 * smoothstep(0.2, 0.7, altitude_fraction);

    return density;
}

float clouds_thunderhead_optical_depth(
    vec3 ray_origin,
    vec3 ray_dir,
    float dither,
    const uint step_count
) {
    const float step_growth = 2.0;

    float step_length = 1.0 * clouds_thunderhead_thickness / float(step_count);

    vec3 ray_pos = ray_origin;
    vec4 ray_step = vec4(ray_dir, 1.0) * step_length;

    float optical_depth = 0.0;

    for (uint i = 0u; i < step_count; ++i, ray_pos += ray_step.xyz) {
        ray_step *= step_growth;
        optical_depth
            += clouds_thunderhead_density(ray_pos + ray_step.xyz * dither)
            * ray_step.w;
    }

    return optical_depth;
}

// Altocumulus-style shell chord along the sun direction
float clouds_thunderhead_anvil_shadow_on_body(
    vec3 ray_pos,
    vec3 light_dir,
    float dither,
    float sample_density
) {
    const float Rmin = clouds_thunderhead_radius;
    const float Rmax = clouds_thunderhead_top_radius;
    const float inv_shell = 1.0 / (Rmax - Rmin);

    float r0 = length(ray_pos);
    float h0 = clamp01((r0 - Rmin) * inv_shell);
    float body_receiver = smoothstep(0.74, 0.36, h0);
    if (body_receiver < 1e-4) {
        return 0.0;
    }

    float lace = smoothstep(0.0018, 0.048, sample_density);
    body_receiver *= mix(0.40, 1.0, lace);

    vec2 shell_hit = intersect_spherical_shell(ray_pos, light_dir, Rmin, Rmax);
    if (shell_hit.y < 0.0) {
        return 0.0;
    }

    float t0 = max(0.0, shell_hit.x);
    float segment_len = shell_hit.y - t0;
    if (segment_len <= 0.0) {
        return 0.0;
    }

    const uint steps = 14u;
    float step_len = segment_len / float(steps);
    vec3 step_vec = light_dir * step_len;
    vec3 march_origin = ray_pos + light_dir * t0;

    float optical_depth = 0.0;
    for (uint i = 0u; i < steps; ++i) {
        vec3 sp = march_origin + step_vec * (float(i) + dither);
        float r = length(sp);
        if (r < Rmin || r > Rmax) {
            continue;
        }
        float h = clamp01((r - Rmin) * inv_shell);
        float anvil_mask = smoothstep(0.48, 0.84, h);
        optical_depth += clouds_thunderhead_density(sp) * anvil_mask * step_len;
    }

    return optical_depth * 34.0 * body_receiver;
}

// ∫ρ ds along light_dir through thunderhead+anvil shell, reusing the same
// shell-bounded style as altocumulus lower-layer shadowing.
float clouds_thunderhead_occlusion_on_lower_layers(
    vec3 ray_pos,
    vec3 light_dir,
    float dither
) {
    vec2 shell_hit = intersect_spherical_shell(
        ray_pos,
        light_dir,
        clouds_thunderhead_radius,
        clouds_thunderhead_top_radius
    );
    if (shell_hit.y < 0.0) {
        return 0.0;
    }

    float t0 = max(0.0, shell_hit.x);
    float segment_len = shell_hit.y - t0;
    if (segment_len <= 0.0) {
        return 0.0;
    }

    vec3 march_origin = ray_pos + light_dir * t0;

    const uint steps = 10u;
    float step_len = segment_len / float(steps);
    vec3 step_vec = light_dir * step_len;

    float optical_depth = 0.0;
    for (uint i = 0u; i < steps; ++i) {
        vec3 sp = march_origin + step_vec * (float(i) + dither);
        optical_depth += clouds_thunderhead_density(sp) * step_len;
    }

    // Slightly boosted so thunderhead/anvil shadows read darker on other layers.
    return optical_depth * 100.0;
}

#define PHOTON_THUNDERHEAD_OCCLUSION_LOWER_DEFINED

vec2 clouds_thunderhead_scattering(
    float density,
    float light_optical_depth,
    float sky_optical_depth,
    float ground_optical_depth,
    float step_transmittance,
    float cos_theta,
    float bounced_light,
    float altitude_fraction
) {
    vec2 scattering = vec2(0.0);

    float scatter_amount
        = clouds_params.l0_scattering_coeff * CLOUDS_THUNDERHEAD_BRIGHTNESS;
    float extinct_amount = clouds_params.l0_extinction_coeff;

    float scattering_integral_times_density
        = (1.0 - step_transmittance) / clouds_params.l0_extinction_coeff;

    float powder_effect = clouds_powder_effect(density, cos_theta);

    float phase = clouds_phase_single(cos_theta);
    vec3 phase_g = pow(vec3(0.6, 0.9, 0.3), vec3(1.0 + light_optical_depth));

    // Add height-based darkening
    float bottom_darkening
        = mix(0.1, 1.0, smoothstep(0.0, 3.0, altitude_fraction));

    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatter_amount
            * exp(-extinct_amount * light_optical_depth) * phase
            * bottom_darkening;
        scattering.x += scatter_amount
            * exp(-extinct_amount * ground_optical_depth) * isotropic_phase
            * bounced_light * bottom_darkening;
        scattering.y += scatter_amount
            * exp(-extinct_amount * sky_optical_depth) * isotropic_phase
            * bottom_darkening;

        scatter_amount *= 0.55
            * mix(lift(clamp01(clouds_params.l0_scattering_coeff / 0.1), 0.33),
                  1.0,
                  cos_theta * 0.5 + 0.5)
            * powder_effect;
        extinct_amount *= 0.4;
        phase_g *= 0.8;

        powder_effect = mix(powder_effect, sqrt(powder_effect), 0.5);

        phase = clouds_phase_multi(cos_theta, phase_g);
    }

    return scattering * scattering_integral_times_density;
}

float clouds_thunderhead_lightning(vec3 pos, float density) {
#ifdef CLOUDS_THUNDERHEAD_LIGHTNING_ENABLE
    if (density < 0.001) {
        return 0.0;
    }

    const float wind_angle = CLOUDS_THUNDERHEAD_WIND_ANGLE * degree;
    const vec2 wind_velocity = CLOUDS_THUNDERHEAD_WIND_SPEED
        * vec2(cos(wind_angle), sin(wind_angle));

    vec3 cloud_pos = pos;
    cloud_pos.xz
        += cameraPosition.xz * CLOUDS_SCALE + wind_velocity * world_age;

    const float cell_size = 30000.0;
    vec2 grid_pos = cloud_pos.xz / cell_size;
    vec2 cell_id = floor(grid_pos);

    float total_lightning = 0.0;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 current_cell = cell_id + vec2(x, y);

            const float block_duration = 1.0;
            float t = frameTimeCounter / block_duration;
            float t_floor = floor(t);

            vec4 hash = hash4(vec3(current_cell, t_floor));

            if (hash.w > CLOUDS_THUNDERHEAD_LIGHTNING_FREQUENCY) {
                continue;
            }

            float start_offset = hash.x * 0.1;
            float duration = (0.2 + hash.y * 0.5) / 1.0;

            float local_time = fract(t) * block_duration;
            float start_time = start_offset * block_duration;

            if (local_time < start_time || local_time > start_time + duration) {
                continue;
            }

            vec2 cell_origin = current_cell * cell_size;
            vec2 pos_seed = fract(hash.xy * 12.3 + hash.zw * 45.6);
            vec2 center_xz = cell_origin + pos_seed * cell_size;

            // Match density noise scale for valid placement
            float noise_val
                = texture(
                      noisetex,
                      (0.00000015 / CLOUDS_THUNDERHEAD_SIZE) * center_xz
                )
                      .x;
            if (noise_val < 0.4) {
                continue;
            }

            float center_y = clouds_thunderhead_radius
                + clouds_thunderhead_thickness * (0.3 + 0.4 * hash.z);

            float dx = cloud_pos.x - center_xz.x;
            float dz = cloud_pos.z - center_xz.y;
            float dy = length(pos) - center_y;

            float dist_sq = dx * dx + dz * dz + dy * dy;

            float radius = 4000.0 + hash.x * 20000.0;

            if (dist_sq > radius * radius) {
                continue;
            }

            float dist = sqrt(dist_sq);
            float falloff = smoothstep(radius, 0.0, dist);
            falloff = sqr(falloff); // sharper falloff

            float flash_progress = (local_time - start_time) / duration;

            // Select flash type based on hash
            int type = int(fract(hash.x * 10.0 + hash.y * 20.0) * 6.0);
            float intensity = 0.0;

            float speed = 1.0;
            float p = flash_progress;

            if (type == 0) {
                // Classic Flicker
                float flicker = noise_1d(
                    frameTimeCounter * 80.0 * speed + hash.w * 100.0
                );
                intensity = sin(p * pi) * (0.6 + 0.4 * flicker);
            } else if (type == 1) {
                // Double Flash
                float p1
                    = smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.3, 0.4, p));
                float p2
                    = smoothstep(0.5, 0.6, p) * (1.0 - smoothstep(0.9, 1.0, p));
                float flicker = noise_1d(frameTimeCounter * 120.0 * speed);
                intensity = (p1 + p2) * (0.8 + 0.2 * flicker);
            } else if (type == 2) {
                // Sheet/Long Flash
                float flicker = noise_1d(frameTimeCounter * 40.0 * speed);
                intensity
                    = smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.8, 1.0, p));
                intensity *= (0.5 + 0.5 * flicker);
            } else if (type == 3) {
                // Triple Flash
                float p1 = smoothstep(0.0, 0.05, p)
                    * (1.0 - smoothstep(0.15, 0.2, p));
                float p2 = smoothstep(0.3, 0.35, p)
                    * (1.0 - smoothstep(0.45, 0.5, p));
                float p3 = smoothstep(0.6, 0.65, p)
                    * (1.0 - smoothstep(0.75, 0.8, p));
                intensity = (p1 + p2 + p3)
                    * (0.9 + 0.1 * noise_1d(frameTimeCounter * 150.0 * speed));
            } else if (type == 4) {
                // Strobe/Crackle
                float flicker = noise_1d(
                    frameTimeCounter * 200.0 * speed + hash.y * 50.0
                );
                float envelope
                    = smoothstep(0.0, 0.2, p) * (1.0 - smoothstep(0.4, 0.9, p));
                intensity = step(0.5, flicker) * envelope;
            } else {
                // Ramp Up Flash
                float flicker = noise_1d(frameTimeCounter * 60.0 * speed);
                float envelope = pow(p, 3.0) * (1.0 - smoothstep(0.8, 1.0, p));
                intensity = envelope * (0.7 + 0.3 * flicker) * 2.0;
            }

            total_lightning += falloff * intensity;
        }
    }

    return total_lightning;
#else
    return 0.0;
#endif
}

CloudsResult draw_thunderhead_clouds(
    vec3 air_viewer_pos,
    vec3 ray_dir,
    vec3 clear_sky,
    float distance_to_terrain,
    float dither
) {
    // ---------------------
    //   Raymarching Setup
    // ---------------------

#if defined PROGRAM_DEFERRED0
    const uint primary_steps_horizon = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_H / 2;
    const uint primary_steps_zenith = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_Z / 2;
#else
    const uint primary_steps_horizon = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_H;
    const uint primary_steps_zenith = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_Z;
#endif // PROGRAM_DEFERRED0
    const uint lighting_steps = CLOUDS_THUNDERHEAD_LIGHTING_STEPS;
    const uint ambient_steps = CLOUDS_THUNDERHEAD_AMBIENT_STEPS;
    const float max_ray_length = 30e4;
    const float min_transmittance_base = 0.075;
    const float planet_albedo = 0.4;
    const vec3 sky_dir = vec3(0.0, 1.0, 0.0);

    uint primary_steps = uint(
        mix(primary_steps_horizon, primary_steps_zenith, abs(ray_dir.y))
    );

    float r = length(air_viewer_pos);

    vec2 dists = intersect_spherical_shell(
        air_viewer_pos,
        ray_dir,
        clouds_thunderhead_radius,
        clouds_thunderhead_top_radius
    );
    bool planet_intersected
        = intersect_sphere(
              air_viewer_pos,
              ray_dir,
              min(r - 10.0, planet_radius)
          )
              .y
        >= 0.0;
    bool terrain_intersected = distance_to_terrain >= 0.0
        && r < clouds_thunderhead_radius
        && distance_to_terrain * CLOUDS_SCALE < dists.y;

    if (
        dists.y < 0.0 // volume not intersected
        || planet_intersected
            && r < clouds_thunderhead_radius // planet blocking clouds
        || terrain_intersected // terrain blocking clouds
    ) {
        return clouds_not_hit;
    }

    float immersion = clouds_shell_immersion(
        air_viewer_pos,
        clouds_thunderhead_radius,
        clouds_thunderhead_top_radius
    );
    primary_steps = clouds_boost_steps_inside_shell(
        primary_steps,
        air_viewer_pos,
        clouds_thunderhead_radius,
        clouds_thunderhead_top_radius
    );
    float min_transmittance
        = mix(min_transmittance_base, 0.038, dampen(immersion));

    float ray_length
        = (distance_to_terrain >= 0.0) ? distance_to_terrain : dists.y;
    ray_length = clamp(ray_length - dists.x, 0.0, max_ray_length);
    float step_length = ray_length * rcp(float(primary_steps));

    vec3 ray_step = ray_dir * step_length;
    vec3 ray_origin
        = air_viewer_pos + ray_dir * (dists.x + step_length * dither);

    vec3 direct_scattering
        = vec3(0.0); // RGB accumulated with per-sample atmosphere transmittance
    float sky_scattering = 0.0;
    float lightning_accum = 0.0;
    float transmittance = 1.0;

    float distance_sum = 0.0;
    float distance_weight_sum = 0.0;

    // ------------------
    //   Lighting Setup
    // ------------------

    bool moonlit = sun_dir.y < -0.1;
    vec3 light_dir = moonlit ? moon_dir : sun_dir;
    float cos_theta = dot(ray_dir, light_dir);
    float bounced_light = planet_albedo * light_dir.y * rcp_pi;

    float extinction_coeff
        = mix(0.07, 0.1, smoothstep(0.0, 0.3, abs(sun_dir.y)))
        * (1.0 - 0.33 * rainStrength) * CLOUDS_THUNDERHEAD_DENSITY;
    float scattering_coeff = extinction_coeff * mix(1.00, 1.6, rainStrength);

    float dynamic_thickness = mix(
        0.5,
        1.0,
        smoothstep(0.4, 0.6, clouds_thunderhead_coverage_at_sample().y)
    );
    vec2 detail_weights = vec2(0.01, 0.05) * CLOUDS_THUNDERHEAD_DETAIL_STRENGTH;
    vec2 edge_sharpening = vec2(3.0, 8.0);

    // --------------------
    //   Raymarching Loop
    // --------------------

    for (uint i = 0u; i < primary_steps; ++i) {
        if (transmittance < min_transmittance) {
            break;
        }

        vec3 ray_pos = ray_origin + ray_step * i;
        float r_sample = length(ray_pos);

        float density = clouds_thunderhead_density(ray_pos);

        if (density < eps) {
            continue;
        }

        float distance_to_sample = distance(ray_origin, ray_pos);
        float distance_fade
            = smoothstep(0.95, 1.0, distance_to_sample * rcp(max_ray_length));

        density *= 1.0 - distance_fade;

        float step_optical_depth
            = density * clouds_params.l0_extinction_coeff * step_length;
        float step_transmittance = exp(-step_optical_depth);

        float lightning_radiance
            = clouds_thunderhead_lightning(ray_pos, density);
        lightning_accum
            += lightning_radiance * (1.0 - step_transmittance) * transmittance;

#if defined PROGRAM_DEFERRED0
        vec2 hash = vec2(0.0);
#else
        vec2 hash = hash2(fract(ray_pos));
#endif // PROGRAM_DEFERRED0

        float light_optical_depth = clouds_thunderhead_optical_depth(
            ray_pos,
            light_dir,
            hash.x,
            lighting_steps
        );
#if !defined PROGRAM_PREPARE
        light_optical_depth += clouds_thunderhead_anvil_shadow_on_body(
            ray_pos,
            light_dir,
            fract(hash.x * 17.0 + hash.y * 3.7),
            density
        );
#endif
#ifdef CLOUDS_ALTOCUMULUS && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
        if (max(clouds_params.l1_coverage.x, clouds_params.l1_coverage.y)
            >= 1e-3) {
            light_optical_depth += clouds_altocumulus_occlusion_on_lower_layers(
                ray_pos,
                light_dir,
                hash.x
            );
        }
#endif
        float sky_optical_depth = clouds_thunderhead_optical_depth(
            ray_pos,
            sky_dir,
            hash.y,
            ambient_steps
        );

        float ground_optical_depth
            = mix(density,
                  1.0,
                  clamp01(r_sample / clouds_thunderhead_top_radius * 2.0 - 1.0))
            * (r_sample - clouds_thunderhead_radius)
            / clouds_thunderhead_top_radius;

        float altitude_fraction = (r_sample - clouds_thunderhead_radius)
            * clouds_params.thunderhead_altitude_scale;

        vec2 scatter = clouds_thunderhead_scattering(
            density,
            light_optical_depth,
            sky_optical_depth,
            ground_optical_depth,
            step_transmittance,
            cos_theta,
            bounced_light,
            altitude_fraction
        );

        lightning_accum += lightning_flash_cloud_sample_intensity(
            ray_pos - air_viewer_pos,
            step_transmittance,
            transmittance
        );

        // Sample atmosphere transmittance LUT at this sample position (path
        // from sample to sun)
        vec3 light_color_at_sample
            = sunlight_color * atmosphere_transmittance(ray_pos, light_dir);
        light_color_at_sample
            = atmosphere_post_processing(light_color_at_sample);
        light_color_at_sample *= moonlit ? moon_color : sun_color;

        float normalized_shell_h = clamp01(
            (r_sample - clouds_thunderhead_radius)
                / (clouds_thunderhead_top_radius - clouds_thunderhead_radius));
        float storm_base_blue = (1.0
            - smoothstep(0.0, CLOUDS_THUNDERHEAD_BASE_BLUE_HEIGHT, normalized_shell_h))
            * CLOUDS_THUNDERHEAD_BASE_BLUE_STRENGTH;
        storm_base_blue *= storm_base_blue;
        vec3 cool_base_tint = mix(
            vec3(1.0),
            vec3(1.0, 1.0, 1.0),
            storm_base_blue);
        vec3 light_for_cloud = light_color_at_sample * cool_base_tint;

        direct_scattering += scatter.x * light_for_cloud * transmittance;
        sky_scattering += scatter.y * transmittance * (1.0 + storm_base_blue * 0.28);

        transmittance *= step_transmittance;

        distance_sum += distance_to_sample * density;
        distance_weight_sum += density;
    }

    float clouds_transmittance
        = linear_step(min_transmittance, 1.0, transmittance);
    clouds_transmittance = clouds_stabilize_immersed_transmittance(
        clouds_transmittance,
        immersion
    );

    float sky_fill = 1.0 + 0.12 * dampen(immersion);
    vec3 clouds_scattering
        = direct_scattering + sky_scattering * sky_color * sky_fill;
    /*if (distance_to_terrain < 0.0)*/ clouds_scattering
        = clouds_aerial_perspective_immersed(
            clouds_scattering,
            clouds_transmittance,
            distance_to_terrain,
            air_viewer_pos,
            ray_origin,
            ray_dir,
            clear_sky,
            immersion
        );

    float apparent_distance = (distance_weight_sum == 0.0)
        ? 1e6
        : (distance_sum / distance_weight_sum)
            + distance(air_viewer_pos, ray_origin);

    return CloudsResult(
        vec4(clouds_scattering, sky_scattering),
        clouds_transmittance,
        apparent_distance,
        lightning_accum
    );
}
#endif // INCLUDE_SKY_CLOUDS_THUNDERHEAD
