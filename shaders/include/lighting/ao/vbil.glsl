// Modified version of HBIL from Photon Legacy, GTAO and GT-VBGI by TinyTexel on Shadertoy
// https://www.shadertoy.com/view/XcdBWf

#if !defined INCLUDE_LIGHTING_AO_VBIL
#define INCLUDE_LIGHTING_AO_VBIL

#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/space_conversion.glsl"

// Configuration
const float vbil_thickness = 0.1;
const float vbil_bias = 0.02;
const uint vbil_bit_count = 32u;
const uint vbil_bit_max = 31u;

int count_bits(uint n) {
    return bitCount(n);
}

// Maps angle range [0, PI] -> [0, 31]
uint angle_to_bit(float angle) {
    float normalized = clamp01(angle * rcp_pi); 
    return min(uint(normalized * 32.0), vbil_bit_max);
}

// Create a bitmask range from start_angle to end_angle
uint create_bit_range(float angle_min, float angle_max) {
    if (angle_min > angle_max) return 0u;
    
    uint start_bit = angle_to_bit(angle_min);
    uint end_bit   = angle_to_bit(angle_max);
    
    // Create mask with 1s from start_bit to end_bit
    // Example: bits 2 to 4 -> (1<<5)-1 ^ (1<<2)-1
    uint mask_end   = (end_bit   == vbil_bit_max) ? 0xFFFFFFFFu : ((1u << (end_bit   + 1u)) - 1u);
    uint mask_start = (start_bit == 0u)           ? 0u          : ((1u <<  start_bit      ) - 1u);
    
    return mask_end ^ mask_start;
}

struct VbilResult {
    vec3 radiance;
    uint occlusion_mask;
};

VbilResult vbil_search(
    vec3 view_slice_dir, 
    vec3 viewer_dir,     
    vec3 screen_pos,     
    vec3 view_pos,       
    float radius,
    float dither,
    bool is_lod,
    sampler2D colortex5  
) {
    uint occlusion_mask = 0u;
    vec3 accumulated_gi = vec3(0.0);

    for (int i = 0; i < VBIL_STEPS; ++i) {

        float fi = float(i) + dither;
        float t = fi / float(VBIL_STEPS);
        t *= t;

        float sample_radius = (t * radius) + 0.01; 

        vec3 target_view_pos = view_pos + view_slice_dir * sample_radius;
        vec3 target_screen_pos = view_to_screen_space(target_view_pos, true, is_lod);
        vec2 ray_pos = target_screen_pos.xy;

        if (ray_pos.x < eps || ray_pos.x > 1.0 - eps || ray_pos.y < eps || ray_pos.y > 1.0 - eps) break;

        ivec2 texel = ivec2(ray_pos * view_res * taau_render_scale);
        float sample_depth_nonlinear = texelFetch(combined_depth_tex, texel, 0).x;

        if (sample_depth_nonlinear == 1.0 || sample_depth_nonlinear < hand_depth) continue;

        vec3 sample_view_pos = screen_to_view_space(combined_projection_matrix_inverse, vec3(ray_pos, sample_depth_nonlinear), true);

        vec3 to_sample_front = sample_view_pos - view_pos;
        float dist_sq = dot(to_sample_front, to_sample_front);
        float dist = sqrt(dist_sq);

        float distance_fade = linear_step(0.8 * radius, radius, dist);
        if (distance_fade >= 1.0) continue;

        if (dist < vbil_bias) continue;

        vec3 L = to_sample_front / dist;
        float cos_theta_front = dot(viewer_dir, L);

        cos_theta_front -= 0.05 * dist;
        
        float angle_front = fast_acos(clamp(cos_theta_front, -1.0, 1.0));

        float effective_thickness = vbil_thickness;
        effective_thickness *= (1.0 + dist * 0.5);

        vec3 sample_view_pos_back = sample_view_pos + (viewer_dir * -1.0) * effective_thickness;
        vec3 to_sample_back = sample_view_pos_back - view_pos;
        float cos_theta_back = dot(viewer_dir, normalize(to_sample_back));
        float angle_back = fast_acos(clamp(cos_theta_back, -1.0, 1.0));
        
        if (angle_back < angle_front) {
            float temp = angle_front;
            angle_front = angle_back;
            angle_back = temp;
        }

        uint step_mask = create_bit_range(angle_front, angle_back);

        uint visible_bits = step_mask & (~occlusion_mask);
        if (visible_bits != 0u) {
            vec3 radiance = texture(colortex5, ray_pos).rgb;
            float weight = float(count_bits(visible_bits)) * (1.0 - distance_fade);
            accumulated_gi += radiance * weight;
        }

        occlusion_mask |= step_mask;
        if (occlusion_mask == 0xFFFFFFFFu) break;
    }
    
    return VbilResult(accumulated_gi, occlusion_mask);
}

