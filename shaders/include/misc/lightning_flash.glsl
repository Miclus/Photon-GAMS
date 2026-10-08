#if !defined INCLUDE_MISC_LIGHTNING_FLASH 
#define INCLUDE_MISC_LIGHTNING_FLASH

#define LIGHTNING_FLASH

#if defined LIGHTNING_FLASH && defined IS_IRIS
        uniform float lightning_flash_iris;
uniform vec4 lightningBoltPosition;
#define LIGHTNING_FLASH_HAS_POSITION (lightningBoltPosition.w > 0.5)
#define LIGHTNING_FLASH_POSITION_SCENE lightningBoltPosition.xyz
#endif

// --- CONFIGURATION ---
const float lightning_flash_intensity = LIGHTNING_FLASH_INTENSITY;
const float lightning_flash_point_radius = LIGHTNING_FLASH_POINT_RAIDUS;
const float lightning_flash_fog_radius = LIGHTNING_FLASH_FOG_RAIDUS;
const float lightning_flash_fog_intensity = LIGHTNING_FLASH_FOG_INTENSITY;

const float lightning_global_cloud_flash = 0.015 * LIGHTNING_GLOBAL_CLOUD_FLASH_INTENSITY;
const float lightning_global_world_flash = 0.0;

const float lightning_flash_cloud_radius = (LIGHTNING_GLOBAL_CLOUD_FLASH_INTENSITY > 0.0) 
    ? (LIGHTNING_FLASH_CLOUD_RAIDUS * 0.0) 
    : (LIGHTNING_FLASH_CLOUD_RAIDUS * 1000.0);

float random_flicker(float t, vec3 pos) {
    // pos is camera-relative — convert to world space so
    // the phase stays stable as the player moves
    vec3 world_pos = pos + cameraPosition;
    float bolt_phase = fract(world_pos.x * 0.371 + world_pos.y * 0.563 + world_pos.z * 0.197) * 6.2832;

    float time = frameTimeCounter + bolt_phase;

    const float SPEED = 5.0;

    float mod1 = sin(time * SPEED * 3.1) * 1.6;
    float mod2 = sin(time * SPEED * 1.5 + 1.05) * 0.7;
    float carrier = sin(time * SPEED * 1.9 + mod1 + mod2);

    return carrier * 0.5 + 0.5;
}

// --- ATTENUATION FUNCTIONS ---

float lightning_flash_point_attenuation(vec3 scene_pos) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    if (!LIGHTNING_FLASH_HAS_POSITION || lightning_flash_iris <= 0.01) {
        return 0.0;
    }

    // 1. The Global Ambient Flash (infinite radius)
    float global_flash = lightning_flash_iris * lightning_flash_intensity * lightning_global_world_flash;

    // 2. The Local Core Bolt (80 block radius)
    float local_flash = 0.0;
    vec3 to_light = LIGHTNING_FLASH_POSITION_SCENE - scene_pos;
    float dist_sq = dot(to_light, to_light);
    float radius_sq = lightning_flash_point_radius * lightning_flash_point_radius;

    if (dist_sq < radius_sq) {
        float dist = sqrt(dist_sq);
        float edge_fade = 1.0 - dist * rcp(lightning_flash_point_radius);
        local_flash = lightning_flash_iris * lightning_flash_intensity * sqr(edge_fade) * rcp(1.0 + 0.0002 * dist_sq);
    }

    // Combine them: Use whichever is brighter at this specific location
    return max(global_flash, local_flash);
#else
    return 0.0;
#endif
}

float lightning_flash_fog_attenuation(vec3 scene_pos) {
#if defined LIGHTNING_FLASH && defined IS_IRIS
    if (!LIGHTNING_FLASH_HAS_POSITION || lightning_flash_iris <= 0.01) {
        return 0.0;
    }

    // Global Ambient Flash
    float global_flash = lightning_flash_iris * lightning_flash_intensity * lightning_global_world_flash;

    // Local Core Bolt
    float local_flash = 0.0;
    vec3 to_light = LIGHTNING_FLASH_POSITION_SCENE - scene_pos;
    float dist_sq = dot(to_light, to_light);
    float radius_sq = lightning_flash_fog_radius * lightning_flash_fog_radius;

    if (dist_sq < radius_sq) {
        float dist = sqrt(dist_sq);
        float edge_fade = 1.0 - dist * rcp(lightning_flash_fog_radius);
        local_flash = lightning_flash_iris * lightning_flash_intensity * sqr(edge_fade) * rcp(1.0 + 0.00004 * dist_sq);
    }

    return max(global_flash, local_flash);
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

    float t = floor(frameTimeCounter) * 100;
    float flicker = mix(0.2, 1.0, random_flicker(t, LIGHTNING_FLASH_POSITION_SCENE));

    float global_flash = lightning_flash_iris * lightning_flash_intensity * lightning_global_cloud_flash * flicker;
    // 2. The Local Core Bolt
    float local_flash = 0.0;
    // ... (rest of your existing function code)
    vec3 to_light = LIGHTNING_FLASH_POSITION_SCENE - scene_pos;
    float dist_sq = dot(to_light, to_light);
    float radius_sq = lightning_flash_cloud_radius * lightning_flash_cloud_radius;

    if (dist_sq < radius_sq) {
        float dist = sqrt(dist_sq);
        float edge_fade = 1.0 - dist * rcp(lightning_flash_cloud_radius);
        local_flash = lightning_flash_iris * lightning_flash_intensity * sqr(edge_fade) * rcp(1.0 + 0.000004 * dist_sq);
    }

    return max(global_flash, local_flash);
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
    if (lightning_flash_iris <= 0.01) return vec3(0.0);

    // Global: flat ambient from above, no position needed
    float global_flash = lightning_flash_iris * lightning_flash_intensity * lightning_global_world_flash
        * clamp01(normal.y * 0.5 + 0.5)  // soft top-down bias
        * mix(0.35, 1.0, ao);

    // Local: original bolt proximity light
    float local_flash = 0.0;
    if (LIGHTNING_FLASH_HAS_POSITION) {
        vec3 to_light = LIGHTNING_FLASH_POSITION_SCENE - scene_pos;
        float dist_sq = dot(to_light, to_light);
        float radius_sq = lightning_flash_point_radius * lightning_flash_point_radius;

        if (dist_sq < radius_sq) {
            float dist = sqrt(dist_sq);
            float edge_fade = 1.0 - dist * rcp(lightning_flash_point_radius);
            vec3 light_dir = to_light * rcp(dist);
            float wrapped_lambert = clamp01(dot(normal, light_dir) * 0.75 + 0.25);
            float face_visibility = 0.65 + 0.35 * abs(dot(flat_normal, light_dir));
            local_flash = lightning_flash_iris * lightning_flash_intensity
                * sqr(edge_fade) * rcp(1.0 + 0.0002 * dist_sq)
                * wrapped_lambert * face_visibility * mix(0.35, 1.0, ao);
        }
    }

    return vec3(max(global_flash, local_flash));
#else
    return vec3(0.0);
#endif
}

#endif // INCLUDE_MISC_LIGHTNING_FLASH