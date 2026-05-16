// "Rain drops on screen"
// https://www.shadertoy.com/view/ldSBWW
// Author: Élie Michel
// License: CC BY 3.0
// July 2017

vec3 rain_lens() {

    vec2 n = texture(noisetex, uv * 0.1).rg;  // Displacement

    vec4 f;

    // Loop through the different inverse sizes of drops
    for (float r = 4.0; r > 0.0; r--) {
        vec2 x = view_res * r * 0.015;  // Number of potential drops (in a grid)
        vec2 p = tau * uv * x + (n - 0.5) * 2.0;
        vec2 s = sin(p);

        // Current drop properties. Coordinates are rounded to ensure a
        // consistent value among the fragment of a given drop.
        vec4 d = texture(noisetex, round(uv * x - 0.25) / x);

        // Drop shape and fading
        float t = (s.x + s.y) * max0(1.0 - fract(frameTimeCounter * (d.b + 0.1) * RAINDROP_SPEED + d.g) * 2.0);

        // d.r -> only x% of drops are kept on, with x depending on the size of drops
        if (d.r < (5.0 - r) * 0.08 && t > 0.5) {
            vec3 v = normalize(-vec3(cos(p), mix(0.2, 2.0, t - 0.5)));
            // f = vec4(v * 0.5 + 0.5, 1.0);  // show normals
            
            // Poor man's refraction (no visual need to do more)
            f = texture(colortex0, uv - v.xy * 0.3);
        }
    }

    return f.rgb * 0.4 * RAIN_LENS_INTENSITY * rainStrength * biome_may_rain * eye_skylight;
}