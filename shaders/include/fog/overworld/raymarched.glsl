#if !defined INCLUDE_FOG_AIR_FOG_VL
#define INCLUDE_FOG_AIR_FOG_VL

#include "/include/fog/overworld/constants.glsl"
#include "/include/lighting/cloud_shadows.glsl"
#include "/include/lighting/shadows/distortion.glsl"
#include "/include/misc/lod_mod_support.glsl"
#include "/include/sky/atmosphere.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/phase_functions.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"

#ifdef AIR_FOG_CLOUDY_NOISE
// Improved 3D noise with better structure
float noise3d(vec3 pos) {
    // Sample noise texture on three planes for 3D approximation
    float n1 = texture(noisetex, pos.xy * 0.08).w;
    float n2 = texture(noisetex, pos.xz * 0.08).w;
    float n3 = texture(noisetex, pos.yz * 0.08).w;
    return (n1 + n2 + n3) * (1.0 / 3.0);
}

// Curl noise for swirling motion — optimized with cached derivatives
vec3 curlNoise(vec3 pos) {
    const float e = 0.1;
    float dx0 = noise3d(pos + vec3(e, 0.0, 0.0));
    float dx1 = noise3d(pos - vec3(e, 0.0, 0.0));
    float dy0 = noise3d(pos + vec3(0.0, e, 0.0));
    float dy1 = noise3d(pos - vec3(0.0, e, 0.0));
    float dz0 = noise3d(pos + vec3(0.0, 0.0, e));
    float dz1 = noise3d(pos - vec3(0.0, 0.0, e));
    
    float dfdx = (dx0 - dx1) / (2.0 * e);
    float dfdy = (dy0 - dy1) / (2.0 * e);
    float dfdz = (dz0 - dz1) / (2.0 * e);
    
    // Curl of vector field (f, f, f): (df/dy - df/dz, df/dz - df/dx, df/dx - df/dy)
    return vec3(dfdy - dfdz, dfdz - dfdx, dfdx - dfdy);
}
#endif

vec2 air_fog_density(vec3 world_pos) {
    const vec2 mul = -rcp(air_fog_falloff_half_life);
    const vec2 add = -mul * air_fog_falloff_start;

    vec2 density = exp2(min(world_pos.y * mul + add, 0.0));

    // fade away below sea level
    density *= linear_step(air_fog_volume_bottom, SEA_LEVEL, world_pos.y);

#ifdef AIR_FOG_CLOUDY_NOISE
    // Height-based density shaping - wispy at bottom, solid at top
    float height_fraction = clamp01((world_pos.y - air_fog_volume_bottom) / (air_fog_volume_top - air_fog_volume_bottom));
    
    // Wind animation with curl noise for swirling motion
    const vec3 wind = 0.0003 * vec3(1.0, 0.3, 0.5);
    vec3 noise_pos = world_pos * 0.006 + wind * frameTimeCounter;
    
    // Apply curl noise for natural swirling
    vec3 curl_offset = 0.15 * curlNoise(noise_pos * 0.5);
    noise_pos += curl_offset;
    
    // Multi-octave FBM for cloud-like structure — 2 octaves (down from 4)
    // for performance. Temporal accumulation fills in the missing detail.
    float fbm = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    for (int j = 0; j < 2; j++) {
        fbm += amp * noise3d(noise_pos * freq);
        freq *= 2.8;
        amp *= 0.45;
        noise_pos += wind * frameTimeCounter * 0.3;
    }
    
    // Shape density - create cloud-like clumps in the mid-range
    float cloud_shape = smoothstep(0.0, 0.3, height_fraction) * (1.0 - smoothstep(0.6, 1.0, height_fraction));
    
    // Noise-based density modulation
    float noise_factor = max(fbm * 1.5 - 0.3, 0.0);
    noise_factor = min(noise_factor, 1.0);
    
    // Structure: baseline 1.0, up to ~1.4x in dense noisy areas
    float structure = 1.0 + 0.4 * noise_factor * (0.5 + 0.5 * cloud_shape);

    // Extra density at mid-altitude goes up to ~1.25x max, baseline 1.0
    float altitude_density = 1.0 + 0.25 * cloud_shape;

    density.y *= structure * altitude_density;
#endif

    return density * (0.5 * OVERWORLD_FOG_INTENSITY);
}

