#if !defined INCLUDE_SKY_ATMOSPHERE
#define INCLUDE_SKY_ATMOSPHERE

#include "/include/post_processing/aces/matrices.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/geometry.glsl"
#include "/include/utility/phase_functions.glsl"

// These have to be macros so that they can be used by constant expressions
#define cone_angle_to_solid_angle(theta) (tau * (1.0 - cos(theta)))
#define solid_angle_to_cone_angle(theta) acos(1.0 - (theta) / tau)

const vec3 sunlight_color
    = vec3(1.026, 0.988, 1.016)
    * rec709_to_rec2020;

const float sun_angular_radius = SUN_ANGULAR_RADIUS * degree;
const float moon_angular_radius = MOON_ANGULAR_RADIUS * degree;

const ivec3 transmittance_res = ivec3(/* mu */ 256, /* r */ 64, /* turbidity */ 8);
const ivec4 scattering_res = ivec4(/* nu */ 16, /* mu */ 64, /* mu_s */ 32, /* turbidity */ 8);

const float min_mu_s = -0.35;

const float min_turbidity = 0.1;
const float max_turbidity = 8.0;

// Atmosphere boundaries

const float planet_radius = 6371e3; // m

const float atmosphere_inner_radius = planet_radius - 1e3; // m
const float atmosphere_outer_radius = planet_radius + 110e3; // m

const float planet_radius_sq = planet_radius * planet_radius;
const float atmosphere_thickness
    = atmosphere_outer_radius - atmosphere_inner_radius;
const float atmosphere_inner_radius_sq
    = atmosphere_inner_radius * atmosphere_inner_radius;
const float atmosphere_outer_radius_sq
    = atmosphere_outer_radius * atmosphere_outer_radius;

// Atmosphere coefficients

const float air_mie_albedo = 0.9;
const float air_mie_energy_parameter
    = 3000.0; // Energy parameter for the Klein-Nishina phase function
const float air_mie_g
    = 0.77; // Anisotropy parameter for Henyey-Greenstein phase function

const vec2 air_scale_heights = vec2(8.4e3, 1.25e3); // m

// Coefficients for Rec. 709 primaries transformed to AP1
const vec3 air_rayleigh_coefficient
    = vec3(8.059375432e-06, 1.671209429e-05, 4.080133294e-05)
    * rec709_to_ap1_unlit;
const vec3 air_mie_coefficient
    = vec3(1.666442358e-06, 1.812685127e-06, 1.958927896e-06)
    * rec709_to_ap1_unlit;
const vec3 air_ozone_coefficient
    = vec3(8.304280072e-07, 1.314911970e-06, 5.440679729e-08)
    * rec709_to_ap1_unlit;

const mat2x3 air_scattering_coefficients
    = mat2x3(air_rayleigh_coefficient, air_mie_albedo* air_mie_coefficient);
const mat3x3 air_extinction_coefficients = mat3x3(
    air_rayleigh_coefficient,
    air_mie_coefficient,
    air_ozone_coefficient
);

uniform float atmosphere_saturation_boost_amount;

float atmosphere_mie_phase(float nu, bool use_klein_nishina_phase) {
    return use_klein_nishina_phase
        ? klein_nishina_phase_area(
              nu,
              air_mie_energy_parameter,
              moon_angular_radius
          )
        : henyey_greenstein_phase(nu, air_mie_g);
}

vec3 atmosphere_mie_phase_sun(float nu) {
    float r = nvidia_phase_area(nu, 0.85, 1.0, sun_angular_radius);
    float g = nvidia_phase_area(nu, 0.86, 1.0, sun_angular_radius);
    float b = nvidia_phase_area(nu, 0.87, 1.0, sun_angular_radius);
    vec3 nvidiaRGB = vec3(r, g, b);
    return nvidiaRGB * 0.12; // artistic scale
}

