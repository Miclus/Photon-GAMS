#if !defined INCLUDE_LIGHTING_COLORS_WEATHER_COLOR
#define INCLUDE_LIGHTING_COLORS_WEATHER_COLOR

#include "/include/sky/atmosphere.glsl"

uniform float biome_may_sandstorm;

vec3 get_rain_color() {
    vec3 day_rain_color = RAIN_LIGHT_I * sunlight_color * vec3(0.8, 0.8, 0.8);
    vec3 night_rain_color = NIGHT_RAIN_I * sunlight_color
        * vec3(0.1, 0.1, 0.1); // Darker nighttime rain
    return mix(
        night_rain_color,
        day_rain_color,
        smoothstep(-0.1, 0.5, sun_dir.y)
    );
}

vec3 get_snow_color() {
    vec3 day_rain_color = SNOW_LIGHT_I * sunlight_color * vec3(0.8, 0.8, 0.8);
    vec3 night_rain_color = NIGHT_RAIN_I * sunlight_color
        * vec3(0.1, 0.1, 0.1); // Darker nighttime rain
#if defined PROGRAM_WEATHER
    return mix(0.5, 1.60, smoothstep(-0.1, 0.5, sun_dir.y)) * sunlight_color
        * vec3(0.49, 0.65, 1.00);
#else
    return mix(
        night_rain_color,
        day_rain_color,
        smoothstep(-0.1, 0.5, sun_dir.y)
    );
#endif
}

vec3 get_sandstorm_color() {
    vec3 day_rain_color
        = SANDSTORM_LIGHT_I * sunlight_color * vec3(0.8, 0.8, 0.8);
    vec3 night_rain_color = NIGHT_RAIN_I * sunlight_color
        * vec3(0.1, 0.1, 0.1); // Darker nighttime rain
    return mix(
        night_rain_color,
        day_rain_color,
        smoothstep(-0.1, 0.5, sun_dir.y)
    );
}

vec3 get_weather_color() {
    vec3 weather_color
        = mix(get_rain_color(), get_snow_color(), biome_may_snow);
    weather_color
        = mix(weather_color, get_sandstorm_color(), biome_may_sandstorm);

    return weather_color;
}

#endif // INCLUDE_LIGHTING_COLORS_WEATHER_COLOR
