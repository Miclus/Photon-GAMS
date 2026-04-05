float get_cloud_occlusion(sampler2D colortex8) {
    #if defined CLOUDS_CUMULUS || defined CLOUDS_CUMULUS_CONGESTUS || defined CLOUDS_CUMULONIMBUS || defined CLOUDS_TOWERING_CUMULUS || defined CLOUDS_THUNDERHEAD
        
        const float OCCLUSION_SAMPLES = 32.0;
        float total_occlusion = 0.0;

        vec2 zenith = vec2(0.5, 0.5); 
        const float sample_radius = 0.2;

        for (int i = 0; i < int(OCCLUSION_SAMPLES); i++) {
            float r = sqrt(float(i) + 0.5) / sqrt(OCCLUSION_SAMPLES);
            float angle = float(i) * golden_angle;

            vec2 offset = polar_to_cartesian2(r * sample_radius, angle);
            vec2 checkcoord = zenith + offset;

            if (checkcoord.x > 0.0 && checkcoord.x < 1.0 && checkcoord.y > 0.0 && checkcoord.y < 1.0) {
                ivec2 pixel_coord = ivec2(checkcoord * 256.0);
                float cloud_occlusion_sample = texelFetch(colortex8, pixel_coord, 0).r; 

                total_occlusion += clamp01(cloud_occlusion_sample);
            }
        }
        return total_occlusion / OCCLUSION_SAMPLES;
    #else
        return 0.0; 
    #endif
}

vec3 screenspace_vl(sampler2D depthtex0, vec2 lightPos, vec2 uv, vec3 light_color, float dither) {
    vec2 delta_to_sun = lightPos - uv;

    float dist_to_sun = length(delta_to_sun * vec2(aspectRatio, 1.0));

    if (dist_to_sun > SSVL_FADE_RADIUS) {
        return vec3(0.0);
    }

    vec2 sample_step = delta_to_sun / SSVL_SAMPLES * SSVL_DENSITY;

    vec3 accumulated_light = vec3(0.0);
    float decay_factor = 1.0;

    vec2 sample_uv = uv + sample_step * dither;

    for (int i = 0; i < SSVL_SAMPLES; i++) {
        sample_uv += sample_step;

        if (sample_uv.x < -0.12 || sample_uv.x > 1.12 || sample_uv.y < -0.12 || sample_uv.y > 1.12) {
            break;
        }

        vec2 coord_from_light = sample_uv - lightPos;
        vec2 polar_coord = cartesian_to_polar(coord_from_light);
        float angle = polar_coord.y;
        float dist = polar_coord.x;

        vec2 checkcoord = vec2(angle / tau, dist * SSVL_NOISE_SCATTER);
        float noise_coord = texture(noisetex, checkcoord).r;

        noise_coord = mix(1.0, noise_coord, SSVL_NOISE_INTENSITY);

        #ifdef LOD_MOD_ACTIVE
            float depth_lod = texture(lod_depth_tex, sample_uv).r;
        #else
            float depth_lod = 1.0;
        #endif

        #if defined TAA && defined TAAU
            vec2 original_uv = sample_uv * taau_render_scale;
            float depth_sample = texture(depthtex0, original_uv).r;
        #else
            float depth_sample = texture(depthtex0, sample_uv).r;
        #endif
            float min_depth = min(depth_sample, depth_lod);
            float terrain_visibility = step(1.0 - eps, min_depth);

        if (sun_dir.z > 0.0) {
            accumulated_light += light_color * terrain_visibility * decay_factor * noise_coord;
        } else {
            accumulated_light += light_color * terrain_visibility * decay_factor;
        }

        decay_factor *= SSVL_DECAY;
    }

    float radial_mask = 1.0 - clamp01(dist_to_sun / SSVL_FADE_RADIUS);
          radial_mask = pow(radial_mask, SSVL_FADE_FACTOR);

    float cloud_occlusion = get_cloud_occlusion(colortex8);

#ifdef SSVL_MOONPHASE
    if (sun_dir.z < 0.0) { // Moon
        return accumulated_light * SSVL_INTENSITY * radial_mask * cloud_occlusion * lens_flare_moon_phase_brightness;
    } else { // Sun
        return accumulated_light * SSVL_INTENSITY * radial_mask * cloud_occlusion;
    }
#else
    return accumulated_light * SSVL_INTENSITY * radial_mask * cloud_occlusion;
#endif
}