vec3 atmosphere_mie_phase_moon(float nu) {
    float moonIntensity = 1.02;

    float t = float(moonPhase) / 4.0;
    t = t > 1.0 ? 2.0 - t : t;
    t = sqr(1.0 - t) * 0.04 + 0.96; // small phase difference

    float r = nvidia_phase_area(nu, 0.895 * t, 1.0, 2 * moon_angular_radius);
    float g = nvidia_phase_area(nu, 0.90 * t, 1.0, 2 * moon_angular_radius);
    float b = nvidia_phase_area(nu, 0.905 * t, 1.0, 2 * moon_angular_radius);
    vec3 nvidiaRGB = vec3(r, g, b);
    return nvidiaRGB * moonIntensity;
}

// Post-processing applied to the atmosphere color
// mu: cos(zenith_angle) — 1 at zenith, 0 at horizon, -1 at nadir
// nu_sun: cos(view_sun_angle) — 1 toward the sun, -1 away
vec3 atmosphere_post_processing(vec3 atmosphere, float mu, float nu_sun) {
    float lum = dot(atmosphere, luminance_weights_rec2020);

    // Base saturation from settings
    float sat = ATMOSPHERE_SATURATION_BOOST_INTENSITY
        * atmosphere_saturation_boost_amount;

    // Saturate via chrominance scaling — safe for moderate overshoot
    // (unlike mix() which wraps around past 1.0)
    vec3 chroma = atmosphere - lum;
    atmosphere = lum + chroma * sat;
    return max(atmosphere, vec3(0.0));
}

// Simple overload — matches original Photon behavior
vec3 atmosphere_post_processing(vec3 atmosphere) {
    return mix(
        vec3(dot(atmosphere, luminance_weights_rec2020)),
        atmosphere,
        0.50 * atmosphere_saturation_boost_amount
    );
}

/*
 * Mapping functions from Eric Bruneton's 2020 atmosphere implementation
 * https://ebruneton.github.io/precomputed_atmospheric_scattering/atmosphere/functions.glsl.html
 *
 * nu: cos view-light angle
 * mu: cos view-zenith angle
 * mu_s: cos light-zenith angle
 * r: distance to planet centre
 */

vec3 atmosphere_density(float r) {
    const vec2 rcp_scale_heights = rcp(air_scale_heights);
    const vec2 scaled_planet_radius = planet_radius * rcp_scale_heights;

    vec2 rayleigh_mie = exp(r * -rcp_scale_heights + scaled_planet_radius);

    // Ozone density distribution from Jessie -
    // https://www.desmos.com/calculator/b66xr8madc
    float altitude_km = r * 1e-3 - (planet_radius * 1e-3);
    float o1 = 12.5 * exp(rcp(8.0) * (0.0 - altitude_km));
    float o2
        = 30.0 * exp(rcp(80.0) * (18.0 - altitude_km) * (altitude_km - 18.0));
    float o3
        = 75.0 * exp(rcp(50.0) * (23.5 - altitude_km) * (altitude_km - 23.5));
    float o4
        = 50.0 * exp(rcp(150.0) * (30.0 - altitude_km) * (altitude_km - 30.0));
    float ozone = 7.428e-3 * (o1 + o2 + o3 + o4);

    return vec3(rayleigh_mie, ozone);
}

float get_atmosphere_turbidity_uv(float turbidity) {
    turbidity = linear_step(min_turbidity, max_turbidity, turbidity);
    turbidity = sqrt(turbidity);
    turbidity = get_uv_from_unit_range(turbidity, scattering_res.w);
    return turbidity;
}

#if defined ATMOSPHERE_SCATTERING_LUT
vec4 texture_4d(sampler3D sampler, vec4 coord, const ivec4 res) {
    float i, f = modf(coord.w * float(res.w) - 0.5, i);
    coord.z += i;
    float texel = 1.0 / float(res.w);

    vec4 s0 = texture(sampler, vec3(coord.xy, coord.z * texel));
    vec4 s1 = texture(sampler, vec3(coord.xy, coord.z * texel + texel));

    return mix(s0, s1, f);
}

