//https://www.shadertoy.com/view/XddcRr
// Spreading Frost by dos
// Inspired by https://www.shadertoy.com/view/MsySzy by shadmar

float rand(vec2 uv) {
    float a = dot(uv, vec2(92., 80.));
    float b = dot(uv, vec2(41., 62.));
    float x = sin(a) + cos(b) * 51.;
    return fract(x);
}

vec3 spreading_frost() {
    #ifdef SPREADING_FROST_SNOWING_ONLY
        if (rainStrength <= 0.001) {
            return vec3(0.0);
        }
    #endif

    float progress = biome_may_snow;

    if (progress <= 0.001) {
        return vec3(0.0);
    }

    vec3 frost = texture(noisetex, uv * 2.0).rgb;
    float icespread = texture(noisetex, uv * 1.5).r;

    vec2 rnd = vec2(rand(uv + frost.r * 0.05), rand(uv + frost.b * 0.05));

    float size = mix(progress, sqrt(progress), 0.5);   
          size = size * SPREADING_FROST_VIGNETTE_SIZE + eps; 
    
    vec2 lens = vec2(size, pow(size, 4.0) / 2.0);
    float dist = distance(uv, vec2(0.5, 0.5)); 

    float vignette = sqr(smoothstep(lens.y, lens.x, dist));
   
    rnd *= frost.rg * vignette * SPREADING_FROST_FROSTYNESS;
    rnd *= 1.0 - floor(vignette);

    vec3 frozen = texture(colortex0, uv + rnd).rgb;
    #ifdef SPREADING_FROST_CR
        frozen *= vec3(SPREADING_FROST_CR_R, 
                       SPREADING_FROST_CR_G, 
                       SPREADING_FROST_CR_B);
    #endif

    frozen = display_eotf(frozen);

    float mix_factor = smoothstep(icespread, 1.0, sqr(vignette));

    float snow_factor = 1.0;
    #ifdef SPREADING_FROST_SNOWING_ONLY
        snow_factor = rainStrength;
    #endif

    return (frozen - fragment_color) * (1.0 - mix_factor) * sqr(biome_may_snow) * SPREADING_FROST_INTENSITY * snow_factor;
}