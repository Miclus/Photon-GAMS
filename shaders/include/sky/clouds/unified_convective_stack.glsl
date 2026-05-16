#if !defined INCLUDE_SKY_CLOUDS_UNIFIED_CONVECTIVE_STACK
#define INCLUDE_SKY_CLOUDS_UNIFIED_CONVECTIVE_STACK

// Single spherical-shell raymarch for cumulus + altocumulus + towering cumulus
// + thunderhead, with planar cirrus/cirrocumulus composited separately.
// Preserves per-layer density, lighting, and scattering models; combines
// volumetric extinction along the ray.

float photon_unified_scatter_weight(
    float tau_i,
    float tau_tot,
    float Ti,
    float Ttot
) {
    if (tau_tot < 1e-8 || tau_i < 1e-8) {
        return 0.0;
    }
    float one_minus_Ti = 1.0 - Ti;
    if (one_minus_Ti < 1e-5) {
        return tau_i / tau_tot;
    }
    return (tau_i / tau_tot) * ((1.0 - Ttot) / one_minus_Ti);
}

CloudsResult draw_unified_convective_cloud_stack(
    vec3 air_viewer_pos,
    vec3 ray_dir,
    vec3 clear_sky,
    float distance_to_terrain,
    float dither
) {
#if defined PROGRAM_DEFERRED0
    const uint prim_cu_h = CLOUDS_CUMULUS_PRIMARY_STEPS_H / 2u;
    const uint prim_cu_z = CLOUDS_CUMULUS_PRIMARY_STEPS_Z / 2u;
#ifdef CLOUDS_ALTOCUMULUS
    const uint prim_al_h = CLOUDS_ALTOCUMULUS_PRIMARY_STEPS_H / 2u;
    const uint prim_al_z = CLOUDS_ALTOCUMULUS_PRIMARY_STEPS_Z / 2u;
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    const uint prim_to_h = CLOUDS_TOWERING_CUMULUS_PRIMARY_STEPS_H / 2u;
    const uint prim_to_z = CLOUDS_TOWERING_CUMULUS_PRIMARY_STEPS_Z / 2u;
#endif
#ifdef CLOUDS_THUNDERHEAD
    const uint prim_th_h = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_H / 2u;
    const uint prim_th_z = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_Z / 2u;
#endif
#else
    const uint prim_cu_h = CLOUDS_CUMULUS_PRIMARY_STEPS_H;
    const uint prim_cu_z = CLOUDS_CUMULUS_PRIMARY_STEPS_Z;
#ifdef CLOUDS_ALTOCUMULUS
    const uint prim_al_h = CLOUDS_ALTOCUMULUS_PRIMARY_STEPS_H;
    const uint prim_al_z = CLOUDS_ALTOCUMULUS_PRIMARY_STEPS_Z;
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    const uint prim_to_h = CLOUDS_TOWERING_CUMULUS_PRIMARY_STEPS_H;
    const uint prim_to_z = CLOUDS_TOWERING_CUMULUS_PRIMARY_STEPS_Z;
#endif
#ifdef CLOUDS_THUNDERHEAD
    const uint prim_th_h = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_H;
    const uint prim_th_z = CLOUDS_THUNDERHEAD_PRIMARY_STEPS_Z;
#endif
#endif

    const uint lit_cu = CLOUDS_CUMULUS_LIGHTING_STEPS;
    const uint amb_cu = CLOUDS_CUMULUS_AMBIENT_STEPS;
#ifdef CLOUDS_ALTOCUMULUS
    const uint lit_al = CLOUDS_ALTOCUMULUS_LIGHTING_STEPS;
    const uint amb_al = CLOUDS_ALTOCUMULUS_AMBIENT_STEPS;
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    const uint lit_to = CLOUDS_TOWERING_CUMULUS_LIGHTING_STEPS;
    const uint amb_to = CLOUDS_TOWERING_CUMULUS_AMBIENT_STEPS;
#endif
#ifdef CLOUDS_THUNDERHEAD
    const uint lit_th = CLOUDS_THUNDERHEAD_LIGHTING_STEPS;
    const uint amb_th = CLOUDS_THUNDERHEAD_AMBIENT_STEPS;
#endif

    const float min_transmittance_base = 0.075;
    const float planet_albedo = 0.4;
    const vec3 sky_dir = vec3(0.0, 1.0, 0.0);

    bool cov_l0
        = max(clouds_params.l0_coverage.x, clouds_params.l0_coverage.y) >= 1e-3;
#ifdef CLOUDS_ALTOCUMULUS
    bool cov_l1
        = max(clouds_params.l1_coverage.x, clouds_params.l1_coverage.y) >= 1e-3;
#else
    bool cov_l1 = false;
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    bool cov_to = max(clouds_towering_cumulus_coverage.x,
                      clouds_towering_cumulus_coverage.y)
        >= 1e-3;
#else
    bool cov_to = false;
#endif
#ifdef CLOUDS_THUNDERHEAD
    vec2 th_cov0 = clouds_thunderhead_coverage_at_sample();
    bool cov_th = max(th_cov0.x, th_cov0.y) >= 1e-3;
#else
    bool cov_th = false;
#endif
#ifdef CLOUDS_CIRRUS
    bool cov_ci = max(clouds_params.cirrus_amount, clouds_params.cirrocumulus_amount)
        >= 1e-3;
#else
    bool cov_ci = false;
#endif

    bool did_volume = cov_l0 || cov_l1 || cov_to || cov_th;
    if (!did_volume) {
#ifdef CLOUDS_CIRRUS
        if (cov_ci) {
            return draw_cirrus_clouds(
                air_viewer_pos,
                ray_dir,
                clear_sky,
                distance_to_terrain,
                dither
            );
        }
#endif
        return clouds_not_hit;
    }
    float u_inner = clouds_cumulus_radius;
    float u_outer = clouds_cumulus_top_radius;
    float max_ray_length = 15e4;

#ifdef CLOUDS_ALTOCUMULUS
    u_inner = min(u_inner, clouds_altocumulus_radius);
    u_outer = max(u_outer, clouds_altocumulus_top_radius);
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    u_inner = min(u_inner, clouds_towering_cumulus_radius);
    u_outer = max(u_outer, clouds_towering_cumulus_top_radius);
    max_ray_length = max(max_ray_length, 30e4);
#endif
#ifdef CLOUDS_THUNDERHEAD
    u_inner = min(u_inner, clouds_thunderhead_radius);
    u_outer = max(u_outer, clouds_thunderhead_top_radius);
    max_ray_length = max(max_ray_length, 30e4);
#endif

    uint primary_steps_horizon = prim_cu_h;
    uint primary_steps_zenith = prim_cu_z;
#ifdef CLOUDS_ALTOCUMULUS
    primary_steps_horizon = max(primary_steps_horizon, prim_al_h);
    primary_steps_zenith = max(primary_steps_zenith, prim_al_z);
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    primary_steps_horizon = max(primary_steps_horizon, prim_to_h);
    primary_steps_zenith = max(primary_steps_zenith, prim_to_z);
#endif
#ifdef CLOUDS_THUNDERHEAD
    primary_steps_horizon = max(primary_steps_horizon, prim_th_h);
    primary_steps_zenith = max(primary_steps_zenith, prim_th_z);
#endif

    uint primary_steps = uint(
        mix(float(primary_steps_horizon),
            float(primary_steps_zenith),
            abs(ray_dir.y))
    );

    float r = length(air_viewer_pos);

    vec2 dists
        = intersect_spherical_shell(air_viewer_pos, ray_dir, u_inner, u_outer);
    bool planet_intersected
        = intersect_sphere(
              air_viewer_pos,
              ray_dir,
              min(r - 10.0, planet_radius)
          )
              .y
        >= 0.0;
    bool terrain_intersected = distance_to_terrain >= 0.0 && r < u_inner
        && distance_to_terrain * CLOUDS_SCALE < dists.y;

    if (dists.y < 0.0 || planet_intersected && r < u_inner
        || terrain_intersected) {
#ifdef CLOUDS_CIRRUS
        if (cov_ci) {
            return draw_cirrus_clouds(
                air_viewer_pos,
                ray_dir,
                clear_sky,
                distance_to_terrain,
                dither
            );
        }
#endif
        return clouds_not_hit;
    }
    float immersion = clouds_shell_immersion(air_viewer_pos, u_inner, u_outer);
    primary_steps = clouds_boost_steps_inside_shell(
        primary_steps,
        air_viewer_pos,
        u_inner,
        u_outer
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

    vec3 direct_scattering_acc = vec3(0.0);
    float sky_scattering_acc = 0.0;
    vec3 lpv_scattering = vec3(0.0);
    float transmittance = 1.0;
    float lightning_accum = 0.0;

    float distance_sum = 0.0;
    float distance_weight_sum = 0.0;

    float l0_shadow = linear_step(0.5, 0.6, clouds_params.l1_coverage.x)
        * dampen(day_factor);

#ifdef CLOUDS_ALTOCUMULUS
    float alto_high_coverage
        = linear_step(0.0, 0.0, clouds_params.l1_coverage.x);
    float alto_extinction_coeff = mix(0.1, 0.2, day_factor)
        * CLOUDS_ALTOCUMULUS_DENSITY
        * (2.0 - 1.0 * clouds_params.l1_cumulus_stratus_blend);
    float alto_scattering_coeff
        = alto_extinction_coeff * mix(1.00, 0.75, rainStrength);
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    float to_extinction_coeff
        = mix(0.07, 0.1, smoothstep(0.0, 0.3, abs(sun_dir.y)))
        * (1.0 - 0.33 * rainStrength) * CLOUDS_TOWERING_CUMULUS_DENSITY;
#endif
    for (uint i = 0u; i < primary_steps; ++i) {
        if (transmittance < min_transmittance) {
            break;
        }

        vec3 ray_pos = ray_origin + ray_step * float(i);
        float r_sample = length(ray_pos);
        float dist_to_sample = distance(ray_origin, ray_pos);

        float d_cu = 0.0;
        if (cov_l0) {
            d_cu = clouds_cumulus_density(ray_pos);
            if (d_cu > eps) {
                d_cu *= smoothstep(
                    1.0,
                    0.95,
                    dist_to_sample * rcp(max_ray_length)
                );
#if defined CLOUDS_USE_LOCAL_COVERAGE_MAP
                d_cu *= smoothstep(
                    1.0,
                    0.9,
                    length(ray_pos.xz)
                        * rcp(0.5 * clouds_cumulus_coverage_map_scale)
                );
#endif
            }
        }

        float d_al = 0.0;
#ifdef CLOUDS_ALTOCUMULUS
        if (cov_l1) {
            d_al = clouds_altocumulus_density(ray_pos);
            if (d_al > eps) {
                d_al *= 1.0
                    - smoothstep(
                            0.95,
                            1.0,
                            dist_to_sample * rcp(max_ray_length)
                    );
            }
        }
#endif

        float d_to = 0.0;
#ifdef CLOUDS_TOWERING_CUMULUS
        if (cov_to) {
            d_to = clouds_towering_cumulus_density(ray_pos);
            if (d_to > eps) {
                d_to *= 1.0 - smoothstep(0.95, 1.0, dist_to_sample * rcp(30e4));
            }
        }
#endif

        float d_th = 0.0;
#ifdef CLOUDS_THUNDERHEAD
        if (cov_th) {
            d_th = clouds_thunderhead_density(ray_pos);
            if (d_th > eps) {
                d_th *= 1.0 - smoothstep(0.95, 1.0, dist_to_sample * rcp(30e4));
            }
        }
#endif

        float tau_cu = 0.0;
        float tau_al = 0.0;
        float tau_to = 0.0;
        float tau_th = 0.0;

        if (d_cu > eps) {
            tau_cu = d_cu * clouds_params.l0_extinction_coeff * step_length;
        }
#ifdef CLOUDS_ALTOCUMULUS
        if (d_al > eps) {
            tau_al = d_al * alto_extinction_coeff * step_length;
        }
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
        if (d_to > eps) {
            tau_to = d_to * to_extinction_coeff * step_length;
        }
#endif
#ifdef CLOUDS_THUNDERHEAD
        if (d_th > eps) {
            tau_th = d_th * clouds_params.l0_extinction_coeff * step_length;
        }
#endif

        float tau_tot = tau_cu + tau_al + tau_to + tau_th;
        if (tau_tot < 1e-8) {
            continue;
        }

        float trans_before = transmittance;

        float Ttot = exp(-tau_tot);
        float Tcu = exp(-tau_cu);
#ifdef CLOUDS_ALTOCUMULUS
        float Tal = exp(-tau_al);
#else
        float Tal = 1.0;
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
        float Tto = exp(-tau_to);
#else
        float Tto = 1.0;
#endif
#ifdef CLOUDS_THUNDERHEAD
        float Tth = exp(-tau_th);
#else
        float Tth = 1.0;
#endif

#if defined PROGRAM_DEFERRED0
        vec2 hash = vec2(0.0);
#else
        vec2 hash = hash2(fract(ray_pos));
#endif

        if (d_cu > eps && tau_cu > 1e-8) {
            bool moonlit_cumulus = sun_dir.y < -0.04;
            vec3 light_dir_cu = moonlit_cumulus ? moon_dir : sun_dir;
            float cos_theta_cu = dot(ray_dir, light_dir_cu);
            float bounced_cu = planet_albedo * light_dir_cu.y * rcp_pi;

            float altitude_fraction_cu = (r_sample - clouds_cumulus_radius)
                * rcp(clouds_cumulus_thickness);
            float lod_cu = clouds_cumulus_optical_depth(
                ray_pos,
                light_dir_cu,
                hash.x,
                lit_cu
            );
#if defined CLOUDS_THUNDERHEAD && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            lod_cu += clouds_thunderhead_occlusion_on_lower_layers(
                ray_pos,
                light_dir_cu,
                hash.x
            );
#endif
#if defined CLOUDS_ALTOCUMULUS && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            if (cov_l1) {
                lod_cu += PHOTON_ALTOCUMULUS_LOWER_SHADOW_SCALE
                    * clouds_altocumulus_occlusion_on_lower_layers(
                        ray_pos,
                        light_dir_cu,
                        hash.x
                    );
            }
#endif
#if defined CLOUDS_TOWERING_CUMULUS && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            if (cov_to) {
                lod_cu += PHOTON_TOWERING_CUMULUS_LOWER_SHADOW_SCALE
                    * clouds_towering_cumulus_occlusion_on_lower_layers(
                        ray_pos,
                        light_dir_cu,
                        hash.x
                    );
            }
#endif
            float sod_cu = clouds_cumulus_optical_depth(
                ray_pos,
                sky_dir,
                hash.y,
                amb_cu
            );
            float god_cu
                = mix(d_cu, 1.0, clamp01(altitude_fraction_cu * 2.0 - 1.0))
                * altitude_fraction_cu * clouds_cumulus_thickness;

            float w_cu
                = photon_unified_scatter_weight(tau_cu, tau_tot, Tcu, Ttot);
            vec2 sc_cu
                = clouds_cumulus_scattering(
                      d_cu,
                      lod_cu,
                      sod_cu,
                      god_cu,
                      Tcu,
                      cos_theta_cu,
                      l0_shadow,
                      bounced_cu
                  )
                * w_cu;

            vec3 lc_cu = sunlight_color
                * atmosphere_transmittance(ray_origin, light_dir_cu);
            lc_cu = atmosphere_post_processing(lc_cu);
            lc_cu *= moonlit_cumulus ? moon_color : sun_color;
            direct_scattering_acc += sc_cu.x * lc_cu * trans_before;
            sky_scattering_acc += sc_cu.y * trans_before;
        }

