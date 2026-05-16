/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/gbuffers_skytextured:
  Handle vanilla sun and moon and custom skies

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec3 frag_color;

/* RENDERTARGETS: 0 */

in vec2 uv;
in vec3 view_pos;

#if MC_VERSION >= 260100
in vec2 uv_mid;
#endif

flat in vec3 tint;
flat in vec3 sun_color;
flat in vec3 moon_color;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform int renderStage;

uniform vec3 view_sun_dir;

#include "/include/sky/atmosphere.glsl"
#include "/include/utility/color.glsl"

const float vanilla_sun_luminance = SUN_LUMINANCE * SUN_DISK_INTENSITY;
const float moon_luminance = MOON_LUMINANCE * MOON_DISK_INTENSITY;

void main() {
    vec2 new_uv = uv;
    vec2 offset;

    if (renderStage == MC_RENDER_STAGE_CUSTOM_SKY) {
#ifdef CUSTOM_SKY
        frag_color = texture(gtexture, new_uv).rgb;
        frag_color = srgb_eotf_inv(frag_color) * rec709_to_working_color;
        frag_color *= CUSTOM_SKY_BRIGHTNESS;
#else
        frag_color = vec3(0.0);
#endif
    } else if (dot(view_pos, view_sun_dir) > 0.0) {
        // Sun

        // NB: not using renderStage to distinguish sun and moon because it's
        // broken in Iris for Minecraft 1.21.4

        // Cut out the sun itself (discard the halo around it)
        if (max_of(abs(offset)) > 0.25) {
            discard;
        }
        offset = uv * 2.0 - 1.0;

#ifdef VANILLA_SUN
        frag_color = texture(gtexture, new_uv).rgb;
        frag_color = srgb_eotf_inv(frag_color) * rec709_to_working_color;
        frag_color *= dot(frag_color, luminance_weights)
            * (sunlight_color * vanilla_sun_luminance) * sun_color;
#else
        frag_color = vec3(0.0);
#endif
    } else {
        // Moon
#if MOON_TYPE == MOON_VANILLA
        frag_color
            = texture(gtexture, new_uv).rgb * vec3(MOON_R, MOON_G, MOON_B);
#else
        // Procedural moon drawn in deferred sky (draw_moon) to avoid UV issues
        frag_color = vec3(0.0);
#endif

        frag_color = srgb_eotf_inv(frag_color) * rec709_to_working_color;
        frag_color *= sunlight_color * moon_luminance;

        /* #if defined VANILLA_SUN && defined WORLD_SPACE
            case MC_RENDER_STAGE_CUSTOM_SKY:
                vec4 sky_color = texture(gtexture, new_uv);
                sky_color.rgb = sky_color.rgb * tint * smoothstep(0.0, 0.2,
        sky_color.a); if (max_of(sky_color.rgb) < 0.1) discard;

                // alpha of 4 <=> custom sky
                scene_color.a = 4.0 / 255.0;
                scene_color.rgb = sky_color.rgb;

                break;
        #endif */
    }
}
