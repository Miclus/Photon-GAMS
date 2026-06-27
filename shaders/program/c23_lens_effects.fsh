/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge
  Photon GAMS exclusive program

  program/c23_lens_effects:
  Lens effects pass - handles lens flare, rain lens, and spreading frost

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 scene_color;

/* RENDERTARGETS: 0 */

in vec2 uv;

#ifdef LENS_FLARE
flat in vec3 sun_vec, up_vec;
flat in vec2 light_pos;
flat in float SoU;
flat in float cloud_occlusion;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color

uniform float frameTimeCounter;
uniform float aspectRatio;

#if defined LENS_FLARE && defined LENS_DIRT
uniform sampler2D colortex17; // Lens dirt texture
#endif

#if defined LENS_FLARE || defined RAIN_LENS || defined INOUT_WATER_EFFECT || defined SPREADING_FROST
uniform sampler2D noisetex;
#endif

#if defined LENS_FLARE || defined RAIN_LENS || defined INOUT_WATER_EFFECT
uniform int isEyeInWater;
uniform float rainStrength;
#endif

#if defined RAIN_LENS || defined SPREADING_FROST
uniform vec2 view_res;
#endif

#ifdef LENS_FLARE
uniform sampler2D depthtex0;
uniform sampler2D colortex11;
uniform float blindness;
#endif

#if defined LENS_FLARE && defined LF_MOONPHASE
uniform float moon_phase_brightness;
#endif

#if defined LENS_FLARE && defined LOD_MOD_ACTIVE
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform float near;
#endif

#ifdef RAIN_LENS
uniform float biome_may_rain;
uniform float eye_skylight;
#endif

#ifdef INOUT_WATER_EFFECT
uniform float camera_water_state;
#endif

#ifdef SPREADING_FROST
uniform float biome_may_snow;
uniform float is_snowing_biome;
#endif

#if defined SPREADING_FROST_SNOWING_ONLY && !defined LENS_FLARE && !defined RAIN_LENS
uniform float rainStrength;
#endif

// Includes

#include "/include/utility/color.glsl"

#if defined LENS_FLARE && defined LOD_MOD_ACTIVE
#include "/include/misc/lod_mod_support.glsl"
#endif

#ifdef LENS_FLARE
#include "/include/post_processing/lens_effects/lens_flare.glsl"
#endif

#ifdef RAIN_LENS
#include "/include/post_processing/lens_effects/rain_lens.glsl"
#endif

#ifdef INOUT_WATER_EFFECT
#include "/include/post_processing/lens_effects/inout_water_distortion.glsl"
#endif

#ifdef SPREADING_FROST
#include "/include/post_processing/lens_effects/spreading_frost.glsl"
#endif

void main() {
    scene_color = texture(colortex0, uv).rgb;

    // Enter/leave water distortion
#ifdef INOUT_WATER_EFFECT
	if (isEyeInWater <= 0.001) {
		leave_water_distortion(scene_color);
	}
	if (isEyeInWater >= 0.999) {
		underwater_distortion(scene_color);
	}
#endif

    // Spreading frost
#ifdef SPREADING_FROST
    if (biome_may_snow >= 0.001) {
        scene_color += spreading_frost();
    }
#endif

    // Lens flare
#if defined LENS_FLARE && !defined WORLD_NETHER && !defined WORLD_MOON
    if (isEyeInWater == 0) {
        lens_flare(scene_color);
    }
#endif

    // Rain lens
#if defined RAIN_LENS && !defined WORLD_NETHER && !defined WORLD_END && !defined WORLD_MOON
    if (isEyeInWater == 0 && rainStrength >= 0.001) {
        scene_color += rain_lens();
    }
#endif
}
