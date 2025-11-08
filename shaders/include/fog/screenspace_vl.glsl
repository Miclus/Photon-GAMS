vec3 CalculateScreenSpaceVL(sampler2D depthTexture, sampler2D cloudTexture, vec2 lightPos, vec2 uv, vec3 light_color, float dither) {
    vec2 deltaToLight = lightPos - uv;

    float distToSun = length(deltaToLight * vec2(aspectRatio, 1.0));

    if (distToSun > SSVL_FADE_RADIUS) {
        return vec3(0.0);
    }

    vec2 sampleStep = deltaToLight / SSVL_SAMPLES * SSVL_DENSITY;

    vec3 accumulatedLight = vec3(0.0);
    float decayFactor = 1.0;

    vec2 newUV = uv + sampleStep * dither;

    for (int i = 0; i < SSVL_SAMPLES; i++) {
        newUV += sampleStep;

        if (newUV.x < -0.12 || newUV.x > 1.12 || newUV.y < -0.12 || newUV.y > 1.12) {
            break;
        }

        vec2 coordFromLight = newUV - lightPos;
        float angle = atan(coordFromLight.y, coordFromLight.x);
        float dist = length(coordFromLight);

        vec2 noiseCoord = vec2(angle / tau, dist * SSVL_NOISE_SCALE);
        float checkcoord = texture(noisetex, noiseCoord).r;

        checkcoord = mix(1.0, checkcoord, SSVL_NOISE_INTENSITY);
        
        float depthSample = texture(depthTexture, newUV).r;
        float terrain_visibility = step(0.9999, depthSample);

        if (sun_dir.z > 0.0) {
            accumulatedLight += light_color * terrain_visibility * decayFactor * checkcoord;
        } else {
            accumulatedLight += light_color * terrain_visibility * decayFactor;
        }

        decayFactor *= SSVL_DECAY;
    }

    float radialMask = 1.0 - clamp01(distToSun / SSVL_FADE_RADIUS);
          radialMask = pow(radialMask, SSVL_FADE_FACTOR);

#ifdef SSVL_MOONPHASE
    if (sun_dir.z < 0.0) {
        return accumulatedLight * SSVL_INTENSITY * radialMask * lens_flare_moon_phase_brightness;
    } else {
        return accumulatedLight * SSVL_INTENSITY * radialMask;
    }
#else
    return accumulatedLight * SSVL_INTENSITY * radialMask;
#endif
}