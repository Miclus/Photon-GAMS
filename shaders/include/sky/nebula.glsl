#if !defined INCLUDE_SKY_NEBULA
#define INCLUDE_SKY_NEBULA

#include "/include/sky/atmosphere.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"

// ============================================================================
//                               NEBULA SETTINGS
// ============================================================================

// Main nebula settings
#if defined NEBULA_ENABLED
#define NEBULA_ENABLED
#else
#define NEBULA_INTENSITY
#define NEBULA_COLOR_1_R
#define NEBULA_COLOR_1_G
#define NEBULA_COLOR_1_B

#define NEBULA_COLOR_2_R
#define NEBULA_COLOR_2_G
#define NEBULA_COLOR_2_B

#define NEBULA_COLOR_3_R
#define NEBULA_COLOR_3_G
#define NEBULA_COLOR_3_B
#endif

#endif

// ============================================================================
//                               NOISE FUNCTIONS
// ============================================================================

// 3D noise function using hash for randomness
float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smoothstep

    float a = hash1(i);
    float b = hash1(i + vec3(1.0, 0.0, 0.0));
    float c = hash1(i + vec3(0.0, 1.0, 0.0));
    float d = hash1(i + vec3(1.0, 1.0, 0.0));
    float e = hash1(i + vec3(0.0, 0.0, 1.0));
    float g = hash1(i + vec3(1.0, 0.0, 1.0));
    float h = hash1(i + vec3(0.0, 1.0, 1.0));
    float k = hash1(i + vec3(1.0, 1.0, 1.0));

    return mix(
        mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
        mix(mix(e, g, f.x), mix(h, k, f.x), f.y),
        f.z
    );
}

