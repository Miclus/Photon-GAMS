/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c19_color_grading:
  Apply bloom, color grading and tone mapping then convert to rec. 709

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#ifdef LENS_FLARE
uniform sampler2D colortex8; // Cloud shadow map
uniform vec3 upPosition;
uniform vec3 sunPosition;
#endif

out vec2 uv;

#ifdef LENS_FLARE
flat out vec3 upVec, sunVec;
out float cloud_occlusion;
#endif

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

void main() {
	uv = gl_MultiTexCoord0.xy;

#ifdef LENS_FLARE
  upVec = normalize(upPosition);
  sunVec = normalize(sunPosition);
  cloud_occlusion = get_cloud_occlusion(colortex8);
#endif

	gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