vec3 atmosphere_scattering_uv(float nu, float mu, float mu_s) {
    // Improved mapping for nu from Spectrum by Zombye

    float half_range_nu = sqrt((1.0 - mu * mu) * (1.0 - mu_s * mu_s));
    float nu_min = mu * mu_s - half_range_nu;
    float nu_max = mu * mu_s + half_range_nu;

    float u_nu
        = (nu_min == nu_max) ? nu_min : (nu - nu_min) / (nu_max - nu_min);
    u_nu = get_uv_from_unit_range(u_nu, scattering_res.x);

    // Stretch the sky near the horizon upwards (to make it easier to admire the
    // sunset without zooming in)

    if (mu > 0.0) {
        mu *= sqrt(sqrt(mu));
    }

    // Mapping for mu

    const float r = planet_radius; // distance to the planet centre
    const float H = sqrt(
        atmosphere_outer_radius_sq - atmosphere_inner_radius_sq
    ); // distance to the atmosphere upper limit for a horizontal ray at ground
       // level
    const float rho = sqrt(
        max0(planet_radius * planet_radius - atmosphere_inner_radius_sq)
    ); // distance to the horizon

    // Discriminant of the quadratic equation for the intersections of the ray
    // (r, mu) with the ground
    float rmu = r * mu;
    float discriminant = rmu * rmu - r * r + atmosphere_inner_radius_sq;

    float u_mu;
    if (mu < 0.0 && discriminant >= 0.0) { // Ray (r, mu) intersects ground
        // Distance to the ground for the ray (r, mu) and its minimum and
        // maximum values over all mu
        float d = -rmu - sqrt(max0(discriminant));
        float d_min = r - atmosphere_inner_radius;
        float d_max = rho;

        u_mu = d_max == d_min ? 0.0 : (d - d_min) / (d_max - d_min);
        u_mu = get_uv_from_unit_range(u_mu, scattering_res.y / 2);
        u_mu = 0.5 - 0.5 * u_mu;
    } else {
        // Distance to exit the atmosphere outer limit for the ray (r, mu) and
        // its minimum and maximum values over all mu
        float d = -rmu + sqrt(discriminant + H * H);
        float d_min = atmosphere_outer_radius - r;
        float d_max = rho + H;

        u_mu = (d - d_min) / (d_max - d_min);
        u_mu = get_uv_from_unit_range(u_mu, scattering_res.y / 2);
        u_mu = 0.5 + 0.5 * u_mu;
    }

    // Mapping for mu_s

    // Distance to the atmosphere outer limit for the ray
    // (atmosphere_inner_radius, mu_s)
    float d = intersect_sphere(
                  mu_s,
                  atmosphere_inner_radius,
                  atmosphere_outer_radius
    )
                  .y;
    float d_min = atmosphere_thickness;
    float d_max = H;
    float a = (d - d_min) / (d_max - d_min);

    // Distance to the atmosphere upper limit for the ray
    // (atmosphere_inner_radius, min_mu_s)
    float D = intersect_sphere(
                  min_mu_s,
                  atmosphere_inner_radius,
                  atmosphere_outer_radius
    )
                  .y;
    float A = (D - d_min) / (d_max - d_min);

    // An ad-hoc function equal to 0 for mu_s = min_mu_s (because then d = D and
    // thus a = A, equal to 1 for mu_s = 1 (because then d = d_min and thus a =
    // 0), and with a large slope around mu_s = 0, to get more texture samples
    // near the horizon
    float u_mu_s = get_uv_from_unit_range(
        max0(1.0 - a / A) / (1.0 + a),
        scattering_res.z
    );

    return vec3(u_nu, u_mu, u_mu_s);
}

