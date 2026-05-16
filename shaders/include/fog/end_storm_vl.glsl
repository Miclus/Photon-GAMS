#ifndef INCLUDE_FOG_END_STORM_VL
#define INCLUDE_FOG_END_STORM_VL

#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/phase_functions.glsl"
#include "/include/utility/random.glsl"

float end_storm_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float end_storm_density(vec3 wp) {
    const float ceiling_y = END_STORM_FOG_CEILING_Y;
    const float floor_y = END_STORM_FOG_FLOOR_Y;
    const float height_span = ceiling_y - floor_y;

    float bump_k = clamp(END_STORM_FOG_BUMPINESS, 0.0, 2.0);

    vec3 wind_fast = vec3(0.019, 0.011, 0.016) * END_STORM_FOG_SPEED * frameTimeCounter;
    vec3 wind_slow = wind_fast * 0.45;

    float thickness = max(END_STORM_FOG_LAYER_THICKNESS, 4.0);

    vec3 ceil_uv = vec3(wp.xz * 0.00162, wind_slow.x * 2.1 + wind_slow.z * 1.4);
    float ceil_coarse = texture(colortex0, ceil_uv + vec3(19.0, 37.0, 11.0)).x;
    float ceil_fine = texture(colortex0, wp * vec3(0.0026, 0.0024, 0.0048) + wind_fast * 0.42).x;
    float ceil_roll = ((ceil_coarse - 0.5) * 44.0 + (ceil_fine - 0.5) * 8.0) * bump_k;

    vec3 floor_uv = vec3(wp.xz * 0.00148 + vec2(211.0, 147.0), wind_slow.y * 1.9 - wind_slow.z);
    float floor_coarse = texture(colortex0, floor_uv + vec3(61.0, 23.0, 17.0)).x;
    float floor_roll = ((floor_coarse - 0.5) * 40.0 + (ceil_fine - 0.5) * 7.0) * bump_k;

    float ceil_y_eff = ceiling_y + ceil_roll;
    float floor_y_eff = floor_y + floor_roll;

    float slab_wave_t = frameTimeCounter * END_STORM_FOG_SPEED * 5.0;
    vec2 slab_wave_pos = wp.xz * 0.0505;
    float slab_wave_a = sin(dot(slab_wave_pos, vec2(0.78, 0.63)) + slab_wave_t * 0.42);
    float slab_wave_b = sin(dot(slab_wave_pos, vec2(-0.44, 0.91)) - slab_wave_t * 0.31);
    float slab_wave = (slab_wave_a * 0.62 + slab_wave_b * 0.38) * 13.6 * bump_k;
    ceil_y_eff += slab_wave;
    floor_y_eff += slab_wave * 0.82;

    vec3 mega_w = wind_slow * 0.11;
    float ceil_mega = texture(
            colortex0,
            wp * vec3(0.00038, 0.00036, 0.00032) + mega_w + vec3(3.0, 7.0, 11.0)
        )
        .x;
    float ceil_broad = texture(
            colortex0,
            wp * vec3(0.00095, 0.00092, 0.00078) + mega_w * 1.15 + vec3(19.0, 13.0, 5.0)
        )
        .x;
    float floor_mega = texture(
            colortex0,
            wp * vec3(0.00041, 0.00039, 0.00033) + mega_w + vec3(101.0, 67.0, 29.0)
        )
        .x;
    float floor_broad = texture(
            colortex0,
            wp * vec3(0.00098, 0.00102, 0.00081) + mega_w * 1.12 + vec3(53.0, 91.0, 17.0)
        )
        .x;

    float ceil_lift = ((ceil_mega - 0.5) * 102.0 + (ceil_broad - 0.5) * 44.0) * bump_k;
    float floor_lift = ((floor_mega - 0.5) * 92.0 + (floor_broad - 0.5) * 40.0) * bump_k;
    ceil_y_eff += ceil_lift;
    floor_y_eff += floor_lift;

    float thick_mod = mix(
        1.0,
        mix(0.9, 1.14, smoothstep(0.18, 0.82, texture(colortex0, wp * 0.0075 + wind_slow * 0.55).x)),
        bump_k
    );

    float ceil_corrug = smoothstep(0.14, 0.86, ceil_mega * 0.52 + ceil_broad * 0.48);
    float floor_corrug = smoothstep(0.14, 0.86, floor_mega * 0.52 + floor_broad * 0.48);
    float thick_c_scale = mix(1.0, mix(0.58, 1.72, ceil_corrug), bump_k);
    float thick_f_scale = mix(1.0, mix(0.58, 1.72, floor_corrug), bump_k);

    float thick_c = thickness * thick_mod * mix(1.0, mix(0.88, 1.12, ceil_fine), bump_k) * thick_c_scale;
    float thick_f = thickness * thick_mod * mix(1.0, mix(0.88, 1.12, ceil_fine), bump_k) * thick_f_scale;

    float spacing = max(END_STORM_FOG_SPACING, 32.0);
    vec2 xz = wp.xz;
    vec2 base = floor(xz / spacing);
    float funnel_best = 0.0;
    float wrap_shell = 0.0;
    float vortex_shell = 0.0;

    float y_norm = clamp((wp.y - floor_y) / height_span, 0.0, 1.0);
    float r_top = spacing * 0.7;
    float r_bot = spacing * 0.05;
    float base_allowed_r = mix(r_bot, r_top, y_norm);

    for (int dz = -3; dz <= 3; ++dz) {
        for (int dx = -3; dx <= 3; ++dx) {
            vec2 cid = base + vec2(dx, dz);
            vec2 cid_center = (cid + vec2(0.5)) * spacing;
            if (distance(xz, cid_center) > spacing * 5.0) {
                continue;
            }
            if (end_storm_hash(cid + vec2(59.1, 83.4)) > END_STORM_FOG_TORNADO_COVERAGE) {
                continue;
            }

            float h = end_storm_hash(cid);
            float h2 = end_storm_hash(cid + vec2(41.2, 73.9));
            float h3 = end_storm_hash(cid + vec2(127.0, 311.0));
            float h4 = end_storm_hash(cid + vec2(503.0, 149.0));
            float h5 = end_storm_hash(cid + vec2(281.0, 53.0));
            float h6 = end_storm_hash(cid + vec2(97.0, 421.0));
            float h7 = end_storm_hash(cid + vec2(619.0, 337.0));
            float h8 = end_storm_hash(cid + vec2(733.0, 197.0));
            float h9 = end_storm_hash(cid + vec2(389.0, 587.0));
            float h10 = end_storm_hash(cid + vec2(859.0, 271.0));
            float h11 = end_storm_hash(cid + vec2(467.0, 149.0));
            float h12 = end_storm_hash(cid + vec2(941.0, 613.0));
            float h13 = end_storm_hash(cid + vec2(521.0, 827.0));
            float h14 = end_storm_hash(cid + vec2(173.0, 953.0));

            float spin_dir = mix(-1.0, 1.0, step(0.5, end_storm_hash(cid + vec2(211.0, 93.0))));
            float amble_dir = mix(-1.0, 1.0, step(0.5, end_storm_hash(cid + vec2(17.0, 244.0))));

            float t = END_STORM_FOG_SPEED * frameTimeCounter;

            float w_spin = 0.084 + h2 * 0.058;
            float w_amble = 0.031 + h3 * 0.024;

            float ang_spin = t * w_spin * spin_dir + h * 6.2831853;
            float ang_amble = t * w_amble * amble_dir + h2 * 6.2831853;

            float size_shape = mix(0.68, 0.98, h12);
            float rope_r = mix(spacing * (0.016 + 0.018 * h4), spacing * (0.12 + 0.04 * h6), pow(y_norm, size_shape));
            float mid_r = rope_r * 3.0;
            float wedge_r = mid_r * 3.0;
            float mega_wedge_r = wedge_r * 3.0;

            float rope_w = 1.0 - smoothstep(0.22, 0.42, h11);
            float mega_wedge_w = smoothstep(0.96, 0.99, h11);
            float wedge_w = smoothstep(0.82, 0.90, h11) * (1.0 - mega_wedge_w);
            float mid_w = clamp(1.0 - rope_w - wedge_w - mega_wedge_w, 0.0, 1.0);
            float allowed_r = rope_r * rope_w + mid_r * mid_w + wedge_r * wedge_w + mega_wedge_r * mega_wedge_w;
            allowed_r = max(allowed_r, base_allowed_r * 0.35);
            float travel_scale = mix(1.0, 0.52, smoothstep(spacing * 0.72, spacing * 1.8, allowed_r));

            float lifecycle_mask = 1.0;
            float lifecycle_u = 0.5;
            const float form_end = 0.38;
            const float hold_end = 0.90;
            bool lifecycle_grounded = true;
            bool lifecycle_dissipating = false;
            if (h13 > 0.54) {
                float lifecycle_period = mix(72.0, 156.0, h14);
                lifecycle_u = fract(t / lifecycle_period + h13 * 2.7 + h14 * 1.9);
                const float lifecycle_soft = 0.055;

                if (lifecycle_u < form_end) {
                    float p = smoothstep(0.0, 1.0, lifecycle_u / form_end);
                    float cutoff = mix(1.02, -0.06, p);
                    lifecycle_mask = smoothstep(cutoff - lifecycle_soft, cutoff + lifecycle_soft, y_norm);
                    lifecycle_grounded = p > 0.96;
                } else if (lifecycle_u < hold_end) {
                    lifecycle_mask = 1.0;
                } else {
                    float p = smoothstep(0.0, 1.0, (lifecycle_u - hold_end) / (1.0 - hold_end));
                    float cutoff = mix(-0.06, 1.02, p);
                    lifecycle_mask = smoothstep(cutoff - lifecycle_soft, cutoff + lifecycle_soft, y_norm);
                    lifecycle_dissipating = true;
                }
            }

            vec2 center = (cid + vec2(0.5)) * spacing;

            center += (vec2(h, h2) - vec2(0.5)) * spacing * 0.94;
            center += (vec2(h3, h4) - vec2(0.5)) * spacing * 0.41;

            float wander_x_freq = 0.038 + 0.019 * h2;
            float wander_z_freq = 0.034 + 0.021 * h3;
            float wander_x_phase = t * wander_x_freq + h * 6.18;
            float wander_z_phase = t * wander_z_freq + h * 4.92;
            float wander_amp = spacing * (0.66 + 0.46 * h4) * travel_scale;
            vec2 wander = vec2(cos(wander_x_phase), sin(wander_z_phase)) * wander_amp;
            center += wander;

            float roam_freq_a = mix(0.004, 0.014, h5);
            float roam_freq_b = mix(0.006, 0.018, h6);
            float steer_freq = mix(0.008, 0.024, h7);
            float meander_freq = mix(0.014, 0.042, h8);
            float drift_freq = mix(0.003, 0.010, h9);

            float roam_phase_a = t * roam_freq_a + h5 * 6.2831853;
            float roam_phase_b = t * roam_freq_b + h6 * 6.2831853;
            float steer_phase = t * steer_freq + h7 * 6.2831853;
            float meander_phase = t * meander_freq + h8 * 6.2831853;
            float drift_phase = t * drift_freq + h9 * 6.2831853;

            float flow_angle
                = h10 * 6.2831853
                + sin(roam_phase_a) * mix(0.7, 1.8, h11)
                + sin(roam_phase_b) * mix(0.45, 1.35, h12)
                + sin(steer_phase) * mix(0.2, 0.9, h4);
            float steer_angle
                = flow_angle
                + sin(meander_phase) * mix(0.55, 1.7, h3)
                + cos(steer_phase * 0.73 + h2 * 4.6) * mix(0.25, 0.95, h6);
            float drift_angle
                = steer_angle
                + sin(drift_phase + h * 3.1) * mix(0.35, 1.25, h7);

            vec2 flow_dir = vec2(cos(flow_angle), sin(flow_angle));
            vec2 steer_dir = vec2(cos(steer_angle), sin(steer_angle));
            vec2 drift_dir = vec2(cos(drift_angle), sin(drift_angle));
            vec2 cross_dir = vec2(-steer_dir.y, steer_dir.x);

            float roam_amp_a = spacing * mix(0.18, 0.88, h8) * travel_scale;
            float roam_amp_b = spacing * mix(0.10, 0.72, h9) * travel_scale;
            float meander_amp = spacing * mix(0.06, 0.44, h10) * travel_scale;
            float drift_amp = spacing * mix(0.08, 0.52, h11) * travel_scale;

            vec2 roaming_path
                = flow_dir * (sin(roam_phase_a + sin(steer_phase) * 0.7) * roam_amp_a)
                + steer_dir * (sin(roam_phase_b + cos(meander_phase) * 0.9) * roam_amp_b)
                + cross_dir * (sin(meander_phase + sin(drift_phase) * 0.8) * meander_amp)
                + drift_dir * (sin(drift_phase + cos(roam_phase_a) * 0.75) * drift_amp);
            center += roaming_path;

            float orbit_primary = spacing * (0.088 + 0.048 * h2) * travel_scale;
            center += vec2(cos(ang_spin), sin(ang_spin)) * orbit_primary;

            float orbit_secondary_phase = ang_spin * 0.41 + h * 4.2;
            float orbit_secondary_amp = spacing * (0.058 + 0.042 * h3) * travel_scale;
            center += vec2(cos(orbit_secondary_phase), sin(orbit_secondary_phase)) * orbit_secondary_amp;

            float amble_x_phase = ang_amble + h * 2.7;
            float amble_z_phase = ang_amble + h * 2.1;
            float amble_amp = spacing * (0.038 + 0.032 * h2) * travel_scale;
            center += vec2(cos(amble_x_phase), sin(amble_z_phase)) * amble_amp;

            vec2 motion = vec2(
                    -sin(wander_x_phase) * wander_x_freq,
                    cos(wander_z_phase) * wander_z_freq
                )
                * wander_amp;
            motion += flow_dir * (cos(roam_phase_a + sin(steer_phase) * 0.7) * roam_amp_a * roam_freq_a);
            motion += steer_dir * (cos(roam_phase_b + cos(meander_phase) * 0.9) * roam_amp_b * roam_freq_b);
            motion += cross_dir * (cos(meander_phase + sin(drift_phase) * 0.8) * meander_amp * meander_freq * 0.8);
            motion += drift_dir * (cos(drift_phase + cos(roam_phase_a) * 0.75) * drift_amp * drift_freq);
            motion += vec2(-sin(ang_spin), cos(ang_spin)) * orbit_primary * w_spin * spin_dir;
            motion += vec2(-sin(orbit_secondary_phase), cos(orbit_secondary_phase))
                * orbit_secondary_amp
                * w_spin
                * spin_dir
                * 0.41;
            motion += vec2(-sin(amble_x_phase), cos(amble_z_phase)) * amble_amp * w_amble * amble_dir;

            vec2 bend_dir = normalize_safe(motion);
            float bottom_bend = pow(1.0 - y_norm, 1.55);
            vec2 bend_offset = bend_dir * spacing * 1.0 * bottom_bend * mix(1.0, 0.72, 1.0 - travel_scale);
            center += bend_offset;

            vec2 rel = xz - center;

            float shear_bottom_heavy = mix(1.08, 0.52, pow(y_norm, 1.15));
            float bend_follow = smoothstep(0.0, 0.85, bottom_bend);
            float bend_angle = atan(bend_dir.y, bend_dir.x);
            float bend_stream = dot(rel, bend_dir) * rcp(max(spacing * 0.38, 1.0));
            float helix_turn = t * (0.118 + h2 * 0.055) * shear_bottom_heavy * max(y_norm, 0.08)
                * spin_dir;
            helix_turn += bend_follow * (bend_angle * 0.34 + bend_stream * 0.92) * spin_dir;

            float ch = cos(helix_turn);
            float sh = sin(helix_turn);
            vec2 rel_r = vec2(ch * rel.x - sh * rel.y, sh * rel.x + ch * rel.y);

            float dist = length(rel_r);
            float influence_r = allowed_r * 1.42 + max(spacing * 0.04, 4.0);
            if (dist > influence_r) {
                continue;
            }

            float core = 1.0 - smoothstep(0.0, allowed_r * 0.92, dist);
            core *= lifecycle_mask;

            float swirl_angle = atan(rel_r.y, rel_r.x);
            float swirl_phase = swirl_angle * 3.0
                + y_norm * 10.5
                + bend_follow * (bend_stream * 2.6 + bend_angle * 0.65)
                - t * (0.42 + 0.18 * h2) * spin_dir;
            float swirl_band = 0.5 + 0.5 * sin(swirl_phase);

            vec3 twist_uv = vec3(
                (wp.xz - bend_offset * 0.42) * 0.0095
                    + vec2(helix_turn * 0.06 + ang_spin * 0.025, -helix_turn * 0.045),
                wp.y * 0.0075 + helix_turn * 0.015
            );
            float twist = texture(colortex0, twist_uv + wind_slow * 0.7).x;
            float swirl_shape = smoothstep(0.18, 0.82, swirl_band * 0.72 + twist * 0.28);
            core *= mix(1.0, mix(0.72, 1.22, swirl_shape), bump_k);

            funnel_best = max(funnel_best, core);

            float u = dist / max(allowed_r * 0.92, 1.0);
            float shell = (1.0 - smoothstep(0.12, 1.08, u)) * core;
            wrap_shell = max(wrap_shell, shell);

            for (int vortex_slot = 0; vortex_slot < 3; ++vortex_slot) {
                if (max(wedge_w, mega_wedge_w) <= 0.01 || !lifecycle_grounded || lifecycle_dissipating) {
                    continue;
                }
                float slot = float(vortex_slot);
                vec2 slot_seed = cid + vec2(37.1 + slot * 91.7, 19.4 + slot * 53.3);

                float period_hash = end_storm_hash(slot_seed + vec2(4.7, 81.2));
                float vortex_t = t * 0.5;
                float period = mix(11.0, 23.0, period_hash);
                float cycle = floor(vortex_t / period + slot * 0.37 + h3 * 1.7);
                float life = fract(vortex_t / period + slot * 0.37 + h3 * 1.7);

                float active_hash = end_storm_hash(slot_seed + vec2(cycle * 23.1, cycle * 41.7));
                float active_strength = 1.0 - smoothstep(0.72, 0.96, active_hash);
                if (active_strength <= 0.001) {
                    continue;
                }

                float fade = smoothstep(0.0, 0.26, life) * (1.0 - smoothstep(0.64, 1.0, life));
                fade *= active_strength;
                if (fade <= 0.001) {
                    continue;
                }

                float y_center = 0.04 + 0.92 * end_storm_hash(slot_seed + vec2(cycle * 7.3, 3.1));
                float y_travel = 0.04 + 0.18 * end_storm_hash(slot_seed + vec2(5.9, cycle * 13.7));
                float vortex_y = y_center + y_travel * (life - 0.5);

                float vertical_width = mix(0.006, 0.012, end_storm_hash(slot_seed + vec2(12.8, cycle * 2.9)));
                float vertical_band = exp(-0.5 * pow((y_norm - vortex_y) / vertical_width, 2.0));

                float vortex_r = max(allowed_r, spacing * 0.14);
                float ring_radius = vortex_r * mix(0.98, 1.34, end_storm_hash(slot_seed + vec2(8.2, cycle * 5.4)));
                float radial_width = max(vortex_r * mix(0.012, 0.024, h4), 1.4);
                float radial_band = exp(-0.5 * pow((dist - ring_radius) / radial_width, 2.0));

                float arc_base = end_storm_hash(slot_seed + vec2(cycle * 17.0, 27.5)) * 6.2831853;
                float arc_speed = (0.42 + 0.24 * active_hash) * spin_dir;
                float arc_angle = arc_base
                    + bend_follow * bend_angle * 0.55
                    + vortex_t * arc_speed
                    + life * mix(0.8, 1.9, h2) * spin_dir;
                float angle_delta = abs(atan(sin(swirl_angle - arc_angle), cos(swirl_angle - arc_angle)));
                float arc_len_hash = end_storm_hash(slot_seed + vec2(31.0, cycle * 9.2));
                float arc_width = mix(0.06, 0.24, sqr(arc_len_hash));
                float arc_band = 1.0 - smoothstep(arc_width, arc_width * 1.9, angle_delta);

                float upward_swirl = smoothstep(-0.06, 0.12, vortex_y) * (1.0 - smoothstep(0.92, 1.08, vortex_y));
                float vortex = radial_band * vertical_band * arc_band * fade * upward_swirl;
                vortex_shell = max(vortex_shell, vortex * mix(0.58, 0.95, active_strength));
            }
        }
    }

    float wrap_blend = clamp(wrap_shell * 1.08, 0.0, 1.0);
    float thick_c_wrap = thick_c * (1.0 + 0.92 * wrap_blend);
    float thick_f_wrap = thick_f * (1.0 + 0.92 * wrap_blend);

    float ceiling_blob = exp(
        -0.5 * pow((wp.y - ceil_y_eff) / max(thick_c_wrap, 1.0), 2.0)
    );
    float floor_blob = exp(
        -0.5 * pow((wp.y - floor_y_eff) / max(thick_f_wrap, 1.0), 2.0)
    );

    float collar_r_top = max(thick_c_wrap * 0.36, 2.0);
    float collar_r_bot = max(thick_f_wrap * 0.36, 2.0);
    float collar_top
        = wrap_blend
        * exp(-0.5 * pow((wp.y - ceil_y_eff) / collar_r_top, 2.0));
    float collar_bot
        = wrap_blend
        * exp(-0.5 * pow((wp.y - floor_y_eff) / collar_r_bot, 2.0));

    float slab_core = max(ceiling_blob, floor_blob);
    float slab_wrap = max(slab_core, max(collar_top, collar_bot) * 0.96);

    float puff = mix(
        1.0,
        mix(
            0.9,
            1.08,
            smoothstep(0.18, 0.82, texture(colortex0, wp * vec3(0.008, 0.0075, 0.010) + wind_slow * 0.8).x)
        ),
        bump_k
    );

    vec3 bump_uv_lo = wp * vec3(0.017, 0.016, 0.019) + wind_slow * 0.72;
    vec3 bump_uv_hi = wp * vec3(0.026, 0.024, 0.028) + wind_fast * 0.34;
    float bump_lo = texture(colortex0, bump_uv_lo).x;
    float bump_hi = texture(colortex0, bump_uv_hi).x;
    float bump_mix = smoothstep(0.16, 0.84, bump_lo) * 0.76 + smoothstep(0.2, 0.8, bump_hi) * 0.24;
    float bump_factor = mix(1.0, mix(0.9, 1.1, bump_mix), bump_k);

    float layers = slab_wrap * puff * bump_factor;

    float w0 = texture(colortex0, wp * 0.0085 + wind_slow * 0.65).x;
    float w1 = texture(colortex0, wp * vec3(0.014, 0.011, 0.013) + wind_fast * 0.36).x;
    float wisps_raw = clamp(mix(0.86, 1.06, smoothstep(0.18, 0.82, w0 * 0.72 + w1 * 0.28)), 0.82, 1.04);
    float wisps = mix(1.0, wisps_raw, bump_k);

    float bridge = layers * wisps * 1.52
        + funnel_best * wisps * (1.28 + 0.42 * wrap_blend)
        + vortex_shell * wisps * 1.15;
    return bridge * END_STORM_FOG_INTENSITY * 0.095;
}

