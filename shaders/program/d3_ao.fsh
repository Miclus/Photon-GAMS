/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge
  Modified by xuyin2333

  program/d3_ao:
  Calculate ambient occlusion

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(
    location = 0
) out vec4 ambient; // ao, ambient SSS, octahedrally encoded bent normal
layout(location = 1) out vec2 ambient_history_data; // depth, pixel age

/* RENDERTARGETS: 6,14 */

in vec2 uv;

//   Uniforms
// ------------

uniform sampler2D noisetex;

uniform sampler2D colortex1; // gbuffer 0
uniform sampler2D colortex2; // gbuffer 1
uniform sampler2D colortex5; // previous frame scene color (GI radiance source)
#if defined WORLD_OVERWORLD && defined SH_SKYLIGHT
uniform sampler2D colortex4; // sky map (sky SH stored at texels 191,2..10)
#endif
uniform sampler2D colortex6; // ambient lighting data
uniform sampler2D colortex14; // ambient lighting history data

uniform sampler2D depthtex1;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;
uniform float eyeAltitude;

uniform int frameCounter;

uniform vec3 light_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;
uniform vec2 clouds_offset;

uniform bool world_age_changed;

// ------------
//   Includes
// ------------

#define TEMPORAL_REPROJECTION
#include "/include/misc/lod_mod_support.glsl"
#include "/include/utility/bicubic.glsl"
#include "/include/utility/dithering.glsl"
#include "/include/utility/encoding.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/slerp.glsl"
#include "/include/utility/space_conversion.glsl"

#if defined WORLD_OVERWORLD && defined SH_SKYLIGHT
#include "/include/utility/spherical_harmonics.glsl"
#endif

#if SHADER_AO == SHADER_AO_SSAO
#include "/include/lighting/ao/ssao.glsl"
#endif

#if SHADER_AO == SHADER_AO_GTAO
#include "/include/lighting/ao/gtao.glsl"
#endif

#if SHADER_AO == SHADER_AO_VBIL
#include "/include/lighting/ao/vbil.glsl"
#endif

const float ao_render_scale = 0.5;

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);
    ivec2 view_texel
        = ivec2(gl_FragCoord.xy * (taau_render_scale / ao_render_scale));

    if (clamp(view_texel, ivec2(0), ivec2(view_res)) != view_texel) {
        return;
    }

    float depth = texelFetch(combined_depth_tex, view_texel, 0).x;

#ifndef NORMAL_MAPPING
    vec4 gbuffer_data = texelFetch(colortex1, view_texel, 0);
#else
    vec4 gbuffer_data = texelFetch(colortex2, view_texel, 0);
#endif
    vec2 dither = vec2(
        texelFetch(noisetex, texel & 511, 0).b,
        texelFetch(noisetex, (texel + 249) & 511, 0).b
    );

    // Distant Horizons support

#ifdef LOD_MOD_ACTIVE
    float depth_mc = texelFetch(depthtex1, view_texel, 0).x;
    float depth_lod = texelFetch(lod_depth_tex, view_texel, 0).x;
    bool is_lod = is_lod_terrain(depth_mc, depth_lod);
#else
#define depth_mc depth
    const bool is_lod = false;
#endif

    bool is_hand;
    fix_hand_depth(depth_mc, is_hand);

    vec3 screen_pos = vec3(uv, depth);
    vec3 view_pos = screen_to_view_space(
        combined_projection_matrix_inverse,
        screen_pos,
        true
    );
    vec3 scene_pos = view_to_scene_space(view_pos);

    vec3 previous_screen_pos = reproject_scene_space(scene_pos, false, false);

    if (depth == 1.0) {
        ambient = vec4(1.0, 0.0, 0.0, 0.0);
        ambient_history_data = vec2(0.0);
        return;
    }

#ifdef NORMAL_MAPPING
    vec3 world_normal = decode_unit_vector(gbuffer_data.xy);

#ifdef LOD_MOD_ACTIVE
    if (is_lod) {
        vec4 gbuffer_data_0 = texelFetch(colortex1, view_texel, 0);
        world_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data_0.z));
    }