vec3 atmosphere_scattering(
    float nu,
    float mu,
    float mu_s,
    bool use_klein_nishina_phase
) {
#ifndef SKY_GROUND
    float horizon_mu = mix(-0.01, 0.03, smoothstep(-0.05, 0.1, mu_s));
    mu = max(mu, horizon_mu);
#endif

    vec4 coord;
    coord.xyz = atmosphere_scattering_uv(nu, mu, mu_s);
    coord.w   = get_atmosphere_turbidity_uv(1.0);

    float mie_phase = atmosphere_mie_phase(nu, use_klein_nishina_phase);

    vec3 scattering;

    // Rayleigh + multiple scattering
    coord.x *= 0.5;
    scattering = texture_4d(ATMOSPHERE_SCATTERING_LUT, coord, scattering_res).rgb;

    // Single mie scattering
    coord.x += 0.5;
    scattering += texture_4d(ATMOSPHERE_SCATTERING_LUT, coord, scattering_res).rgb * mie_phase;

    return atmosphere_post_processing(scattering, mu, nu);
}

vec3 atmosphere_scattering(
    vec3 ray_dir,
    vec3 light_dir,
    bool use_klein_nishina_phase
) {
    float nu = dot(ray_dir, light_dir);
    float mu = ray_dir.y;
    float mu_s = light_dir.y;

    return atmosphere_scattering(nu, mu, mu_s, use_klein_nishina_phase);
}