#ifdef CLOUDS_ALTOCUMULUS
        if (d_al > eps && tau_al > 1e-8) {
            bool moonlit_altocumulus = sun_dir.y < -0.045;
            vec3 light_dir_al = moonlit_altocumulus ? moon_dir : sun_dir;
            float cos_theta_al = dot(ray_dir, light_dir_al);
            float bounced_al = planet_albedo * light_dir_al.y * rcp_pi;

            float altitude_fraction_al = (r_sample - clouds_altocumulus_radius)
                * rcp(clouds_altocumulus_thickness);
            float lod_al = clouds_altocumulus_optical_depth(
                ray_pos,
                light_dir_al,
                hash.x,
                lit_al
            );
#if defined CLOUDS_THUNDERHEAD && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            lod_al += clouds_thunderhead_occlusion_on_lower_layers(
                ray_pos,
                light_dir_al,
                hash.x
            );
#endif
#if defined CLOUDS_TOWERING_CUMULUS && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            if (cov_to) {
                lod_al += PHOTON_TOWERING_CUMULUS_LOWER_SHADOW_SCALE
                    * clouds_towering_cumulus_occlusion_on_lower_layers(
                        ray_pos,
                        light_dir_al,
                        hash.x
                    );
            }
#endif
            float sod_al = clouds_altocumulus_optical_depth(
                ray_pos,
                sky_dir,
                hash.y,
                amb_al
            );
            float god_al
                = mix(d_al, 1.0, clamp01(altitude_fraction_al * 2.0 - 1.0))
                * altitude_fraction_al * clouds_altocumulus_thickness;

            float w_al
                = photon_unified_scatter_weight(tau_al, tau_tot, Tal, Ttot);
            vec2 sc_al
                = clouds_altocumulus_scattering(
                      d_al,
                      lod_al,
                      sod_al,
                      god_al,
                      alto_extinction_coeff,
                      alto_scattering_coeff,
                      Tal,
                      cos_theta_al,
                      bounced_al
                  )
                * w_al;

            vec3 lc_al = sunlight_color
                * atmosphere_transmittance(ray_origin, light_dir_al);
            lc_al = atmosphere_post_processing(lc_al);
            lc_al *= moonlit_altocumulus ? moon_color : sun_color;
            lc_al *= 1.0 + 0.4 * alto_high_coverage * dampen(time_noon);
            direct_scattering_acc += sc_al.x * lc_al * trans_before;
            sky_scattering_acc += sc_al.y * trans_before;
        }
