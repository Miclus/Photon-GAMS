#if !defined INCLUDE_SKY_CLOUDS_SAMPLING
#define INCLUDE_SKY_CLOUDS_SAMPLING

#include "/include/misc/lightning_flash.glsl"

// Sample filtered clouds
vec4 read_clouds_and_aurora(vec2 uv, out float apparent_distance) {
#if defined WORLD_OVERWORLD
    // Soften clouds for new pixels
    float pixel_age
        = texelFetch(colortex12, ivec2(uv * view_res * taau_render_scale), 0).y;
    float ld = 2.0 * dampen(max0(1.0 - 0.1 * pixel_age));

    apparent_distance
        = min_of(textureGather(colortex12, uv * taau_render_scale, 0));
    vec4 result = textureLod(colortex11, uv * taau_render_scale, ld);

    float thunderhead_lightning = texture(colortex12, uv * taau_render_scale).w;

    if (thunderhead_lightning > 0.0) {
        vec3 lightning_color = vec3(1.0);
#ifdef CLOUDS_THUNDERHEAD_LIGHTNING_ENABLE
        lightning_color = vec3(
                              CLOUDS_THUNDERHEAD_LIGHTNING_COLOR_R,
                              CLOUDS_THUNDERHEAD_LIGHTNING_COLOR_G,
                              CLOUDS_THUNDERHEAD_LIGHTNING_COLOR_B
                          )
            * CLOUDS_THUNDERHEAD_LIGHTNING_INTENSITY;
#endif
#if defined LIGHTNING_FLASH && defined IS_IRIS
        if (LIGHTNING_FLASH_HAS_POSITION) {
            lightning_color = vec3(1.0);
        }
#endif
        result.xyz += lightning_color * thunderhead_lightning;
    }

    result.xyz *= clamp01(1.0 - blindness - darknessFactor);

    return result;
#else
    return vec4(0.0, 0.0, 0.0, 1.0);
#endif
}

#endif // INCLUDE_SKY_CLOUDS_SAMPLING