// Samples atmospheric scattering LUT for both sun and moon together
// Prevents a few repeated calculations
vec3 atmosphere_scattering(
    vec3 ray_dir,
    vec3 sun_color,
    vec3 sun_dir,
    vec3 moon_color,
    vec3 moon_dir,
    bool use_klein_nishina_phase
) {
    // Calculate nu, mu, mu_s

    float mu = ray_dir.y;

    float nu_sun = dot(ray_dir, sun_dir);
    float nu_moon = dot(ray_dir, moon_dir);

    float mu_sun = sun_dir.y;
    float mu_moon = moon_dir.y;

#ifndef SKY_GROUND
    float horizon_mu = mix(
        -0.01,
        0.03,
        clamp01(smoothstep(-0.05, 0.1, mu_sun) + smoothstep(0.05, 0.1, mu_moon))
    );
    mu = max(mu, horizon_mu);
#endif

    // Improved mapping for nu from Spectrum by Zombye

    float half_range_nu, nu_min, nu_max;

    half_range_nu = sqrt((1.0 - mu * mu) * (1.0 - mu_sun * mu_sun));
    nu_min = mu * mu_sun - half_range_nu;
    nu_max = mu * mu_sun + half_range_nu;

    float u_nu_sun
        = (nu_min == nu_max) ? nu_min : (nu_sun - nu_min) / (nu_max - nu_min);
    u_nu_sun = get_uv_from_unit_range(u_nu_sun, scattering_res.x);

    half_range_nu = sqrt((1.0 - mu * mu) * (1.0 - mu_moon * mu_moon));
    nu_min = mu * mu_moon - half_range_nu;
    nu_max = mu * mu_moon + half_range_nu;

    float u_nu_moon
        = (nu_min == nu_max) ? nu_min : (nu_moon - nu_min) / (nu_max - nu_min);
    u_nu_moon = get_uv_from_unit_range(u_nu_moon, scattering_res.x);

    // Stretch the sky near the horizon upwards (to make it easier to admire the
    // sunset without zooming in)

    if (mu > 0.0) {
        mu *= sqrt(sqrt(mu));
    }

    // Mapping for mu

    const float r = planet_radius; // distance to the planet centre
    const float H = sqrt(
        atmosphere_outer_radius_sq - atmosphere_inner_radius_sq
    ); // distance to the atmosphere upper limit for a horizontal ray at ground
       // level
    const float rho = sqrt(
        max0(planet_radius * planet_radius - atmosphere_inner_radius_sq)
    ); // distance to the horizon

    // Discriminant of the quadratic equation for the intersections of the ray
    // (r, mu) with the ground
    float rmu = r * mu;
    float discriminant = rmu * rmu - r * r + atmosphere_inner_radius_sq;

    float u_mu;
    if (mu < 0.0 && discriminant >= 0.0) { // Ray (r, mu) intersects ground
        // Distance to the ground for the ray (r, mu) and its minimum and
        // maximum values over all mu
        float d = -rmu - sqrt(max0(discriminant));
        float d_min = r - atmosphere_inner_radius;
        float d_max = rho;

        u_mu = d_max == d_min ? 0.0 : (d - d_min) / (d_max - d_min);
        u_mu = get_uv_from_unit_range(u_mu, scattering_res.y / 2);
        u_mu = 0.5 - 0.5 * u_mu;
    } else {
        // Distance to exit the atmosphere outer limit for the ray (r, mu) and
        // its minimum and maximum values over all mu
        float d = -rmu + sqrt(discriminant + H * H);
        float d_min = atmosphere_outer_radius - r;
        float d_max = rho + H;

        u_mu = (d - d_min) / (d_max - d_min);
        u_mu = get_uv_from_unit_range(u_mu, scattering_res.y / 2);
        u_mu = 0.5 + 0.5 * u_mu;
    }

    // Mapping for mu_s

    float d, a;

    const float d_min = atmosphere_thickness;
    const float d_max = H;

    // Distance to the atmosphere upper limit for the ray
    // (atmosphere_inner_radius, min_mu_s)
    float D = intersect_sphere(
                  min_mu_s,
                  atmosphere_inner_radius,
                  atmosphere_outer_radius
    )
                  .y;
    float A = (D - d_min) / (d_max - d_min);

    // Distance to the atmosphere outer limit for the ray
    // (atmosphere_inner_radius, mu_s)
    d = intersect_sphere(
            mu_sun,
            atmosphere_inner_radius,
            atmosphere_outer_radius
    )
            .y;
    a = (d - d_min) / (d_max - d_min);

    // An ad-hoc function equal to 0 for mu_s = min_mu_s (because then d = D and
    // thus a = A, equal to 1 for mu_s = 1 (because then d = d_min and thus a =
    // 0), and with a large slope around mu_s = 0, to get more texture samples
    // near the horizon
    float u_mu_sun = get_uv_from_unit_range(
        max0(1.0 - a / A) / (1.0 + a),
        scattering_res.z
    );

    d = intersect_sphere(
            mu_moon,
            atmosphere_inner_radius,
            atmosphere_outer_radius
    )
            .y;
    a = (d - d_min) / (d_max - d_min);

    float u_mu_moon = get_uv_from_unit_range(
        max0(1.0 - a / A) / (1.0 + a),
        scattering_res.z
    );

    // Sample atmosphere LUT (4D with turbidity)

    float u_turbidity = get_atmosphere_turbidity_uv(1.0);

    vec4 uv_sc = vec4(
        u_nu_sun * 0.5,
        u_mu,
        u_mu_sun,
        u_turbidity
    ); // Rayleigh + multiple scattering, sunlight
    vec4 uv_sm = vec4(
        u_nu_sun * 0.5 + 0.5,
        u_mu,
        u_mu_sun,
        u_turbidity
    ); // Mie scattering, sunlight
    vec4 uv_mc = vec4(
        u_nu_moon * 0.5,
        u_mu,
        u_mu_moon,
        u_turbidity
    ); // Rayleigh + multiple scattering, moonlight
    vec4 uv_mm = vec4(
        u_nu_moon * 0.5 + 0.5,
        u_mu,
        u_mu_moon,
        u_turbidity
    ); // Mie scattering, moonlight

    vec3 scattering_sc = texture_4d(ATMOSPHERE_SCATTERING_LUT, uv_sc, scattering_res).rgb;
    vec3 scattering_sm = texture_4d(ATMOSPHERE_SCATTERING_LUT, uv_sm, scattering_res).rgb;
    vec3 scattering_mc = texture_4d(ATMOSPHERE_SCATTERING_LUT, uv_mc, scattering_res).rgb;
    vec3 scattering_mm = texture_4d(ATMOSPHERE_SCATTERING_LUT, uv_mm, scattering_res).rgb;

    vec3 mie_phase_sun = atmosphere_mie_phase_sun(nu_sun);
    vec3 mie_phase_moon = atmosphere_mie_phase_moon(nu_moon);

    vec3 atmosphere
        = (scattering_sc + scattering_sm * mie_phase_sun) * sun_color
        + (scattering_mc + scattering_mm * mie_phase_moon) * moon_color;

    return atmosphere_post_processing(atmosphere, mu, nu_sun);
}
#else
vec3 atmosphere_scattering(vec3 ray_dir, vec3 light_dir) { return vec3(0.0); }
#endif