#endif

#ifdef CLOUDS_TOWERING_CUMULUS
        if (d_to > eps && tau_to > 1e-8) {
            bool moonlit_towering_cumulus = sun_dir.y < -0.1;
            vec3 light_dir_to = moonlit_towering_cumulus ? moon_dir : sun_dir;
            float cos_theta_to = dot(ray_dir, light_dir_to);
            float bounced_to = planet_albedo * light_dir_to.y * rcp_pi;

            float lod_to = clouds_towering_cumulus_optical_depth(
                ray_pos,
                light_dir_to,
                hash.x,
                lit_to
            );
#if defined CLOUDS_THUNDERHEAD && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            vec2 th_cov_occl3 = clouds_thunderhead_coverage_at_sample();
            if (max(th_cov_occl3.x, th_cov_occl3.y) >= 1e-3) {
                lod_to += clouds_thunderhead_occlusion_on_lower_layers(
                    ray_pos,
                    light_dir_to,
                    hash.x
                );
            }
#endif
#if defined CLOUDS_ALTOCUMULUS && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            if (cov_l1) {
                lod_to += clouds_altocumulus_occlusion_on_lower_layers(
                    ray_pos,
                    light_dir_to,
                    hash.x
                );
            }
#endif
            float sod_to = clouds_towering_cumulus_optical_depth(
                ray_pos,
                sky_dir,
                hash.y,
                amb_to
            );
            float god_to
                = mix(d_to,
                      1.0,
                      clamp01(
                          r_sample / clouds_towering_cumulus_top_radius * 2.0
                          - 1.0
                      ))
                * (r_sample - clouds_towering_cumulus_radius)
                / clouds_towering_cumulus_thickness;
            float altitude_fraction_to
                = (r_sample - clouds_towering_cumulus_radius)
                * clouds_params.towering_cumulus_altitude_scale;

            float w_to
                = photon_unified_scatter_weight(tau_to, tau_tot, Tto, Ttot);
            vec2 sc_to
                = clouds_towering_cumulus_scattering(
                      d_to,
                      lod_to,
                      sod_to,
                      god_to,
                      Tto,
                      cos_theta_to,
                      bounced_to,
                      altitude_fraction_to
                  )
                * w_to;

            vec3 lc_to = sunlight_color
                * atmosphere_transmittance(ray_pos, light_dir_to);
            lc_to = atmosphere_post_processing(lc_to);
            lc_to *= moonlit_towering_cumulus ? moon_color : sun_color;
            direct_scattering_acc += sc_to.x * lc_to * trans_before;
            sky_scattering_acc += sc_to.y * trans_before;
        }