// Fractional Brownian Motion for detailed noise
float fbm(vec3 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise3d(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return value;
}

// Ridged noise for creating more defined structures
float ridged_noise(vec3 p) { return 1.0 - abs(noise3d(p) * 2.0 - 1.0); }

// ============================================================================
//                           SPATIAL MASKING
// ============================================================================

// Simple function to limit nebula to specific sky regions
float get_spatial_mask(vec3 ray_dir) {
    // Create fixed nebula locations based on ray direction
    vec2 sky_pos
        = vec2(atan(ray_dir.x, ray_dir.z), asin(clamp(ray_dir.y, -1.0, 1.0)));

    float mask = 0.0;

    vec2 cluster_center;
    float dist, cluster_mask;

    float fade_distance = 0.1;
    float inner_radius = 0.1;

    // Process each cluster individually to avoid dynamic array indexing
    // Cluster 1
    if (NEBULA_CLUSTER_COUNT >= 1) {
        cluster_center = vec2(-1.0, 0.3);
        dist = length(sky_pos - cluster_center);
        cluster_mask
            = 0.7 - smoothstep(inner_radius, 1.0 + fade_distance, dist);

        // Add secondary gentle falloff for even smoother edges
        float gentle_falloff = 1.0 / (1.0 + dist * dist * 0.5);
        cluster_mask = mix(cluster_mask, gentle_falloff, 0.3);

        // Add subtle noise variation to make edges more organic
        vec3 noise_pos = vec3(sky_pos * 3.0, 0.0);
        float edge_noise = noise3d(noise_pos) * 0.2 + 0.8;
        cluster_mask *= edge_noise;

        mask = max(mask, cluster_mask);
    }

    // Cluster 2
    if (NEBULA_CLUSTER_COUNT >= 2) {
        cluster_center = vec2(0.8, 0.1);
        dist = length(sky_pos - cluster_center);
        cluster_mask
            = 0.7 - smoothstep(inner_radius, 1.0 + fade_distance, dist);

        float gentle_falloff = 1.0 / (1.0 + dist * dist * 0.5);
        cluster_mask = mix(cluster_mask, gentle_falloff, 0.3);

        vec3 noise_pos = vec3(sky_pos * 3.0, 1.0);
        float edge_noise = noise3d(noise_pos) * 0.2 + 0.8;
        cluster_mask *= edge_noise;

        mask = max(mask, cluster_mask);
    }

    // Cluster 3
    if (NEBULA_CLUSTER_COUNT >= 3) {
        cluster_center = vec2(0.3, 0.2);
        dist = length(sky_pos - cluster_center);
        cluster_mask
            = 0.7 - smoothstep(inner_radius, 1.0 + fade_distance, dist);

        float gentle_falloff = 1.0 / (1.0 + dist * dist * 0.5);
        cluster_mask = mix(cluster_mask, gentle_falloff, 0.3);

        vec3 noise_pos = vec3(sky_pos * 3.0, 2.0);
        float edge_noise = noise3d(noise_pos) * 0.2 + 0.8;
        cluster_mask *= edge_noise;

        mask = max(mask, cluster_mask);
    }

    // Cluster 4
    if (NEBULA_CLUSTER_COUNT >= 4) {
        cluster_center = vec2(1.5, 0.4);
        dist = length(sky_pos - cluster_center);
        cluster_mask
            = 0.7 - smoothstep(inner_radius, 1.0 + fade_distance, dist);

        float gentle_falloff = 1.0 / (1.0 + dist * dist * 0.5);
        cluster_mask = mix(cluster_mask, gentle_falloff, 0.3);

        vec3 noise_pos = vec3(sky_pos * 3.0, 3.0);
        float edge_noise = noise3d(noise_pos) * 0.2 + 0.8;
        cluster_mask *= edge_noise;

        mask = max(mask, cluster_mask);
    }

    // Cluster 5
    if (NEBULA_CLUSTER_COUNT >= 5) {
        cluster_center = vec2(0.2, 0.6);
        dist = length(sky_pos - cluster_center);
        cluster_mask
            = 0.7 - smoothstep(inner_radius, 1.0 + fade_distance, dist);

        float gentle_falloff = 1.0 / (1.0 + dist * dist * 0.5);
        cluster_mask = mix(cluster_mask, gentle_falloff, 0.3);

        vec3 noise_pos = vec3(sky_pos * 3.0, 4.0);
        float edge_noise = noise3d(noise_pos) * 0.2 + 0.8;
        cluster_mask *= edge_noise;

        mask = max(mask, cluster_mask);
    }

    // Apply overall spatial limitation with smoother curve
    float spatial_curve = pow(0.5, 0.3); // Gentler curve
    return mask * spatial_curve;
}

// ============================================================================
//                           NEBULA GENERATION
// ============================================================================

// Create base nebula density with multiple noise layers
float get_nebula_density(vec3 ray_dir) {
    // Apply spatial masking first
    float spatial_mask = get_spatial_mask(ray_dir);
    if (spatial_mask <= 0.0) {
        return 0.0;
    }
    // Convert ray direction to 3D coordinates for noise sampling
    vec3 p = ray_dir * 10.0;

    // Large-scale structure
    float large_noise = fbm(p * 0.3, 3);

    // Medium-scale details
    float medium_noise = fbm(p * 1.0, 4);

    // Fine-scale turbulence
    float fine_noise = fbm(p * 1.0 * 3.0, 2);

    // Ridged noise for more defined structures
    float ridged = ridged_noise(p * 1.0 * 0.7);

    // Combine noise layers
    float density = large_noise * 0.6 + medium_noise * 0.3 + fine_noise * 0.1;
    density = mix(density, ridged, 0.2);

    // Apply contrast and coverage
    density = pow(max(density - 0.3, 0.0) / 0.7, 2.5);

    // Apply spatial masking to final density
    density *= spatial_mask;

    return density;
}

// Generate nebula colors based on density and position
vec3 get_nebula_color(vec3 ray_dir, float density) {
    vec3 p = ray_dir * 8.0;

    // Different noise patterns for different emission types
    float color_1_factor = fbm(p * 2.0, 3);
    float color_2_factor = fbm(p * 2.5 + vec3(100.0), 3);
    float color_3_factor = fbm(p * 1.8 + vec3(200.0), 3);

    // Define emission colors
    vec3 color_1 = vec3(NEBULA_COLOR_1_R, NEBULA_COLOR_1_G, NEBULA_COLOR_1_B);
    vec3 color_2 = vec3(NEBULA_COLOR_2_R, NEBULA_COLOR_2_G, NEBULA_COLOR_2_B);
    vec3 color_3 = vec3(NEBULA_COLOR_3_R, NEBULA_COLOR_3_G, NEBULA_COLOR_3_B);

    // Mix colors based on local variations
    vec3 color = vec3(0.0);
    color += color_1 * color_1_factor * 1.2;
    color += color_2 * color_2_factor * 0.8;
    color += color_3 * color_3_factor * 0.7;

    // Add some overall color variation
    float color_variation = fbm(p * 0.5, 2);
    color = mix(color, color * vec3(1.2, 0.9, 1.1), color_variation * 0.3);

    return color * density;
}

// ============================================================================
//                           MAIN NEBULA FUNCTION
// ============================================================================

#ifdef WORLD_OVERWORLD
vec3 draw_nebula(vec3 ray_dir, float galaxy_luminance) {
#ifndef NEBULA_ENABLED
    return vec3(0.0);
#endif

    // Only render nebula during night time
    float night_factor = smoothstep(0.05, -0.15, sun_dir.y);
    if (night_factor <= 0.0) {
        return vec3(0.0);
    }

    // Apply rotation similar to stars and galaxy
    vec3 rotated_ray_dir = ray_dir;

#ifdef NEBULA_ROTATION
#ifdef SHADOW
    // Use the same rotation matrix as stars and galaxy
    mat3 rot = (sunAngle < 0.5)
        ? mat3(shadowModelViewInverse)
        : mat3(
              -shadowModelViewInverse[0].xyz,
              shadowModelViewInverse[1].xyz,
              -shadowModelViewInverse[2].xyz
          );

    rotated_ray_dir = ray_dir * rot;
#endif
#endif

    // Get base density using rotated direction
    float density = get_nebula_density(rotated_ray_dir);
    if (density <= 0.0) {
        return vec3(0.0);
    }

    // Get nebula color using rotated direction
    vec3 nebula_color = get_nebula_color(rotated_ray_dir, density);

    // Apply intensity and night factor
    nebula_color *= NEBULA_INTENSITY * night_factor;

    // Apply atmosphere transmittance to make nebula affected by atmospheric
    // scattering
    nebula_color *= atmosphere_transmittance(ray_dir.y, planet_radius);

    return max(nebula_color, 0.0);
}

#endif // INCLUDE_SKY_NEBULA