#if defined END_STORM_FOG_LIGHTNING_ENABLE
float end_storm_lightning_flash(vec3 world_pos, float density) {
    if (density < 0.0002) {
        return 0.0;
    }

    const float vol_top = END_STORM_FOG_CEILING_Y;
    const float vol_bot = END_STORM_FOG_FLOOR_Y;
    const float cell_size = max(5200.0, END_STORM_FOG_SPACING * 3.5);

    vec3 flash_space = world_pos;
    flash_space.xz += vec2(0.048, 0.036) * END_STORM_FOG_SPEED * frameTimeCounter;

    vec2 grid_pos = flash_space.xz / cell_size;
    vec2 cell_id = floor(grid_pos);

    float flash_speed = max(END_STORM_FOG_LIGHTNING_SPEED, 0.05);

    float total_lightning = 0.0;

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

            float dx = flash_space.x - center_xz.x;
            float dz = flash_space.z - center_xz.y;
            float dy = (world_pos.y - center_y) * 0.49;

            float dist_sq = dx * dx + dz * dz + dy * dy;

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

            float speed = flash_speed;
            float p = flash_progress;

            if (type == 0) {
                float flicker = noise_1d(
                    frameTimeCounter * 80.0 * speed + hash.w * 100.0
                );
                intensity = sin(p * pi) * (0.6 + 0.4 * flicker);
            } else if (type == 1) {
                float p1
                    = smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.3, 0.4, p));
                float p2
                    = smoothstep(0.5, 0.6, p) * (1.0 - smoothstep(0.9, 1.0, p));
                float flicker = noise_1d(frameTimeCounter * 120.0 * speed);
                intensity = (p1 + p2) * (0.8 + 0.2 * flicker);
            } else if (type == 2) {
                float flicker = noise_1d(frameTimeCounter * 40.0 * speed);
                intensity
                    = smoothstep(0.0, 0.1, p) * (1.0 - smoothstep(0.8, 1.0, p));
                intensity *= (0.5 + 0.5 * flicker);
            } else if (type == 3) {
                float p1 = smoothstep(0.0, 0.05, p)
                    * (1.0 - smoothstep(0.15, 0.2, p));
                float p2 = smoothstep(0.3, 0.35, p)
                    * (1.0 - smoothstep(0.45, 0.5, p));
                float p3 = smoothstep(0.6, 0.65, p)
                    * (1.0 - smoothstep(0.75, 0.8, p));
                intensity = (p1 + p2 + p3)
                    * (0.9 + 0.1 * noise_1d(frameTimeCounter * 150.0 * speed));
            } else if (type == 4) {
                float flicker = noise_1d(
                    frameTimeCounter * 200.0 * speed + hash.y * 50.0
                );
                float envelope
                    = smoothstep(0.0, 0.2, p) * (1.0 - smoothstep(0.4, 0.9, p));
                intensity = step(0.5, flicker) * envelope;
            } else {
                float flicker = noise_1d(frameTimeCounter * 60.0 * speed);
                float envelope = pow(p, 3.0) * (1.0 - smoothstep(0.8, 1.0, p));
                intensity = envelope * (0.7 + 0.3 * flicker) * 2.0;
            }

            total_lightning += falloff * intensity;
        }
    }

    return total_lightning;
}
#endif