vec4 compute_vbil(
    vec3 screen_pos,
    vec3 view_pos,
    vec3 view_normal,
    vec2 dither,
    bool is_lod,
    sampler2D colortex5
) {
    vec3 viewer_dir   = normalize(-view_pos);
    
	// Construct local working space
    vec3 viewer_right = normalize(cross(vec3(0.0, 1.0, 0.0), viewer_dir));
    vec3 viewer_up    = cross(viewer_dir, viewer_right);
    mat3 local_to_view = mat3(viewer_right, viewer_up, viewer_dir);

    float ao_radius = VBIL_RADIUS;

    // Increase AO radius for LoD terrain (looks nice)
#ifdef LOD_MOD_ACTIVE
    if (is_lod) ao_radius *= 3.0;
#endif

    vec3 total_radiance = vec3(0.0);
    float total_occlusion_bits = 0.0;

    // Normal Angle logic for Hemisphere Clipping
    for (int i = 0; i < VBIL_SLICES; ++i) {
        float slice_angle = (float(i) + dither.x) * (pi / float(VBIL_SLICES));
        
        // Slice Direction in View Space
        vec3 slice_dir_local = vec3(cos(slice_angle), sin(slice_angle), 0.0);
        vec3 view_slice_dir = local_to_view * slice_dir_local;

        // Project Geometric Normal onto the slice plane
        vec3 slice_normal_plane = cross(view_slice_dir, viewer_dir); // Perpendicular to slice plane
        vec3 projected_normal = view_normal - slice_normal_plane * dot(view_normal, slice_normal_plane);
        float proj_len = length(projected_normal);

        // Bidirectional search (Left and Right sides of the slice)
        VbilResult result_1 = vbil_search(-view_slice_dir, viewer_dir, screen_pos, view_pos, ao_radius, dither.y, is_lod, colortex5);
        VbilResult result_2 = vbil_search( view_slice_dir, viewer_dir, screen_pos, view_pos, ao_radius, dither.y, is_lod, colortex5);

        if (proj_len > eps) {
            vec3 norm_dir = projected_normal / proj_len;
            float cos_gamma = dot(norm_dir, viewer_dir);
            float gamma = fast_acos(clamp(cos_gamma, -1.0, 1.0));

            float sign_n = dot(norm_dir, view_slice_dir);

            float horizon_angle = gamma - half_pi;

            float geom_angle_1 = (sign_n < 0.0) ? (half_pi + gamma) : (half_pi - gamma);
            float geom_angle_2 = (sign_n > 0.0) ? (half_pi + gamma) : (half_pi - gamma);

            // Create masks for geometric self-occlusion
            uint geo_mask_1 = create_bit_range(geom_angle_1, pi);
            uint geo_mask_2 = create_bit_range(geom_angle_2, pi);

            // Combine with raymarched occlusion
            result_1.occlusion_mask |= geo_mask_1;
            result_2.occlusion_mask |= geo_mask_2;
        }

        // Count total occluded bits (0 to 32)
        total_occlusion_bits += float(count_bits(result_1.occlusion_mask));
        total_occlusion_bits += float(count_bits(result_2.occlusion_mask));

        total_radiance += result_1.radiance + result_2.radiance;
    }

    // Normalization
    // Total bits processed = Slices * 2 sides * 32 bits
    float max_bits = float(VBIL_SLICES * 2 * 32);
    float occlusion = total_occlusion_bits / max_bits;
    float ao = 1.0 - occlusion;

    // Multi-bounce approximation for AO (GTAO style)
    const float albedo = 0.2;
    ao /= albedo * ao + (1.0 - albedo);
    ao = pow(ao, 1.8) * 4.0;

    vec3 gi = (total_radiance / max_bits);
    gi *= 1.0;

    // R = AO, GBA = GI Color
    return vec4(clamp01(ao), clamp01(gi));
}

#endif // INCLUDE_LIGHTING_AO_VBIL