#if defined ATMOSPHERE_TRANSMITTANCE_LUT || defined ATMOSPHERE_IRRADIANCE_LUT
vec2 atmosphere_transmittance_uv(float mu, float r) {
    // Distance to the atmosphere outer limit for a horizontal ray at ground
    // level
    const float H
        = sqrt(max(atmosphere_outer_radius_sq - atmosphere_inner_radius_sq, 0));

    // Distance to the horizon
    float rho = sqrt(max0(r * r - atmosphere_inner_radius_sq));

    // Distance to the atmosphere upper limit and its minimum and maximum values
    // over all mu
    float d = intersect_sphere(mu, r, atmosphere_outer_radius).y;
    float d_min = atmosphere_outer_radius - r;
    float d_max = rho + H;

    float u_mu = get_uv_from_unit_range(
        (d - d_min) / (d_max - d_min),
        transmittance_res.x
    );
    float u_r = get_uv_from_unit_range(rho / H, transmittance_res.y);

    return vec2(u_mu, u_r);
}
#endif

#if defined ATMOSPHERE_TRANSMITTANCE_LUT
vec3 atmosphere_transmittance(float mu, float r) {
    if (intersect_sphere(mu, r, planet_radius).x >= 0.0) {
        return vec3(0.0);
    }

    vec2 uv = atmosphere_transmittance_uv(mu, r);
    return texture(ATMOSPHERE_TRANSMITTANCE_LUT, uv).rgb;
}
#else
// Source: http://www.thetenthplanet.de/archives/4519
float chapman_function_approx(float x, float cos_theta) {
    float c = sqrt(half_pi * x);

    if (cos_theta >= 0.0) { // => theta <= 90 deg
        return c / ((c - 1.0) * cos_theta + 1.0);
    } else {
        float sin_theta = sqrt(clamp01(1.0 - sqr(cos_theta)));
        return c / ((c - 1.0) * cos_theta - 1.0)
            + 2.0 * c * exp(x - x * sin_theta) * sqrt(sin_theta);
    }
}

vec3 atmosphere_transmittance(float mu, float r) {
    if (intersect_sphere(mu, max(r, planet_radius + 10.0), planet_radius).x
        >= 0.0) {
        return vec3(0.0);
    }

    // Rayleigh and mie density at r
    const vec2 rcp_scale_heights = rcp(air_scale_heights);
    const vec2 scaled_planet_radius = planet_radius * rcp_scale_heights;
    vec2 density = exp(r * -rcp_scale_heights + scaled_planet_radius);

    // Estimate airmass along ray using chapman function approximation
    vec2 airmass = air_scale_heights * density;
    airmass.x *= chapman_function_approx(r * rcp_scale_heights.x, mu);
    airmass.y *= chapman_function_approx(r * rcp_scale_heights.y, mu);

    // Approximate ozone density as rayleigh density
    return clamp01(exp(-air_extinction_coefficients * airmass.xyx));
}
#endif

vec3 atmosphere_transmittance(vec3 ray_origin, vec3 ray_dir) {
    float r_sq = dot(ray_origin, ray_origin);
    float rcp_r = inversesqrt(r_sq);
    float mu = dot(ray_origin, ray_dir) * rcp_r;
    float r = r_sq * rcp_r;

    return atmosphere_transmittance(mu, r);
}

#endif // INCLUDE_SKY_ATMOSPHERE
