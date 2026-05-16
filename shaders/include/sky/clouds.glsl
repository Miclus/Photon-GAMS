#if !defined INCLUDE_SKY_CLOUDS
#define INCLUDE_SKY_CLOUDS

// Before altocumulus/cumulus: those layers call thunderhead / towering
// occlusion helpers when enabled.
#if defined CLOUDS_THUNDERHEAD
#include "clouds/thunderhead.glsl"
#define PHOTON_THUNDERHEAD_INCLUDED_BEFORE_CUMULUS
#endif
#if defined CLOUDS_TOWERING_CUMULUS
#include "clouds/towering_cumulus.glsl"
#define PHOTON_TOWERING_INCLUDED_BEFORE_CUMULUS
#endif
#include "clouds/altocumulus.glsl"
#include "clouds/cirrus.glsl"
#include "clouds/cumulonimbus.glsl"
#include "clouds/cumulus.glsl"
#include "clouds/cumulus_congestus.glsl"
#include "clouds/noctilucent.glsl"
#ifndef PHOTON_TOWERING_INCLUDED_BEFORE_CUMULUS
#include "clouds/towering_cumulus.glsl"
#endif
#ifndef PHOTON_THUNDERHEAD_INCLUDED_BEFORE_CUMULUS
#include "clouds/thunderhead.glsl"
#endif

#if defined CLOUDS_CUMULUS \
    && (defined CLOUDS_ALTOCUMULUS || defined CLOUDS_TOWERING_CUMULUS \
        || defined CLOUDS_THUNDERHEAD || defined CLOUDS_CIRRUS)
#include "clouds/unified_convective_stack.glsl"
#define PHOTON_UNIFIED_CONVECTIVE_STACK
#endif

bool clouds_early_exit(CloudsResult result, float r, float layer_radius) {
    bool has_congestus = clouds_params.cumulus_congestus_blend > eps;

    return result.transmittance < 1e-3 && r < layer_radius
        && (result.apparent_distance < clouds_cumulus_congestus_distance
            || !has_congestus);
}

#if !defined CLOUDS_CUMULUS && !defined CLOUDS_CUMULUS_CONGESTUS \
    && !defined CLOUDS_CUMULONIMBUS && !defined CLOUDS_ALTOCUMULUS \
    && !defined CLOUDS_CIRRUS && !defined CLOUDS_TOWERING_CUMULUS \
    && !defined CLOUDS_THUNDERHEAD
CloudsResult draw_clouds(
    vec3 air_viewer_pos,
    vec3 ray_dir,
    vec3 clear_sky,
    float distance_to_terrain,
    float dither
) {
    return clouds_not_hit;
}
#else

// cursed sort optimization
const uint defined_clouds =
#ifdef CLOUDS_CUMULUS
    1u |
#endif
#ifdef CLOUDS_CUMULUS_CONGESTUS
    2u |
#endif
#ifdef CLOUDS_CUMULONIMBUS
    4u |
#endif
#ifdef CLOUDS_ALTOCUMULUS
    8u |
#endif
#ifdef CLOUDS_CIRRUS
    16u |
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
    32u |
#endif
#ifdef CLOUDS_THUNDERHEAD
    64u
#else
    0u
#endif
    ;

const uint cloud_layers = max(
    ((defined_clouds) & 1u) + ((defined_clouds >> 1u) & 1u)
        + ((defined_clouds >> 2u) & 1u) + ((defined_clouds >> 3u) & 1u)
        + ((defined_clouds >> 4u) & 1u) + ((defined_clouds >> 5u) & 1u)
        + ((defined_clouds >> 6u) & 1u),
    1u
);

// Insertion sort from
// https://github.com/OpenGLInsights/OpenGLInsightsCode/blob/master/Chapter%2020%20Efficient%20Layered%20Fragment%20Buffer%20Techniques/sorting.glsl
vec2[cloud_layers] sort_clouds(vec2[cloud_layers] cloud_types) {
    if (cloud_layers < 2) {
        return cloud_types;
    }

    else if (cloud_layers == 2) {
        if (cloud_types[0].y > cloud_types[cloud_layers - 1].y) {
            vec2 temp = cloud_types[0];
            cloud_types[0] = cloud_types[cloud_layers - 1];
            cloud_types[cloud_layers - 1] = temp;
        }
        return cloud_types;
    }

    for (int j = 1; j < cloud_layers; ++j) {
        vec2 key = cloud_types[j];
        int i = j - 1;
        while (i >= 0 && cloud_types[i].y > key.y) {
            cloud_types[i + 1] = cloud_types[i];
            --i;
        }
        cloud_types[i + 1] = key;
    }
    return cloud_types;
}

