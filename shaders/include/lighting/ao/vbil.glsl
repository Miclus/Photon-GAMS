// Modified version of GT-VBGI (diffuse) by TinyTexel on Shadertoy
// https://www.shadertoy.com/view/lfdBWn
// Ported from Photon-GAMS by SW-52, -Daytendo64-, OUdefie17, Arona74, Miclus and CChex

#if !defined INCLUDE_LIGHTING_AO_VBIL
#define INCLUDE_LIGHTING_AO_VBIL

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/space_conversion.glsl"

const float vbil_thickness = 0.2;
const float ao_radius_ratio = 0.3;
const uint VBIL_HORIZON_BITS = 32u;
const float rcp_VBIL_HORIZON_BITS = 1.0 / float(VBIL_HORIZON_BITS);

float slice_rel_cdf_cos(float x, float ang_n, float cos_n) {
    if (x <= 0.0 || x >= 1.0) {
        return x;
    }

    float phi = x * pi - half_pi;
    bool c = phi > ang_n;

    float n0 = c ? 3.0 : 1.0;
    float n1 = c ? -1.0 : 1.0;
    float n2 = c ? 4.0 : 0.0;

    float t0 = n0 * cos_n + n1 * cos(ang_n - 2.0 * phi)
        + (n2 * ang_n + (n1 * 2.0) * phi + pi) * sin(ang_n);
    float t1 = 4.0 * (cos_n + ang_n * sin(ang_n));

    return clamp01(t0 / t1);
}