mat2x3 raymarch_end_storm_fog(
    vec3 world_start_pos,
    vec3 world_end_pos,
    bool sky,
    float dither
) {
    const float volume_top = END_STORM_FOG_CEILING_Y;
    const float volume_bottom = END_STORM_FOG_FLOOR_Y;

    vec3 world_dir = world_end_pos - world_start_pos;
    float ray_length;
    length_normalize(world_dir, world_dir, ray_length);

    float distance_to_lower_plane = (volume_bottom - eyeAltitude) / world_dir.y;
    float distance_to_upper_plane = (volume_top - eyeAltitude) / world_dir.y;
    float distance_to_volume_start;
    float distance_to_volume_end;

    if (eyeAltitude < volume_bottom) {
        distance_to_volume_start = distance_to_lower_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? -1.0 : distance_to_upper_plane;
    } else if (eyeAltitude < volume_top) {
        distance_to_volume_start = 0.0;
        distance_to_volume_end = world_dir.y < 0.0
            ? distance_to_lower_plane
            : distance_to_upper_plane;
    } else {
        distance_to_volume_start = distance_to_upper_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? distance_to_upper_plane : -1.0;
    }

    if (distance_to_volume_end < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    ray_length = sky ? distance_to_volume_end : ray_length;
    float ray_cap = far * END_STORM_FOG_VIEW_DISTANCE_SCALE;
    ray_length = clamp(ray_length - distance_to_volume_start, 0.0, ray_cap);

    if (ray_length < eps) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    const uint min_steps = 10u;
    const uint max_steps = 24u;
    const float growth = 0.065;

    uint step_count = uint(float(min_steps) + growth * ray_length);
    step_count = clamp(step_count, min_steps, max_steps);

    float step_length = ray_length * rcp(float(step_count));
    vec3 world_step = world_dir * step_length;

    vec3 world_pos = world_start_pos
        + world_dir * (distance_to_volume_start + step_length * dither);

    vec3 sand = from_srgb(
        vec3(END_STORM_FOG_R, END_STORM_FOG_G, END_STORM_FOG_B)
    );
    vec3 shadow_tint = sand * vec3(0.28, 0.24, 0.22);

    float LoV = dot(world_dir, light_dir);
    vec3 wind_uv = vec3(0.014, 0.009, 0.012) * END_STORM_FOG_SPEED * frameTimeCounter;

    vec3 scattering = vec3(0.0);
    vec3 transmittance = vec3(1.0);

    const float layer_th = max(END_STORM_FOG_LAYER_THICKNESS, 4.0);
    const float shaft_strength = 40.0;
    float sky_edge_start = ray_cap * 0.8;
    float sky_edge_end = ray_cap * 0.985;
    float sky_horizon_block = sky ? (1.0 - smoothstep(0.10, 0.42, abs(world_dir.y))) : 0.0;

    for (uint i = 0u; i < step_count; ++i) {
        float density = end_storm_density(world_pos);
        float cam_dist = distance(world_pos, cameraPosition);
        if (sky_horizon_block > 0.0) {
            float y_norm = clamp(
                (world_pos.y - volume_bottom) / max(volume_top - volume_bottom, 1.0),
                0.0,
                1.0
            );
            float sky_edge = sqr(smoothstep(sky_edge_start, sky_edge_end, cam_dist));
            float sky_curtain = smoothstep(0.02, 0.22, y_norm) * (1.0 - smoothstep(0.78, 0.98, y_norm));
            density += sky_edge * sky_horizon_block * sky_curtain * END_STORM_FOG_INTENSITY * 0.022;
        }

        vec3 sigma_s = vec3(density);
        vec3 sigma_a = density * vec3(0.32, 0.28, 0.24);
        vec3 extinction = sigma_a + sigma_s;

        vec3 step_optical_depth = extinction * step_length;
        vec3 step_transmittance = exp(-step_optical_depth);
        vec3 step_transmitted_fraction
            = (1.0 - step_transmittance) / max(step_optical_depth, vec3(eps));

        vec3 visible_scattering = step_transmitted_fraction * transmittance;

        float sun_penetration = clamp(exp(-density * shaft_strength), 0.12, 1.0);

        float cw = exp(
            -0.5 * pow((world_pos.y - volume_top) / layer_th, 2.0)
        );
        float fw = exp(
            -0.5 * pow((world_pos.y - volume_bottom) / layer_th, 2.0)
        );
        float layer_sum = cw + fw + 1e-5;
        float ceil_frac = cw / layer_sum;
        float y_norm = clamp(
            (world_pos.y - volume_bottom)
                / max(volume_top - volume_bottom, 1.0),
            0.0,
            1.0
        );
        if (layer_sum < 0.025) {
            ceil_frac = y_norm;
        }

        float sun_elev = clamp(light_dir.y * 0.65 + 0.42, 0.0, 1.0);
        float canopy_light
            = clamp(sun_elev * ceil_frac + mix(0.22, 0.68, 1.0 - ceil_frac), 0.0, 1.0);
        float sun_edge = mix(0.48, 1.38, canopy_light);

        float mie_peaked = henyey_greenstein_phase(LoV, 0.76);
        float mie_soft = henyey_greenstein_phase(LoV, 0.22);
        float phase = 0.62 * mie_peaked + 0.38 * mie_soft;

        vec3 sun_term = light_color * phase * sun_penetration * sun_edge;

        float back_mu = max(-LoV, 0.0);
        vec3 rim_glow = sand * pow(back_mu, 1.4) * sun_penetration * mix(0.1, 0.38, canopy_light);

        float amb_layer = mix(0.13, 0.48, ceil_frac);
        amb_layer *= mix(0.36, 1.02, canopy_light);
        amb_layer *= mix(0.68, 1.0, sun_penetration);

        float depth_vis = mix(1.0, 0.5, 1.0 - exp2(-cam_dist * 0.00026));

        vec3 amb_term = ambient_color * isotropic_phase * amb_layer * (10.5 + 16.5 * depth_vis);

        float grain = texture(colortex0, world_pos * 0.019 + wind_uv * 0.65).x;
        float grain_mod = mix(0.9, 1.08, smoothstep(0.28, 0.72, grain));

        float height_glow = y_norm;
        vec3 local_col = mix(shadow_tint, sand, 0.22 + 0.78 * height_glow);
        local_col *= grain_mod * mix(0.82, 1.12, canopy_light);

        vec3 S = local_col * sigma_s * (sun_term + amb_term + rim_glow);
#if defined END_STORM_FOG_LIGHTNING_ENABLE
        float L_flash = end_storm_lightning_flash(world_pos, density);
        vec3 flash_rgb = vec3(
                END_STORM_FOG_LIGHTNING_COLOR_R,
                END_STORM_FOG_LIGHTNING_COLOR_G,
                END_STORM_FOG_LIGHTNING_COLOR_B
            )
            * END_STORM_FOG_LIGHTNING_INTENSITY;
        float flash_mask = mix(0.14, 1.0, smoothstep(0.0, 0.055, density));
        S += sigma_s * flash_rgb * L_flash * flash_mask;
#endif

        scattering += S * visible_scattering * step_length;
        transmittance *= step_transmittance;

        world_pos += world_step;
    }

    scattering *= 1.22;
    transmittance = pow(transmittance, vec3(1.12));

    return mat2x3(scattering, transmittance);
}

#endif