float abs_min(float a, float b) {
    if (abs(b) < abs(a)) {
        return b;
    }
    return a;
}

CloudsResult draw_clouds(
    vec3 air_viewer_pos,
    vec3 ray_dir,
    vec3 clear_sky,
    float distance_to_terrain,
    float dither
) {
    CloudsResult result = clouds_not_hit;
    if (defined_clouds == 0u) {
        return result;
    }
    float r = length(air_viewer_pos);

    int ct_index = 0;
    vec2 cloud_types[cloud_layers];

#ifdef CLOUDS_CUMULUS_CONGESTUS
    cloud_types[ct_index++]
        = vec2(0., abs(max0(clouds_cumulus_congestus_radius) - r));
#endif // CLOUDS_CUMULUS_CONGESTUS

#ifdef CLOUDS_CUMULUS
    cloud_types[ct_index++] = vec2(1., abs(clouds_cumulus_radius - r));
#endif // CLOUDS_CUMULUS

#ifdef CLOUDS_CUMULONIMBUS
    cloud_types[ct_index++]
        = vec2(2., mix(abs(clouds_cumulonimbus_radius - r), 0.0, rainStrength));
#endif // CLOUDS_CUMULONIMBUS

#ifdef CLOUDS_CIRRUS
    // Force cirrus clouds to always be rendered first (behind other clouds) by
    // setting a very large distance
    cloud_types[ct_index++] = vec2(4., 1e6);
#endif // CLOUDS_CIRRUS

    cloud_types = sort_clouds(cloud_types);

    for (uint i = 0; i < cloud_types.length(); ++i) {
        int cloud_type = int(cloud_types[i].x + 0.5);
        switch (cloud_type) {
#ifdef CLOUDS_CUMULUS_CONGESTUS
            case 0:
                if ((clouds_params.cumulus_congestus_blend > eps)
                    && (clouds_params.cumulus_congestus_blend >= 1e-3)) {
                    CloudsResult result_cu_con = draw_cumulus_congestus_clouds(
                        air_viewer_pos,
                        ray_dir,
                        clear_sky,
                        distance_to_terrain,
                        dither
                    );

                    // fade existing clouds into congestus
                    float distance_fade = mix(
                        1.0,
                        result_cu_con.transmittance,
                        linear_step(
                            0.75,
                            1.0,
                            result.apparent_distance
                                * rcp(clouds_cumulus_congestus_distance)
                        )
                    );
                    result.scattering *= distance_fade;
                    result.transmittance
                        += (1.0 - result.transmittance) * (1.0 - distance_fade);
                    result.apparent_distance = mix(
                        result_cu_con.apparent_distance,
                        result.apparent_distance,
                        distance_fade
                    );

                    result = blend_layers(result, result_cu_con, i);
                    if (result.transmittance < 1e-3) {
                        return result;
                    }
                }
                break;
#endif // CLOUDS_CUMULUS_CONGESTUS

#ifdef CLOUDS_CUMULUS
            case 1:
#if defined PHOTON_UNIFIED_CONVECTIVE_STACK
            {
                float photon_u_inner = clouds_cumulus_radius;
#ifdef CLOUDS_ALTOCUMULUS
                photon_u_inner = min(photon_u_inner, clouds_altocumulus_radius);
#endif
#ifdef CLOUDS_TOWERING_CUMULUS
                photon_u_inner
                    = min(photon_u_inner, clouds_towering_cumulus_radius);
#endif
#ifdef CLOUDS_THUNDERHEAD
                photon_u_inner = min(photon_u_inner, clouds_thunderhead_radius);
#endif
                CloudsResult cumulus_result
                    = draw_unified_convective_cloud_stack(
                        air_viewer_pos,
                        ray_dir,
                        clear_sky,
                        distance_to_terrain,
                        dither
                    );
                if (clouds_early_exit(result, r, photon_u_inner)) {
                    result = blend_layers(result, cumulus_result, i);
                    return result;
                }
                result = blend_layers(result, cumulus_result, i);
                if (result.transmittance < 1e-3) {
                    return result;
                }
            }
#else
                if (max(clouds_params.l0_coverage.x,
                        clouds_params.l0_coverage.y)
                    >= 1e-3) {
                    CloudsResult cumulus_result = draw_cumulus_clouds(
                        air_viewer_pos,
                        ray_dir,
                        clear_sky,
                        distance_to_terrain,
                        dither
                    );
                    if (clouds_early_exit(result, r, clouds_cumulus_radius)) {
                        result = blend_layers(result, cumulus_result, i);
                        return result;
                    }

// Add altocumulus within cumulus function if enabled
#ifdef CLOUDS_ALTOCUMULUS
                    if (max(clouds_params.l1_coverage.x,
                            clouds_params.l1_coverage.y)
                        >= 1e-3) {
                        CloudsResult alto_result = draw_altocumulus_clouds(
                            air_viewer_pos,
                            ray_dir,
                            clear_sky,
                            distance_to_terrain,
                            dither
                        );
                        cumulus_result
                            = blend_layers(cumulus_result, alto_result, i);
                        if (clouds_early_exit(
                                result,
                                r,
                                clouds_altocumulus_radius
                            )) {
                            result = blend_layers(result, cumulus_result, i);
                            return result;
                        }
                    }
#endif // CLOUDS_ALTOCUMULUS

// Add towering cumulus within cumulus function if enabled
#ifdef CLOUDS_TOWERING_CUMULUS
                    if (max(clouds_towering_cumulus_coverage.x,
                            clouds_towering_cumulus_coverage.y)
                        >= 1e-3) {
                        CloudsResult towering_result
                            = draw_towering_cumulus_clouds(
                                air_viewer_pos,
                                ray_dir,
                                clear_sky,
                                distance_to_terrain,
                                dither
                            );
                        cumulus_result
                            = blend_layers(cumulus_result, towering_result, i);
                    }
#endif // CLOUDS_TOWERING_CUMULUS

// Add thunderhead within cumulus function if enabled
#ifdef CLOUDS_THUNDERHEAD
                    vec2 thunderhead_cov_active
                        = clouds_thunderhead_coverage_at_sample();
                    if (max(thunderhead_cov_active.x, thunderhead_cov_active.y)
                        >= 1e-3) {
                        CloudsResult thunderhead_result
                            = draw_thunderhead_clouds(
                                air_viewer_pos,
                                ray_dir,
                                clear_sky,
                                distance_to_terrain,
                                dither
                            );
                        cumulus_result = blend_layers(
                            cumulus_result,
                            thunderhead_result,
                            i
                        );
                    }
#endif // CLOUDS_THUNDERHEAD

                    result = blend_layers(result, cumulus_result, i);
                    if (result.transmittance < 1e-3) {
                        return result;
                    }
                }
#endif // PHOTON_UNIFIED_CONVECTIVE_STACK
            break;
#endif // CLOUDS_CUMULUS

#ifdef CLOUDS_CUMULONIMBUS
            case 2:
                if (clouds_params.cumulonimbus_amount >= 1e-3) {
                    CloudsResult result_cn = draw_cumulonimbus_clouds(
                        air_viewer_pos,
                        ray_dir,
                        clear_sky,
                        distance_to_terrain,
                        dither
                    );
                    result = blend_layers(result, result_cn, i);
                    if (result.transmittance < 1e-3) {
                        return result;
                    }
                }
                break;
#endif // CLOUDS_CUMULONIMBUS

#ifdef CLOUDS_CIRRUS
            case 4:
#ifndef PHOTON_UNIFIED_CONVECTIVE_STACK
                if (max(clouds_params.cirrus_amount,
                        clouds_params.cirrocumulus_amount)
                    >= 1e-3) {
                    CloudsResult result_ci = draw_cirrus_clouds(
                        air_viewer_pos,
                        ray_dir,
                        clear_sky,
                        distance_to_terrain,
                        dither
                    );
                    result = blend_layers(result, result_ci, i);
                    if (result.transmittance < 1e-3) {
                        return result;
                    }
                }
#endif // !PHOTON_UNIFIED_CONVECTIVE_STACK
                break;
#endif // CLOUDS_CIRRUS

            default:
                break;
        }

        if (result.transmittance < 1e-3) {
            return result;
        }
    }
#ifdef CLOUDS_NOCTILUCENT
    vec4 result_nlc = draw_noctilucent_clouds(
        air_viewer_pos,
        ray_dir,
        clear_sky,
        distance_to_terrain
    );
    result.scattering.rgb += result_nlc.xyz * result.transmittance;
    result.transmittance *= result_nlc.w;
#endif // CLOUDS_NOCTILUCENT

    return result;
}

#endif // HAS CLOUDS

#endif // INCLUDE_SKY_CLOUDS
