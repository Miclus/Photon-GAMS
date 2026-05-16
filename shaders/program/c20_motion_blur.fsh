/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/c16_motion_blur:
  Apply motion blur

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout (location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color

uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float frameTime;
uniform float near;
uniform float far;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

#define TEMPORAL_REPROJECTION
#include "/include/utility/space_conversion.glsl"

#define MOTION_BLUR_SAMPLES 20

void main() {
    ivec2 texel     = ivec2(gl_FragCoord.xy);
    ivec2 view_texel = ivec2(gl_FragCoord.xy * taau_render_scale);
    float depth     = texelFetch(depthtex0, view_texel, 0).x;

    vec3 center_color = texelFetch(colortex0, texel, 0).rgb;

    if (depth < hand_depth) {
        scene_color = center_color;
        return;
    }

    vec2 velocity = uv - reproject(vec3(uv, depth)).xy;

    // Clamp velocity magnitude and fade at screen edges
    float vel_mag = length(velocity);
    velocity *= min(vel_mag, 0.02) / max(vel_mag, 1e-6);

    vec2 increment = velocity * (0.5 * MOTION_BLUR_INTENSITY / float(MOTION_BLUR_SAMPLES));
    vec2 pos       = uv - increment * (float(MOTION_BLUR_SAMPLES) * 0.5);
    vec3 color_sum = vec3(0.0);

    for (uint i = 0u; i < MOTION_BLUR_SAMPLES; ++i) {
        vec2 clamped   = clamp(pos, 0.0, 1.0);
        ivec2 tap      = ivec2(clamped * view_res);
        ivec2 depth_tap = ivec2(clamped * view_res * taau_render_scale);

        bool valid = all(equal(clamped, pos)) && texelFetch(depthtex0, depth_tap, 0).x > hand_depth;

        color_sum += valid ? texelFetch(colortex0, tap, 0).rgb : center_color;
        pos += increment;
    }

    scene_color = color_sum / float(MOTION_BLUR_SAMPLES);
}