#endif

#ifdef CLOUDS_THUNDERHEAD
        if (d_th > eps && tau_th > 1e-8) {
            bool moonlit_thunderhead = sun_dir.y < -0.1;
            vec3 light_dir_th = moonlit_thunderhead ? moon_dir : sun_dir;
            float cos_theta_th = dot(ray_dir, light_dir_th);
            float bounced_th = planet_albedo * light_dir_th.y * rcp_pi;

            float lod_th = clouds_thunderhead_optical_depth(
                ray_pos,
                light_dir_th,
                hash.x,
                lit_th
            );
#if !defined PROGRAM_PREPARE
            lod_th += clouds_thunderhead_anvil_shadow_on_body(
                ray_pos,
                light_dir_th,
                fract(hash.x * 17.0 + hash.y * 3.7),
                d_th
            );
#endif
#if defined CLOUDS_ALTOCUMULUS && !defined PROGRAM_PREPARE \
    && defined CLOUDS_LAYER_SHADOWING
            if (cov_l1) {
                lod_th += clouds_altocumulus_occlusion_on_lower_layers(
                    ray_pos,
                    light_dir_th,
                    hash.x
                );
            }
#endif
            float sod_th = clouds_thunderhead_optical_depth(
                ray_pos,
                sky_dir,
                hash.y,
                amb_th
            );
            float god_th
                = mix(d_th,
                      1.0,
                      clamp01(
                          r_sample / clouds_thunderhead_top_radius * 2.0 - 1.0
                      ))
                * (r_sample - clouds_thunderhead_radius)
                / clouds_thunderhead_top_radius;
            float altitude_fraction_th = (r_sample - clouds_thunderhead_radius)
                * clouds_params.thunderhead_altitude_scale;

            float w_th
                = photon_unified_scatter_weight(tau_th, tau_tot, Tth, Ttot);
            vec2 sc_th
                = clouds_thunderhead_scattering(
                      d_th,
                      lod_th,
                      sod_th,
                      god_th,
                      Tth,
                      cos_theta_th,
                      bounced_th,
                      altitude_fraction_th
                  )
                * w_th;

            vec3 lc_th = sunlight_color
                * atmosphere_transmittance(ray_pos, light_dir_th);
            lc_th = atmosphere_post_processing(lc_th);
            lc_th *= moonlit_thunderhead ? moon_color : sun_color;
            float normalized_shell_h_th = clamp01(
                (r_sample - clouds_thunderhead_radius)
                    / (clouds_thunderhead_top_radius - clouds_thunderhead_radius));
            float storm_base_blue_th = (1.0
                - smoothstep(0.0, CLOUDS_THUNDERHEAD_BASE_BLUE_HEIGHT, normalized_shell_h_th))
                * CLOUDS_THUNDERHEAD_BASE_BLUE_STRENGTH;
            storm_base_blue_th *= storm_base_blue_th;
            vec3 cool_base_tint_th = mix(
                vec3(1.0),
                vec3(0.82, 0.92, 1.12),
                storm_base_blue_th);
            vec3 lc_th_cloud = lc_th * cool_base_tint_th;
            direct_scattering_acc += sc_th.x * lc_th_cloud * trans_before;
            sky_scattering_acc
                += sc_th.y * trans_before * (1.0 + storm_base_blue_th * 0.28);
        }