#endif
#else
    vec3 world_normal = decode_unit_vector(unpack_unorm_2x8(gbuffer_data.z));
#endif

    vec3 view_normal = mat3(gbufferModelView) * world_normal;

    dither = r2(frameCounter, dither);

    // Extract skylight from gbuffer for VBIL GI
    vec2 light_levels = unpack_unorm_2x8(gbuffer_data.w);
    float skylight = light_levels.y;

    // Calculate AO

    vec2 ao;
    vec3 bent_normal;

#if SHADER_AO == SHADER_AO_NONE
    ao = vec2(1.0, 0.0);
    bent_normal = view_normal;
#elif SHADER_AO == SHADER_AO_SSAO
    ao.x = compute_ssao(screen_pos, view_pos, view_normal, dither);
    ao.y = 0.0;
    bent_normal = view_normal;
#elif SHADER_AO == SHADER_AO_GTAO
    ao = compute_gtao(
        screen_pos,
        view_pos,
        view_normal,
        dither,
        is_lod,
        bent_normal
    );
#elif SHADER_AO == SHADER_AO_VBIL
    // VBIL needs 4 dither values:
    //   .x = slice angle rotation (ign, per-frame)
    //   .y = (unused, kept for parity)
    //   .z = ray start offset (from r2)
    //   .w = sub-texel sector boundary dither (from r2)
    float vbil_ign = interleaved_gradient_noise(gl_FragCoord.xy, frameCounter);
    vec4 vbil_dither = vec4(vec2(vbil_ign), dither);
    vec4 vbil_output = compute_vbil(
        screen_pos,
        view_pos,
        view_normal,
        vbil_dither,
        is_lod,
        colortex5
    );

#if defined WORLD_OVERWORLD && defined SH_SKYLIGHT
    // Sky SH mixing: fold direct sky irradiance into the GI channel, modulated
    // by the unoccluded fraction (vbil_output.x = ao = visibility). The
    // colortex5 bounce alone can't deliver sky light.
    // Applied BEFORE temporal accumulation so the history buffer stays consistent
    // (no double-counting).
    vec3 sky_sh[9];
    sky_sh[0] = texelFetch(colortex4, ivec2(191, 2), 0).rgb;
    sky_sh[1] = texelFetch(colortex4, ivec2(191, 3), 0).rgb;
    sky_sh[2] = texelFetch(colortex4, ivec2(191, 4), 0).rgb;
    sky_sh[3] = texelFetch(colortex4, ivec2(191, 5), 0).rgb;
    sky_sh[4] = texelFetch(colortex4, ivec2(191, 6), 0).rgb;
    sky_sh[5] = texelFetch(colortex4, ivec2(191, 7), 0).rgb;
    sky_sh[6] = texelFetch(colortex4, ivec2(191, 8), 0).rgb;
    sky_sh[7] = texelFetch(colortex4, ivec2(191, 9), 0).rgb;
    sky_sh[8] = texelFetch(colortex4, ivec2(191, 10), 0).rgb;

    vec3 sky_irradiance = sh_evaluate_irradiance(
        sky_sh, world_normal, vbil_output.x
    );
    vbil_output.yzw += sky_irradiance * cube(skylight);
#endif
#endif

    // Temporal accumulation

    const float max_accumulated_frames = 10.0;
    const float depth_rejection_strength = 16.0;
    const float offcenter_rejection_strength = 0.25;

