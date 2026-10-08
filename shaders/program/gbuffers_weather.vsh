/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/gbuffers_weather:
  Handle rain and snow particles

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;
out vec2 lmcoord;
out vec3 scene_pos; // fixed relative to world blocks
flat out vec4 tint;

// ------------
//   Uniforms
// ------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;

uniform int frameCounter;

uniform vec2 taa_offset;
uniform vec2 view_pixel_size;

void main() {
    lmcoord = mat2(gl_TextureMatrix[1]) * gl_MultiTexCoord1.xy;
    lmcoord = lmcoord * (255.0 / 256.0) + (0.5 / 256.0);

    uv = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy
        + gl_TextureMatrix[0][3].xy;

    tint = gl_Color;

    vec3 view_pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

#ifdef SLANTED_RAIN
    const float rain_tilt_amount = -0.25;
    const float rain_tilt_angle = 30.0 * degree;
    const vec2 rain_tilt_offset
        = rain_tilt_amount * vec2(cos(rain_tilt_angle), sin(rain_tilt_angle));

    vec3 p_space = transform(gbufferModelViewInverse, view_pos);
    vec3 world_pos = p_space + cameraPosition;

    float tilt_wave = 0.7 + 0.3 * sin(dot(world_pos, vec3(5.0)));
    p_space.xz -= rain_tilt_offset * tilt_wave * p_space.y;

    view_pos = transform(gbufferModelView, p_space);
    scene_pos = p_space;
#else
    scene_pos = transform(gbufferModelViewInverse, view_pos);
#endif

    vec4 clip_pos = project(gl_ProjectionMatrix, view_pos);

#if defined TAA && defined TAAU
    clip_pos.xy = clip_pos.xy * taau_render_scale
        + clip_pos.w * (taau_render_scale - 1.0);
    clip_pos.xy += taa_offset * clip_pos.w;
#elif defined TAA
    clip_pos.xy += taa_offset * clip_pos.w * 0.66;
#endif

    gl_Position = clip_pos;
}
