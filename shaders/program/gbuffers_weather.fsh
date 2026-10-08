/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/gbuffers_weather:
  Handle rain and snow particles

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 frag_color;

/* RENDERTARGETS: 13 */

in vec2 uv;
in vec2 lmcoord;
in vec3 scene_pos; // Static player-space coordinate array

flat in vec4 tint;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform int moonPhase;
uniform int frameCounter;

uniform vec3 sun_dir;

uniform vec2 taa_offset;
uniform vec2 view_pixel_size;

uniform float biome_may_snow;

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform sampler3D light_sampler_a;
uniform sampler3D light_sampler_b;

#include "/include/utility/color.glsl"

#ifndef COLORED_LIGHTS
const vec3 blocklight_color = from_srgb(vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B)) * BLOCKLIGHT_I;
const float blocklight_scale = 6.0;
#endif

#include "/include/lighting/handheld_lighting.glsl"
#include "/include/lighting/lpv/blocklight.glsl"
#include "/include/lighting/colors/weather_color.glsl"
#include "/include/utility/encoding.glsl"


void main() {

#if defined TAA && defined TAAU
    vec2 coord = gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale);
    if (clamp01(coord) != coord) {
        discard;
    }
#endif

    vec4 base_color = texture(gtexture, uv);
    if (base_color.a < 0.1) {
        discard;
    }

    bool is_rain = (abs(base_color.r - base_color.b) > eps);

    vec3 rain_color = get_rain_color();
    float blocklight_strength = 0.1;
    vec3 handlight = get_handheld_lighting(scene_pos, 1.0);

    #ifdef COLORED_LIGHTS
        vec3 colored_light = get_lpv_fog(scene_pos);
        rain_color += colored_light * blocklight_strength;
        rain_color += handlight * (blocklight_strength * 0.3);
    #else
        handlight *= 0.35;
        rain_color += blocklight_color * blocklight_scale * lmcoord.x * blocklight_strength * 0.45;
        rain_color += handlight * (blocklight_strength);
    #endif   

    frag_color = is_rain
        ? vec4(rain_color, RAIN_OPACITY * base_color.a) * tint
        : vec4(get_snow_color(), SNOW_OPACITY * base_color.a) * tint;

    frag_color.rgb *= frag_color.a;
}