#if SHADER_AO == SHADER_AO_VBIL
    // VBIL stores vec4(ao, gi) — no bent normal in colortex6
    const float vbil_max_accumulated_frames = 8.0;

    vec4 history = max0(
        catmull_rom_filter_fast(colortex6, previous_screen_pos.xy, 0.65)
    );
    vec2 history_data = max0(texture(colortex14, previous_screen_pos.xy).xy);

    float view_norm_vbil = rcp_length(view_pos);
    float NoV_vbil = abs(dot(view_normal, view_pos)) * view_norm_vbil;

    if (clamp01(previous_screen_pos.xy) == previous_screen_pos.xy) {
        float history_depth = 1.0 - history_data.x;
        float pixel_age = min(history_data.y, vbil_max_accumulated_frames);

        float z0 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            depth
        );
        float z1 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            history_depth
        );
        float depth_weight = exp2(-abs(z0 - z1) * depth_rejection_strength * NoV_vbil * view_norm_vbil);

        vec2 pixel_offset = 1.0
            - abs(2.0 * fract(view_res * ao_render_scale * previous_screen_pos.xy) - 1.0);
        float offcenter_rejection = sqrt(pixel_offset.x * pixel_offset.y)
                * offcenter_rejection_strength
            + (1.0 - offcenter_rejection_strength);

        // Reprojection-velocity rejection
        vec2 reproj_delta = abs(screen_pos.xy - previous_screen_pos.xy) * view_res;
        float motion_weight = exp2(-max_of(reproj_delta) * 2.0);

        pixel_age *= depth_weight * offcenter_rejection * motion_weight * float(history_depth != 1.0);
        float history_weight = pixel_age / (pixel_age + 1.0);

        vbil_output = mix(vbil_output, history, history_weight);

        ambient = vbil_output;
        ambient_history_data = vec2(1.0 - depth, pixel_age + 1.0);
    } else {
        ambient = vbil_output;
        ambient_history_data = vec2(0.0);
    }
#else
    // GTAO / SSAO: vec2(ao, ambient_sss) + bent normal in .zw

    vec4 history = max0(
        catmull_rom_filter_fast(colortex6, previous_screen_pos.xy, 0.65)
    );
    vec2 history_data = max0(texture(colortex14, previous_screen_pos.xy).xy);

    if (clamp01(previous_screen_pos.xy) == previous_screen_pos.xy) {
        // Unpack history data
        float history_depth = 1.0 - history_data.x;
        float pixel_age = min(history_data.y, max_accumulated_frames);

        vec3 history_bent_normal;
        history_bent_normal.xy = history.zw * 2.0 - 1.0;
        history_bent_normal.z = sqrt(
            clamp01(1.0 - dot(history_bent_normal.xy, history_bent_normal.xy))
        );

        // Reproject bent normal
        history_bent_normal
            = history_bent_normal * mat3(gbufferPreviousModelView);
        history_bent_normal = mat3(gbufferModelView) * history_bent_normal;

        // Depth rejection
        float view_norm = rcp_length(view_pos);
        float NoV = abs(dot(view_normal, view_pos))
            * view_norm; // NoV / sqrt(length(view_pos))
        float z0 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            depth
        );
        float z1 = screen_to_view_space_depth(
            combined_projection_matrix_inverse,
            history_depth
        );
        float depth_weight
            = exp2(-abs(z0 - z1) * depth_rejection_strength * NoV * view_norm);

        // Offcenter rejection from Jessie, which is originally by Zombye
        // Reduces blur in motion
        vec2 pixel_offset = 1.0
            - abs(2.0
                      * fract(
                          view_res * ao_render_scale * previous_screen_pos.xy
                      )
                  - 1.0);
        float offcenter_rejection = sqrt(pixel_offset.x * pixel_offset.y)
                * offcenter_rejection_strength
            + (1.0 - offcenter_rejection_strength);

        pixel_age
            *= depth_weight * offcenter_rejection * float(history_depth != 1.0);

        // Blend with history
        float history_weight = pixel_age / (pixel_age + 1.0);

        ao = mix(ao, history.xy, history_weight);
        bent_normal = slerp(bent_normal, history_bent_normal, history_weight);

        ambient = vec4(ao, bent_normal.xy * 0.5 + 0.5);
        ambient_history_data = vec2(1.0 - depth, pixel_age + 1.0);
    } else {
        ambient = vec4(ao, bent_normal.xy * 0.5 + 0.5);
        ambient_history_data = vec2(0.0);
    }
#endif

    if (is_hand) {
        ambient_history_data.x = 1.0;
    }
}