// Fast density without noise — used for sunlight transmittance raymarch.
// Only computes height-based exponential falloff, skipping the expensive
// FBM + curl noise. This reduces the per-step cost of the 3-sample sunlight
// raymarch from ~90 noise texture fetches to zero.
vec2 air_fog_density_fast(vec3 world_pos) {
    const vec2 mul = -rcp(air_fog_falloff_half_life);
    const vec2 add = -mul * air_fog_falloff_start;

    vec2 density = exp2(min(world_pos.y * mul + add, 0.0));
    density *= linear_step(air_fog_volume_bottom, SEA_LEVEL, world_pos.y);

    return density * (0.5 * OVERWORLD_FOG_INTENSITY);
}

mat2x3 raymarch_air_fog(
    vec3 world_start_pos,
    vec3 world_end_pos,
    bool sky,
    float skylight,
    float dither
) {
    vec3 world_dir = world_end_pos - world_start_pos;

    float length_sq = length_squared(world_dir);
    float norm = inversesqrt(length_sq);
    float ray_length = length_sq * norm;
    world_dir *= norm;

    vec3 shadow_start_pos
        = transform(shadowModelView, world_start_pos - cameraPosition);
    shadow_start_pos = project_ortho(shadowProjection, shadow_start_pos);

    vec3 shadow_dir = mat3(shadowModelView) * world_dir;
    shadow_dir = diagonal(shadowProjection).xyz * shadow_dir;

    float distance_to_lower_plane
        = (air_fog_volume_bottom - eyeAltitude) / world_dir.y;
    float distance_to_upper_plane
        = (air_fog_volume_top - eyeAltitude) / world_dir.y;
    float distance_to_volume_start, distance_to_volume_end;

    if (eyeAltitude < air_fog_volume_bottom) {
        // Below volume
        distance_to_volume_start = distance_to_lower_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? -1.0 : distance_to_upper_plane;
    } else if (eyeAltitude < air_fog_volume_top) {
        // Inside volume
        distance_to_volume_start = 0.0;
        distance_to_volume_end = world_dir.y < 0.0
            ? distance_to_lower_plane
            : distance_to_upper_plane;
    } else {
        // Above volume
        distance_to_volume_start = distance_to_upper_plane;
        distance_to_volume_end
            = world_dir.y < 0.0 ? distance_to_upper_plane : -1.0;
    }

#ifdef LOD_MOD_ACTIVE
    float fog_end = float(lod_render_distance);
#else
    float fog_end = far;
#endif

    if (distance_to_volume_end < 0.0) {
        return mat2x3(vec3(0.0), vec3(1.0));
    }

    ray_length = sky ? distance_to_volume_end : ray_length;
    ray_length = clamp(ray_length - distance_to_volume_start, 0.0, fog_end);

    uint step_count = uint(
        float(air_fog_min_step_count) + air_fog_step_count_growth * ray_length
    );
    step_count = min(step_count, air_fog_max_step_count);

    float rSteps = rcp(float(step_count));
    float base_step_length = ray_length * rSteps * rSteps;

    float LoV = dot(world_dir, light_dir);

    vec3 transmittance = vec3(1.0);

    mat2x3 light_sun = mat2x3(0.0);
    mat2x3 light_sky = mat2x3(0.0);

    for (int i = 0; i < step_count; ++i) {
        float fi = float(i) + dither;
        float fi_prev = max(fi - 1.0, 0.0);

        float actual_step_length = base_step_length * (sqr(fi) - sqr(fi_prev));
        float current_distance = distance_to_volume_start + base_step_length * sqr(fi);

        vec3 world_pos = world_start_pos + world_dir * current_distance;
        vec3 shadow_pos = shadow_start_pos + shadow_dir * current_distance;

        vec2 density = air_fog_density(world_pos) * actual_step_length;

        if (dot(density, vec2(1.0)) < 1e-6) continue;

        vec3 shadow_screen_pos = distort_shadow_space(shadow_pos) * 0.5 + 0.5;

#if defined SHADOW && !defined PROGRAM_DEFERRED0
        ivec2 shadow_texel = ivec2(
            shadow_screen_pos.xy * shadowMapResolution * MC_SHADOW_QUALITY
        );

#ifdef AIR_FOG_COLORED_LIGHT_SHAFTS
        float depth0 = texelFetch(shadowtex0, shadow_texel, 0).x;
        float depth1 = texelFetch(shadowtex1, shadow_texel, 0).x;
        vec3 color
            = clamp01(texelFetch(shadowcolor0, shadow_texel, 0).rgb * 4.0);
        float color_weight
            = step(depth0, shadow_screen_pos.z) * step(eps, max_of(color));

        color = color * color_weight + (1.0 - color_weight);

        vec3 shadow = step(shadow_screen_pos.z, depth1) * color;
        shadow = (clamp01(shadow_screen_pos) == shadow_screen_pos)
            ? shadow
            : vec3(1.0);
#else
        float depth1 = texelFetch(shadowtex1, shadow_texel, 0).x;
        float shadow = step(
            float(clamp01(shadow_screen_pos) == shadow_screen_pos)
                * shadow_screen_pos.z,
            depth1
        );
#endif
#else
#define shadow 1.0
#endif

        vec3 step_optical_depth
            = fog_params.rayleigh_scattering_coeff * density.x
            + fog_params.mie_extinction_coeff * density.y;
        vec3 step_transmittance = fast_exp_neg(step_optical_depth);
        vec3 step_transmitted_fraction
            = (1.0 - step_transmittance) / max(step_optical_depth, eps);

        // Sunlight transmittance — use fast density (no noise) for the 3-sample
        // raymarch toward the sun. This eliminates ~90 noise texture fetches
        // per fog step while having negligible visual impact since the sunlight
        // transmittance is dominated by the height-based density falloff.
        vec2 optical_depth_sun = vec2(0.0);
        float sun_step = 4.0;
        vec3 light_pos = world_pos;
        for (int j = 0; j < 3; j++) {
            sun_step *= 1.5;
            light_pos += light_dir * sun_step;
            vec2 sun_density = air_fog_density_fast(light_pos);
            optical_depth_sun += sun_density * sun_step;
        }

        vec3 step_optical_depth_sun
            = fog_params.rayleigh_scattering_coeff * optical_depth_sun.x
            + fog_params.mie_extinction_coeff * optical_depth_sun.y;
        vec3 sun_transmittance = fast_exp_neg(step_optical_depth_sun);

        // Phase 1: Powder Effect - stronger scattering toward light direction
        float LoV01 = LoV * 0.5 + 0.5;
        float step_density = dot(step_optical_depth, vec3(1.0 / 3.0));
        float powder = (1.0 - fast_exp_neg(0.5 * step_density)) * (1.0 - LoV01) + LoV01;

        vec3 visible_scattering = step_transmitted_fraction * transmittance * powder;

        light_sun[0] += visible_scattering * density.x * shadow * sun_transmittance;
        light_sun[1] += visible_scattering * density.y * shadow * sun_transmittance;
        light_sky[0] += visible_scattering * density.x;
        light_sky[1] += visible_scattering * density.y;

        transmittance *= step_transmittance;

        if (dot(transmittance, vec3(1.0)) < 1e-3) break;
    }

    light_sun[0] *= fog_params.rayleigh_scattering_coeff;
    light_sun[1] *= fog_params.mie_scattering_coeff;
    light_sky[0] *= fog_params.rayleigh_scattering_coeff;
    light_sky[1] *= fog_params.mie_scattering_coeff;

    if (!sky) {
        // Skylight falloff
        light_sky[0] *= max(skylight, eye_skylight);
        light_sky[1] *= max(skylight, eye_skylight);
    }

    float mie_phase = 0.7 * henyey_greenstein_phase(LoV, 0.5)
        + 0.3 * henyey_greenstein_phase(LoV, -0.2);

    /*
    // Single scattering
    vec3 scattering  = light_color * (light_sun * vec2(isotropic_phase,
    mie_phase)); scattering += ambient_color * (light_sky *
    vec2(isotropic_phase));
    /*/
    // Multiple scattering
    vec3 scattering = vec3(0.0);
    float scatter_amount = 1.0;
    float anisotropy = 1.0;

    // Boost ambient brightness so fog doesn't look dim
    vec3 fog_ambient = max(ambient_color, vec3(0.06));

    scattering += 2.8 * light_sky * vec2(isotropic_phase) * fog_ambient;

    for (int i = 0; i < 4; ++i) {
        float mie_phase = 0.7 * henyey_greenstein_phase(LoV, 0.5 * anisotropy)
            + 0.3 * henyey_greenstein_phase(LoV, -0.2 * anisotropy);

        scattering += scatter_amount
            * (light_sun * vec2(isotropic_phase, mie_phase)) * light_color;

        scatter_amount *= 0.5;
        anisotropy *= 0.7;
    }
    //*/

    scattering *= clamp01(1.0 - blindness - darknessFactor);

    // Artifically brighten fog in the early morning and evening (looks nice)
    float evening_glow
        = 0.75 * linear_step(0.05, 1.0, exp(-300.0 * sqr(sun_dir.y + 0.02)));
    scattering += scattering * evening_glow;

    return mat2x3(scattering, transmittance);
}

#endif // INCLUDE_FOG_AIR_FOG_VL