#endif

#if defined CLOUDS_THUNDERHEAD && defined CLOUDS_THUNDERHEAD_LIGHTNING_ENABLE
        if (cov_th) {
            // Flash is evaluated only from thunderhead density + thunderhead
            // lightning logic; spill lights other layers along the same ray.
            float L_tf = clouds_thunderhead_lightning(ray_pos, d_th);
            if (L_tf > 0.0) {
                lightning_accum += L_tf * (1.0 - Tth) * trans_before;

                float other_density = d_cu;
#ifdef CLOUDS_ALTOCUMULUS
                other_density += d_al;
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
                other_density += d_to;
#endif
                vec3 lrgb = vec3(
                                CLOUDS_THUNDERHEAD_LIGHTNING_COLOR_R,
                                CLOUDS_THUNDERHEAD_LIGHTNING_COLOR_G,
                                CLOUDS_THUNDERHEAD_LIGHTNING_COLOR_B
                            )
                    * CLOUDS_THUNDERHEAD_LIGHTNING_INTENSITY;
                float spill = dampen(clamp01(3.0 * other_density));
                direct_scattering_acc
                    += L_tf * trans_before * lrgb * spill * 0.45;
            }
        }
#endif

#if defined COLORED_LIGHTS && defined COLORED_LIGHTS_CLOUDS
        if (d_cu > eps) {
            float lpv_step_transmittance;
            float dynamic_thickness = mix(
                0.5,
                1.0,
                smoothstep(
                    0.4,
                    0.6,
                    dot(clouds_params.l0_coverage, vec2(0.25, 0.75))
                )
            );
            lpv_scattering
                += clouds_cumulus_lpv_scattering(
                       ray_pos,
                       air_viewer_pos,
                       ray_origin,
                       distance_to_terrain,
                       d_cu,
                       step_length,
                       clouds_params.l0_detail_weights,
                       clouds_params.l0_edge_sharpening,
                       dynamic_thickness,
                       hash,
                       lit_cu,
                       lpv_step_transmittance
                   )
                * trans_before;
        }
