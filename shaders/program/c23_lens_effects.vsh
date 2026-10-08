/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge
  Photon GAMS exclusive program

  program/c23_lens_effects:
  Lens effects pass - handles lens flare, rain lens, and spreading frost

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#ifdef LENS_FLARE
uniform sampler2D colortex4; // sky map
uniform sampler2D colortex8; // Cloud shadow map
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 view_light_dir;
uniform vec2 taa_offset;
uniform vec2 view_res;
uniform float near;
uniform float far;
#endif

out vec2 uv;

#ifdef LENS_FLARE
flat out vec3 light_color;
flat out vec2 light_pos;
flat out float cloud_occlusion;
#endif

#ifdef LENS_FLARE
#include "/include/utility/space_conversion.glsl"
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

#ifdef LENS_FLARE
    int lighting_color_x = SKY_MAP_LIGHT_X;
	light_color   = texelFetch(colortex4, ivec2(lighting_color_x, 0), 0).rgb;

    vec3 sclip = project_and_divide(gbufferProjection, view_light_dir);
    light_pos = sclip.xy * 0.5 + 0.5;

    cloud_occlusion = get_cloud_occlusion(colortex8);
#endif

    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
