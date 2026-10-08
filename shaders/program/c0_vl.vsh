/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c0_vl:
  Calculate volumetric fog

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

flat out vec3 ambient_color;
flat out vec3 light_color;

#ifdef SCREENSPACE_VL
flat out vec2 light_pos;
flat out float cloud_occlusion;
#endif

#if defined WORLD_OVERWORLD
#include "/include/fog/overworld/parameters.glsl"
flat out OverworldFogParameters fog_params;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex4; // Sky map, lighting color palette
uniform sampler2D colortex8; // Cloud shadow map

uniform float rainStrength;
uniform float sunAngle;

uniform int worldTime;
uniform int worldDay;

uniform vec3 sun_dir;

uniform float wetness;

uniform float eye_skylight;

uniform vec2 view_res;

uniform float biome_temperate;
uniform float biome_arid;
uniform float biome_snowy;
uniform float biome_taiga;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_may_rain;
uniform float biome_may_snow;
uniform float biome_temperature;
uniform float biome_humidity;

uniform float world_age;
uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

uniform float desert_sandstorm;

#ifdef SCREENSPACE_VL
uniform mat4 gbufferProjection;
uniform vec3 view_light_dir;
uniform float blindness;
uniform int isEyeInWater;
#endif

#if defined WORLD_OVERWORLD
#include "/include/sky/projection.glsl"
#include "/include/weather/fog.glsl"
#endif

float get_cloud_occlusion(sampler2D colortex8) {
    #if defined CLOUDS_CUMULUS || defined CLOUDS_CUMULUS_CONGESTUS || defined CLOUDS_CUMULONIMBUS || defined CLOUDS_TOWERING_CUMULUS || defined CLOUDS_THUNDERHEAD
        
        const float occlusion_sample = 8.0;
        float total_occlusion = 0.0;

        vec2 light_pos_on_sampler = vec2(0.5, 0.5); 
        const float sample_radius = 0.2;

        for (int i = 0; i < int(occlusion_sample); i++) {
            float r = sqrt(float(i) + 0.5) / sqrt(occlusion_sample);
            float angle = float(i) * golden_angle;

            vec2 offset = polar_to_cartesian2(r * sample_radius, angle);
            vec2 checkcoord = light_pos_on_sampler + offset;

            if (checkcoord.x > 0.0 && checkcoord.x < 1.0 && checkcoord.y > 0.0 && checkcoord.y < 1.0) {
                ivec2 pixel_coord = ivec2(checkcoord * 256.0);
                float cloud_occlusion_sample = texelFetch(colortex8, pixel_coord, 0).r; 

                total_occlusion += clamp01(cloud_occlusion_sample);
            }
        }
        return total_occlusion / occlusion_sample;
    #else
        return 1.0; 
    #endif
}

void main() {
    uv = gl_MultiTexCoord0.xy;

    light_color = texelFetch(colortex4, ivec2(191, 0), 0).rgb;
#if defined WORLD_OVERWORLD && defined SH_SKYLIGHT
    ambient_color = texelFetch(colortex4, ivec2(191, 11), 0).rgb;
#else
    ambient_color = texelFetch(colortex4, ivec2(191, 1), 0).rgb;
#endif

#if defined WORLD_OVERWORLD
    fog_params = get_fog_parameters(get_weather());
#endif

#ifdef SCREENSPACE_VL
    if (isEyeInWater == 0 && blindness == 0.0) {
        vec3 sclip = project_and_divide(gbufferProjection, view_light_dir);
        light_pos = sclip.xy * 0.5 + 0.5;
    }
    cloud_occlusion = get_cloud_occlusion(colortex8);
#endif

    vec2 vertex_pos = gl_Vertex.xy;
    gl_Position = vec4(vertex_pos * 2.0 - 1.0, 0.0, 1.0);
}