vec4 compute_vbil(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_normal,
    vec4 dither,
    bool is_lod,
    sampler2D colortex5
) {
    float ao = 0.0;
    vec3 gi = vec3(0.0);

    // Construct local working space
    vec3 viewer_dir = normalize(-view_pos);
    vec3 viewer_right = normalize(cross(vec3(0.0, 1.0, 0.0), viewer_dir));
    vec3 viewer_up = cross(viewer_dir, viewer_right);
    mat3 local_to_view = mat3(viewer_right, viewer_up, viewer_dir);

    // Reduce AO radius very close up, makes some screen-space artifacts less
    // obvious
    float ao_radius = max(
        0.25 + 0.75 * smoothstep(0.0, 10.0, length_squared(view_pos)),
        0.5
    );

    float step_size = (VBIL_RADIUS * rcp(float(VBIL_STEPS))) * ao_radius;

    for (int s = 0; s < VBIL_SLICES; ++s) {
        float slice_angle = (s + dither.x) * (pi / float(VBIL_SLICES));
        vec3 slice_dir = vec3(cos(slice_angle), sin(slice_angle), 0.0);
        vec3 view_slice_dir = local_to_view * slice_dir;

        vec3 slice_n = cross(viewer_dir, view_slice_dir);
        vec3 proj_n = view_normal - slice_n * dot(view_normal, slice_n);

        float proj_n_sqr_len = dot(proj_n, proj_n);
        if (proj_n_sqr_len < eps) {
            ao += 1.0;
            continue;
        }

        float proj_n_rcp_len = inversesqrt(proj_n_sqr_len);
        float cos_n = dot(proj_n, viewer_dir) * proj_n_rcp_len;

        vec3 tangent = cross(slice_n, proj_n);
        float sgn = dot(viewer_dir, tangent) < 0.0 ? -1.0 : 1.0;
        float ang_n = sgn * fast_acos(cos_n);
        float offset = ang_n * rcp_pi + 0.5;

        uint occlusion_mask = 0u;
        vec3 total_radiance = vec3(0.0);
        float slice_occlusion_ao = 0.0;

        float max_ao_dist = (VBIL_RADIUS * ao_radius) * ao_radius_ratio;

        vec2 ray_step_base
            = (view_to_screen_space(
                   view_pos + view_slice_dir * step_size,
                   true,
                   is_lod
               )
               - screen_pos)
                  .xy;

        for (float d = -1.0; d <= 1.0; d += 2.0) {
            vec2 ray_step = ray_step_base * d;

            vec2 ray_pos = screen_pos.xy
                + ray_step
                    * (dither.z
                       + max_of(view_pixel_size) * rcp_length(ray_step));

            for (int i = 0; i < VBIL_STEPS; ++i, ray_pos += ray_step) {
                if (clamp01(ray_pos) != ray_pos) {
                    break;
                }

                ivec2 texel
                    = ivec2(ray_pos * view_res * taau_render_scale - 0.5);
                float depth = texelFetch(combined_depth_tex, texel, 0).x;

                if (depth == 1.0 || depth < hand_depth
                    || depth == screen_pos.z) {
                    continue;
                }

                vec3 sample_view_pos = screen_to_view_space(
                    combined_projection_matrix_inverse,
                    vec3(ray_pos, depth),
                    true
                );
                vec3 delta_pos_front = sample_view_pos - view_pos;
                vec3 delta_pos_back = delta_pos_front
                    + normalize(sample_view_pos) * vbil_thickness;

                vec2 horizon_cos = vec2(
                    dot(normalize(delta_pos_front), viewer_dir),
                    dot(normalize(delta_pos_back), viewer_dir)
                );

                vec2 horizon_angle = fast_acos(horizon_cos) * d;
                horizon_angle = clamp01(horizon_angle * rcp_pi + offset);

                if (d < 0.0) {
                    horizon_angle = horizon_angle.yx;
                }
                if (horizon_angle.x > horizon_angle.y) {
                    horizon_angle = horizon_angle.yx;
                }

                horizon_angle.x
                    = slice_rel_cdf_cos(horizon_angle.x, ang_n, cos_n);
                horizon_angle.y
                    = slice_rel_cdf_cos(horizon_angle.y, ang_n, cos_n);

                horizon_angle
                    = clamp01(horizon_angle + dither.w * (1.0 / 32.0));

                uvec2 horizon_int = uvec2(horizon_angle * 32.0);
                uint mask_end
                    = horizon_int.x < 32u ? 0xFFFFFFFFu << horizon_int.x : 0u;
                uint mask_start = horizon_int.y != 0u
                    ? 0xFFFFFFFFu >> (32u - horizon_int.y)
                    : 0u;
                uint step_mask = mask_end & mask_start;

                uint visible_bits = step_mask & (~occlusion_mask);

                if (visible_bits != 0u) {
                    float visibility
                        = float(bitCount(visible_bits)) * rcp_VBIL_HORIZON_BITS;
#if !defined(PHOTONICS_IN_USE) || VBIL_GI_I > 0.0
                        vec3 radiance = textureLod(colortex5, ray_pos, 0.0).rgb;
                        total_radiance += radiance * visibility;
#endif

#if VBIL_RADIUS > 1.0
                    float hit_dist = length(delta_pos_front);
                    float ao_falloff = clamp01(1.0 - hit_dist / max_ao_dist);
                    slice_occlusion_ao += ao_falloff * visibility;
#endif
                }

                occlusion_mask |= step_mask;
            }
        }

        float occlusion = float(bitCount(occlusion_mask)) * (1.0 / 32.0);

#if VBIL_RADIUS > 1.0
        ao += 1.0 - slice_occlusion_ao;
#else
        ao += 1.0 - occlusion;
#endif
#if !defined(PHOTONICS_IN_USE) || VBIL_GI_I > 0.0
        gi += total_radiance;
#endif
    }

    float normalization = rcp(float(VBIL_SLICES));
    ao *= normalization;
    gi *= normalization;

    // Multi-bounce approximation for AO & GI (GTAO style)
    const float albedo = 0.2;
    ao /= albedo * ao + (1.0 - albedo);
    gi /= albedo * gi + (1.0 - 1.8 * albedo);

    return vec4(clamp01(ao), clamp01(gi * VBIL_GI_I));
}

#endif // INCLUDE_LIGHTING_AO_VBIL
