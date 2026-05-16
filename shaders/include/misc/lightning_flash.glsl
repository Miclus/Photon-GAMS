#if !defined INCLUDE_MISC_LIGHTNING_FLASH 
#define INCLUDE_MISC_LIGHTNING_FLASH

#if defined LIGHTNING_FLASH && defined IS_IRIS
		uniform float lightning_flash_iris;
uniform vec4 lightningBoltPosition;
#define LIGHTNING_FLASH_HAS_POSITION (lightningBoltPosition.w > 0.5)
#define LIGHTNING_FLASH_POSITION_SCENE lightningBoltPosition.xyz
#endif

const float lightning_flash_intensity = LIGHTNING_FLASH_INTENSITY;
const float lightning_flash_point_radius = 80.0;
const float lightning_flash_cloud_radius = 7000.0;
const float lightning_flash_fog_radius = 80.0;
const float lightning_flash_fog_intensity = 0.10;

float lightning_flash_point_attenuation(vec3 scene_pos) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    if (!LIGHTNING_FLASH_HAS_POSITION || lightning_flash_iris <= 0.01) {
        return 0.0;
    }

    vec3 to_light = LIGHTNING_FLASH_POSITION_SCENE - scene_pos;
    float dist_sq = dot(to_light, to_light);
    float radius_sq = lightning_flash_point_radius * lightning_flash_point_radius;

    if (dist_sq >= radius_sq) {
        return 0.0;
    }

    float dist = sqrt(dist_sq);
    float edge_fade = 1.0 - dist * rcp(lightning_flash_point_radius);

    return lightning_flash_iris * lightning_flash_intensity * sqr(edge_fade)
        * rcp(1.0 + 0.0002 * dist_sq);
#else
    return 0.0;
#endif
}

float lightning_flash_fog_attenuation(vec3 scene_pos) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    if (!LIGHTNING_FLASH_HAS_POSITION || lightning_flash_iris <= 0.01) {
        return 0.0;
    }

    vec3 to_light = LIGHTNING_FLASH_POSITION_SCENE - scene_pos;
    float dist_sq = dot(to_light, to_light);
    float radius_sq = lightning_flash_fog_radius * lightning_flash_fog_radius;

    if (dist_sq >= radius_sq) {
        return 0.0;
    }

    float dist = sqrt(dist_sq);
    float edge_fade = 1.0 - dist * rcp(lightning_flash_fog_radius);

    return lightning_flash_iris * lightning_flash_intensity * sqr(edge_fade)
        * rcp(1.0 + 0.00004 * dist_sq);
#else
    return 0.0;
#endif
}

vec3 lightning_flash_fog_sample_scattering(
    vec3 scene_pos,
    vec3 scattering_coeff,
    vec3 visible_scattering
) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    float attenuation = lightning_flash_fog_attenuation(scene_pos);

    if (attenuation <= 0.0) {
        return vec3(0.0);
    }

    return vec3(1.0) * attenuation * lightning_flash_fog_intensity
        * scattering_coeff * visible_scattering;
#else
    return vec3(0.0);
#endif
}

float lightning_flash_cloud_attenuation(vec3 scene_pos) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    if (!LIGHTNING_FLASH_HAS_POSITION || lightning_flash_iris <= 0.01) {
        return 0.0;
    }

    vec3 to_light = LIGHTNING_FLASH_POSITION_SCENE - scene_pos;
    float dist_sq = dot(to_light, to_light);
    float radius_sq = lightning_flash_cloud_radius * lightning_flash_cloud_radius;

    if (dist_sq >= radius_sq) {
        return 0.0;
    }

    float dist = sqrt(dist_sq);
    float edge_fade = 1.0 - dist * rcp(lightning_flash_cloud_radius);

    return lightning_flash_iris * lightning_flash_intensity * sqr(edge_fade)
        * rcp(1.0 + 0.000004 * dist_sq);
#else
    return 0.0;
#endif
}

float lightning_flash_cloud_sample_intensity(
    vec3 scene_pos,
    float step_transmittance,
    float transmittance
) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    float attenuation = lightning_flash_cloud_attenuation(scene_pos);

    if (attenuation <= 0.0) {
        return 0.0;
    }

    float sample_opacity = 1.0 - step_transmittance;
    return attenuation * sample_opacity * transmittance;
#else
    return 0.0;
#endif
}

vec3 lightning_flash_point_lighting(
    vec3 scene_pos,
    vec3 normal,
    vec3 flat_normal,
    float ao
) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    float attenuation = lightning_flash_point_attenuation(scene_pos);

    if (attenuation <= 0.0) {
        return vec3(0.0);
    }

    vec3 light_dir = normalize_safe(LIGHTNING_FLASH_POSITION_SCENE - scene_pos);
    float wrapped_lambert = clamp01(dot(normal, light_dir) * 0.75 + 0.25);
    float face_visibility = 0.65 + 0.35 * abs(dot(flat_normal, light_dir));

    return vec3(1.0) * attenuation * wrapped_lambert * face_visibility
        * mix(0.35, 1.0, ao);
#else
    return vec3(0.0);
#endif
}

#endif // INCLUDE_MISC_LIGHTNING_FLASH