#endif

        lightning_accum += lightning_flash_cloud_sample_intensity(
            ray_pos - air_viewer_pos,
            Ttot,
            trans_before
        );

        transmittance = trans_before * Ttot;

        float w_dist = d_cu;
#ifdef CLOUDS_ALTOCUMULUS
        w_dist += d_al;
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
        w_dist += d_to;
#endif
#ifdef CLOUDS_THUNDERHEAD
        w_dist += d_th;
#endif
        if (w_dist > eps) {
            distance_sum += dist_to_sample * w_dist;
            distance_weight_sum += w_dist;
        }
    }

    float clouds_transmittance
        = linear_step(min_transmittance, 1.0, transmittance);
    clouds_transmittance = clouds_stabilize_immersed_transmittance(
        clouds_transmittance,
        immersion
    );
    float sky_fill = 1.0 + 0.14 * dampen(immersion);
    vec3 clouds_scattering
        = direct_scattering_acc + sky_scattering_acc * sky_color * sky_fill;
    clouds_scattering = clouds_aerial_perspective_immersed(
        clouds_scattering,
        clouds_transmittance,
        distance_to_terrain,
        air_viewer_pos,
        ray_origin,
        ray_dir,
        clear_sky,
        immersion
    );
    clouds_scattering += lpv_scattering;

    float apparent_distance = (distance_weight_sum == 0.0)
        ? 1e6
        : (distance_sum / distance_weight_sum)
            + distance(air_viewer_pos, ray_origin);

    CloudsResult vol_result = CloudsResult(
        vec4(clouds_scattering, sky_scattering_acc),
        clouds_transmittance,
        apparent_distance,
        lightning_accum
    );

#ifdef CLOUDS_CIRRUS
    if (cov_ci) {
        CloudsResult ci_result = draw_cirrus_clouds(
            air_viewer_pos,
            ray_dir,
            clear_sky,
            distance_to_terrain,
            dither
        );
        bool vol_hit = vol_result.transmittance < 1.0 - 1e-4
            || max_of(vol_result.scattering.rgb) > 1e-6
            || vol_result.lightning_intensity > 1e-6;
        bool ci_hit = ci_result.transmittance < 1.0 - 1e-4
            || max_of(ci_result.scattering.rgb) > 1e-6;
        if (!vol_hit && !ci_hit) {
            return clouds_not_hit;
        }
        if (!vol_hit) {
            return ci_result;
        }
        if (!ci_hit) {
            return vol_result;
        }
        return blend_layers(vol_result, ci_result, 1u);
    }
#endif

    return vol_result;
}

#endif // INCLUDE_SKY_CLOUDS_UNIFIED_CONVECTIVE_STACK
