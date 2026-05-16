#if !defined INCLUDE_SKY_AURORA_COLORS
#define INCLUDE_SKY_AURORA_COLORS

#include "/include/utility/random.glsl"

// [0] - bottom color
// [1] - top color
mat2x3 get_aurora_colors() {
    const mat2x3[] aurora_colors = mat2x3[](
        mat2x3( // 0
            vec3(AURORA_COLOR_0_BTM_R, AURORA_COLOR_0_BTM_G, AURORA_COLOR_0_BTM_B) * AURORA_COLOR_0_BTM_I,
            vec3(AURORA_COLOR_0_TOP_R, AURORA_COLOR_0_TOP_G, AURORA_COLOR_0_TOP_B) * AURORA_COLOR_0_TOP_I
        )
        , mat2x3( // 1
            vec3(AURORA_COLOR_1_BTM_R, AURORA_COLOR_1_BTM_G, AURORA_COLOR_1_BTM_B) * AURORA_COLOR_1_BTM_I,
            vec3(AURORA_COLOR_1_TOP_R, AURORA_COLOR_1_TOP_G, AURORA_COLOR_1_TOP_B) * AURORA_COLOR_1_TOP_I
        )
        , mat2x3( // 2
            vec3(AURORA_COLOR_2_BTM_R, AURORA_COLOR_2_BTM_G, AURORA_COLOR_2_BTM_B) * AURORA_COLOR_2_BTM_I,
            vec3(AURORA_COLOR_2_TOP_R, AURORA_COLOR_2_TOP_G, AURORA_COLOR_2_TOP_B) * AURORA_COLOR_2_TOP_I
        )
        , mat2x3( // 3
            vec3(AURORA_COLOR_3_BTM_R, AURORA_COLOR_3_BTM_G, AURORA_COLOR_3_BTM_B) * AURORA_COLOR_3_BTM_I,
            vec3(AURORA_COLOR_3_TOP_R, AURORA_COLOR_3_TOP_G, AURORA_COLOR_3_TOP_B) * AURORA_COLOR_3_TOP_I
        )
        , mat2x3( // 4
            vec3(AURORA_COLOR_4_BTM_R, AURORA_COLOR_4_BTM_G, AURORA_COLOR_4_BTM_B) * AURORA_COLOR_4_BTM_I,
            vec3(AURORA_COLOR_4_TOP_R, AURORA_COLOR_4_TOP_G, AURORA_COLOR_4_TOP_B) * AURORA_COLOR_4_TOP_I
        )
        , mat2x3( // 5
            vec3(AURORA_COLOR_5_BTM_R, AURORA_COLOR_5_BTM_G, AURORA_COLOR_5_BTM_B) * AURORA_COLOR_5_BTM_I,
            vec3(AURORA_COLOR_5_TOP_R, AURORA_COLOR_5_TOP_G, AURORA_COLOR_5_TOP_B) * AURORA_COLOR_5_TOP_I
        )
        , mat2x3( // 6
            vec3(AURORA_COLOR_6_BTM_R, AURORA_COLOR_6_BTM_G, AURORA_COLOR_6_BTM_B) * AURORA_COLOR_6_BTM_I,
            vec3(AURORA_COLOR_6_TOP_R, AURORA_COLOR_6_TOP_G, AURORA_COLOR_6_TOP_B) * AURORA_COLOR_6_TOP_I
        )
        , mat2x3( // 7
            vec3(AURORA_COLOR_7_BTM_R, AURORA_COLOR_7_BTM_G, AURORA_COLOR_7_BTM_B) * AURORA_COLOR_7_BTM_I,
            vec3(AURORA_COLOR_7_TOP_R, AURORA_COLOR_7_TOP_G, AURORA_COLOR_7_TOP_B) * AURORA_COLOR_7_TOP_I
        )
        , mat2x3( // 8
            vec3(AURORA_COLOR_8_BTM_R, AURORA_COLOR_8_BTM_G, AURORA_COLOR_8_BTM_B) * AURORA_COLOR_8_BTM_I,
            vec3(AURORA_COLOR_8_TOP_R, AURORA_COLOR_8_TOP_G, AURORA_COLOR_8_TOP_B) * AURORA_COLOR_8_TOP_I
        )
        , mat2x3( // 9
            vec3(AURORA_COLOR_9_BTM_R, AURORA_COLOR_9_BTM_G, AURORA_COLOR_9_BTM_B) * AURORA_COLOR_9_BTM_I,
            vec3(AURORA_COLOR_9_TOP_R, AURORA_COLOR_9_TOP_G, AURORA_COLOR_9_TOP_B) * AURORA_COLOR_9_TOP_I
        )
        , mat2x3( // 10
            vec3(AURORA_COLOR_10_BTM_R, AURORA_COLOR_10_BTM_G, AURORA_COLOR_10_BTM_B) * AURORA_COLOR_10_BTM_I,
            vec3(AURORA_COLOR_10_TOP_R, AURORA_COLOR_10_TOP_G, AURORA_COLOR_10_TOP_B) * AURORA_COLOR_10_TOP_I
        )
        , mat2x3( // 11
            vec3(AURORA_COLOR_11_BTM_R, AURORA_COLOR_11_BTM_G, AURORA_COLOR_11_BTM_B) * AURORA_COLOR_11_BTM_I,
            vec3(AURORA_COLOR_11_TOP_R, AURORA_COLOR_11_TOP_G, AURORA_COLOR_11_TOP_B) * AURORA_COLOR_11_TOP_I
        )
    );

#if AURORA_COLOR == -1
    const uint[] weights = uint[](
        AURORA_COLOR_0_WEIGHT,
        AURORA_COLOR_1_WEIGHT,
        AURORA_COLOR_2_WEIGHT,
        AURORA_COLOR_3_WEIGHT,
        AURORA_COLOR_4_WEIGHT,
        AURORA_COLOR_5_WEIGHT,
        AURORA_COLOR_6_WEIGHT,
        AURORA_COLOR_7_WEIGHT,
        AURORA_COLOR_8_WEIGHT,
        AURORA_COLOR_9_WEIGHT,
        AURORA_COLOR_10_WEIGHT,
        AURORA_COLOR_11_WEIGHT
    );
    const uint total_weight = AURORA_COLOR_0_WEIGHT + AURORA_COLOR_1_WEIGHT
        + AURORA_COLOR_2_WEIGHT + AURORA_COLOR_3_WEIGHT + AURORA_COLOR_4_WEIGHT
        + AURORA_COLOR_5_WEIGHT + AURORA_COLOR_6_WEIGHT + AURORA_COLOR_7_WEIGHT
        + AURORA_COLOR_8_WEIGHT + AURORA_COLOR_9_WEIGHT + AURORA_COLOR_10_WEIGHT
        + AURORA_COLOR_11_WEIGHT;
    mat2x3[total_weight] aurora_colors_weighted;
    for (uint i = 0u, index = 0u; i < weights.length(); i++) {
        for (uint j = 0u; j < weights[i]; j++, index++) {
            aurora_colors_weighted[index] = aurora_colors[i];
        }
    }

    uint day_index = uint(worldDay);
    day_index = lowbias32(day_index) % aurora_colors_weighted.length();
    return aurora_colors_weighted[day_index];
#else
    return aurora_colors[uint(AURORA_COLOR)];
#endif
}

// 0.0 - no aurora
// 1.0 - full aurora
float get_aurora_amount() {
    float night = smoothstep(0.0, 0.2, -sun_dir.y);

#if AURORA_NORMAL == AURORA_NEVER
    float aurora_normal = 0.0;
#elif AURORA_NORMAL == AURORA_RARELY
    float aurora_normal = float(lowbias32(uint(worldDay)) % 5 == 1);
#elif AURORA_NORMAL == AURORA_ALWAYS
    float aurora_normal = 1.0;
#endif

#if AURORA_SNOW == AURORA_NEVER
    float aurora_snow = 0.0;
#elif AURORA_SNOW == AURORA_RARELY
    float aurora_snow = float(lowbias32(uint(worldDay)) % 5 == 1);
#elif AURORA_SNOW == AURORA_ALWAYS
    float aurora_snow = 1.0;
#endif

    return night * mix(aurora_normal, aurora_snow, biome_may_snow);
}

#endif // INCLUDE_SKY_AURORA_COLORS
