#ifndef INCLUDE_TONEMAPPING_OPENDT_JZDT
#define INCLUDE_TONEMAPPING_OPENDT_JZDT

/*  JzDT
      A simple display transform based on JzAzBz LMS.
      Uses a chromaticity-linear rendering, with perceptual chroma compression
      hue-path compensation using the JzAzBz perceptual color model.
      Uses a max(r,g,b) norm, and a simple tonescale based on the
      Michaelis-Menten model of enzyme kinetics, which has been shown to
      describe the response of photoreceptor cells to stimulus.
    ---------------------------------------------------------------------------
      v0.0.1
      Written by Jed Smith
      https://github.com/jedypod/open-display-transform

    -------------------------------------------------
*/

#define average 1
#define dim 2
#define dark 3

// #define in_gamut 0
#define tf 0 // in_curve
#define Lw 100.0
// JZDT_DECHROMA // Dechroma
// JZDT_SATURATION // Saturation
// #define surround average
#define invert 0 // Inverse EOTF
// JZDT_EUCLIDEAN           // Euclidean distance norm
// JZDT_PERCEPTUAL_DECHROMA // Perceptual Dechroma
// JZDT_GAMUT_COMPRESS      // Gamut Compress
#define eotf 0

// Compute "safe" power of vec3 a, reflected over the origin
#define spowf(a, b) (sign(a) * pow(abs(a), b))
#define spowf3(a, b) (sign(a) * pow(abs(a), vec3(b)))

const mat3 matrix_rec2020_to_xyz = mat3(
    vec3(0.636958122253f, 0.144616916776f, 0.168880969286f),
    vec3(0.262700229883f, 0.677998125553f, 0.059301715344f),
    vec3(0.000000000000f, 0.028072696179, 1.060985088348f)
);

const mat3 in_to_xyz = matrix_rec2020_to_xyz;
mat3 xyz_to_display = inverse(matrix_rec2020_to_xyz);
mat3 xyz_to_in = xyz_to_display;
const mat3 display_to_xyz = matrix_rec2020_to_xyz;

/* ##########################################################################
    Transfer Functions
    ---------------------------------
*/

/*vec3 eotf_hlg(vec3 rgb, int inverse) {
    // Aply the HLG Forward or Inverse EOTF. Implements the full ambient
surround illumination model
    // ITU-R Rec BT.2100-2 https://www.itu.int/rec/R-REC-BT.2100
    // ITU-R Rep BT.2390-8: https://www.itu.int/pub/R-REP-BT.2390
    // Perceptual Quantiser (PQ) to Hybrid Log-Gamma (HLG) Transcoding:
https://www.bbc.co.uk/rd/sites/50335ff370b5c262af000004/assets/592eea8006d63e5e5200f90d/BBC_HDRTV_PQ_HLG_Transcode_v2.pdf

    const float HLG_Lw = 1000.0f;
    //   const float HLG_Lb = 0.0f;
    const float HLG_Ls = 5.0f;
    const float h_a = 0.17883277f;
    const float h_b = 1.0f - 4.0f * 0.17883277f;
    const float h_c = 0.5f - h_a * log(4.0f * h_a);
    const float h_g = 1.2f * pow(1.111f, log2(HLG_Lw / 1000.0f)) * pow(0.98f,
log2(max(1e-6f, HLG_Ls) / 5.0f)); if (inverse == 1) { float Yd = 0.2627f * rgb.x
+ 0.6780f * rgb.y + 0.0593f * rgb.z;
        // HLG Inverse OOTF
        rgb = rgb * pow(Yd, (1.0f - h_g) / h_g);
        // HLG OETF
        rgb.x = rgb.x <= 1.0f / 12.0f ? sqrt(3.0f * rgb.x) : h_a * log(12.0f *
rgb.x - h_b) + h_c; rgb.y = rgb.y <= 1.0f / 12.0f ? sqrt(3.0f * rgb.y) : h_a *
log(12.0f * rgb.y - h_b) + h_c; rgb.z = rgb.z <= 1.0f / 12.0f ? sqrt(3.0f *
rgb.z) : h_a * log(12.0f * rgb.z - h_b) + h_c; } else {
        // HLG Inverse OETF
        rgb.x = rgb.x <= 0.5f ? rgb.x * rgb.x / 3.0f : (exp((rgb.x - h_c) / h_a)
+ h_b) / 12.0f; rgb.y = rgb.y <= 0.5f ? rgb.y * rgb.y / 3.0f : (exp((rgb.y -
h_c) / h_a) + h_b) / 12.0f; rgb.z = rgb.z <= 0.5f ? rgb.z * rgb.z / 3.0f :
(exp((rgb.z - h_c) / h_a) + h_b) / 12.0f;
        // HLG OOTF
        float Ys = 0.2627f * rgb.x + 0.6780f * rgb.y + 0.0593f * rgb.z;
        rgb = rgb * pow(Ys, h_g - 1.0f);
    }
    return rgb;
}*/

vec3 eotf_pq(vec3 rgb, int inverse, int jz) {
    // Apply the ST-2084 PQ Forward or Inverse EOTF
    // Normalized such that input display linear light code value 1.0 equals
    // 10,000 nits ITU-R Rec BT.2100-2 https://www.itu.int/rec/R-REC-BT.2100
    // ITU-R Rep BT.2390-9 https://www.itu.int/pub/R-REP-BT.2390

    float Lp = 1.0f; // We normalize for hdr peak display luminance elsewhere.
    const float m1 = 2610.0f / 16384.0f;
    float m2 = 2523.0f / 32.0f;
    const float c1 = 107.0f / 128.0f;
    const float c2 = 2413.0f / 128.0f;
    const float c3 = 2392.0f / 128.0f;

    // Custom values for JzAzBz colorspace
    if (jz == 1) {
        m2 *= 1.7f;
        // Lp = 10000.0f;
    }

    if (inverse == 1) {
        rgb /= Lp;
        rgb = spowf3(rgb, m1);
        // Prevent shitting of the bed when there are negatives, for JzAzBz
        // conversion // TODO: lmao what? (comment from JzDT github)
        rgb.x = sign(rgb.x)
            * pow((c1 + c2 * abs(rgb.x)) / (1.0f + c3 * abs(rgb.x)), m2);
        rgb.y = sign(rgb.y)
            * pow((c1 + c2 * abs(rgb.y)) / (1.0f + c3 * abs(rgb.y)), m2);
        rgb.z = sign(rgb.z)
            * pow((c1 + c2 * abs(rgb.z)) / (1.0f + c3 * abs(rgb.z)), m2);
    } else {
        rgb = spowf3(rgb, 1.0f / m2);
        rgb.x = sign(rgb.x)
            * pow((abs(rgb.x) - c1) / (c2 - c3 * abs(rgb.x)), 1.0f / m2) * Lp;
        rgb.y = sign(rgb.y)
            * pow((abs(rgb.y) - c1) / (c2 - c3 * abs(rgb.y)), 1.0f / m2) * Lp;
        rgb.z = sign(rgb.z)
            * pow((abs(rgb.z) - c1) / (c2 - c3 * abs(rgb.z)), 1.0f / m2) * Lp;
    }
    return rgb;
}

/* ##########################################################################
    Color Models
    ---------------------------------
*/

vec3 cartesian_to_polar(vec3 a) {
    return vec3(a.x, cartesian_to_polar(a.yz));
    // return vec3(a.x, length(vec2(a.y, a.z)), atan(a.z, a.y));
}

vec3 polar_to_cartesian(vec3 a) {
    return vec3(a.x, polar_to_cartesian(a.yz));
    // return vec3(a.x, a.y * cos(a.z), a.y * sin(a.z));
}

/*JzAzBz perceptual colorspace
    ----------------------------------
    Safdar, M., Cui, G., Kim, Y. J., & Luo, M. R. (2017).
        Perceptually uniform color space for image signals including high
   dynamic range and wide gamut. Optics Express, 25(13), 15131.
        doi:10.1364/OE.25.015131
    https://www.osapublishing.org/oe/fulltext.cfm?uri=oe-25-13-15131&id=368272
    https://observablehq.com/@jrus/jzazbz
*/

const mat3 matrix_jzazbz_xyz_to_lms = mat3(
    vec3(0.41479f, 0.579999f, 0.014648f),
    vec3(-0.20151f, 1.12065f, 0.0531008f),
    vec3(-0.0166008f, 0.2648f, 0.66848f)
);
const mat3 matrix_jzazbz_lms_p_to_izazbz = mat3(
    vec3(0.5f, 0.5f, 0.0f),
    vec3(3.524f, -4.06671f, 0.542708f),
    vec3(0.199076f, 1.0968f, -1.29588f)
);

vec3 xyz_to_jzlms(vec3 xyz) {
    vec3 lms;
    lms = vec3(
        1.15f * xyz.x - (1.15f - 1.0f) * xyz.z,
        0.66f * xyz.y - (0.66f - 1.0f) * xyz.x,
        xyz.z
    );
    lms = lms * matrix_jzazbz_xyz_to_lms;
    return lms;
}

vec3 jzlms_to_xyz(vec3 lms) {
    vec3 xyz;
    xyz = lms * inverse(matrix_jzazbz_xyz_to_lms);
    xyz = vec3(
        (xyz.x + (1.15f - 1.0f) * xyz.z) / 1.15f,
        (xyz.y + (0.66f - 1.0f) * ((xyz.x + (1.15f - 1.0f) * xyz.z) / 1.15f))
            / 0.66f,
        xyz.z
    );
    return xyz;
}

vec3 xyz_to_jzazbz(vec3 xyz, int cyl) {
    // Convert input XYZ D65 aligned tristimulus values into JzAzBz perceptual
    // colorspace, if cyl==1: output cylindrical JCh : J = luma, C = chroma, h =
    // hue in radians
    const float d = -0.56;
    const float d_0 = eps; // 1.6295499532821565e-11f;
    vec3 lms;
    lms = xyz_to_jzlms(xyz);
    lms = eotf_pq(lms, 1, 1);
    lms = lms * matrix_jzazbz_lms_p_to_izazbz;
    lms.x = lms.x * (1.0 + d) / (1.0 + d * lms.x) - d_0;

    // Convert to cylindrical
    if (cyl == 1) {
        lms = cartesian_to_polar(lms);
    }

    return lms;
}

vec3 jzazbz_to_xyz(vec3 jz, int cyl) {
    const float d = -0.56;
    const float d_0 = eps; // 1.6295499532821565e-11f;
    // Convert to cartesian
    if (cyl == 1) {
        jz = polar_to_cartesian(jz);
    }

    jz.x += d_0;
    jz.x = jz.x / (1.0 + d - d * jz.x);
    jz = jz * inverse(matrix_jzazbz_lms_p_to_izazbz);
    jz = eotf_pq(jz, 0, 1);
    jz = jzlms_to_xyz(jz);
    return jz;
}

/* ##########################################################################
    Utility Functions
    --------------------
*/

float compress_parabolic(float x, float t0, float x0, float y0) {
    /* Parabolic Compression Function
      Threshold
        Only values above threshold point (t0, t0) will be compressed.
      Intersection constraint
        The coordinate (x0, y0) specifies the compression function intersection
        constraint. The input x value x0 is compressed to the output y value y0.
      https://www.desmos.com/calculator/khowxlu6xh
    */
    float s = (y0 - t0) / sqrt(x0 - y0);
    float ox = t0 - s * s / 4.0f;
    float oy = t0 - s * sqrt(s * s / 4.0f);

    return (x < t0 ? x : s * sqrt(x - ox) + oy);
}

vec3 gamut_compress_rgb(vec3 xyz, float th, float ds, int av) {
    // Chromaticity-linear gamut compression, given threshold th and distance
    // ds. if av==1, average of rgb will be used as achromatic axis instead of
    // max of rgb

    vec3 rgb = xyz * inverse(matrix_rec2020_to_xyz);

    float mx = max(rgb.x, max(rgb.y, rgb.z));
    float mn = min(rgb.x, min(rgb.y, rgb.z));
    float ch = mx == 0.0 ? 0.0 : (mx - mn) / mx; // classic chroma
    float ch_c = compress_parabolic(ch, th, ds, 1.0);
    float f = ch == 0.0 ? 0.0 : ch_c / ch;

    // Gamut compress
    if (av == 0) {
        rgb = mx * (1.0 - f) + rgb * f;
    } else {
        float mean = (rgb.x + rgb.y + rgb.z) / 3.0;
        rgb = mean * (1.0 - f) + rgb * f;
    }

    rgb = rgb * matrix_rec2020_to_xyz;

    return rgb;
}

vec3 jzdtransform(vec3 rgb) {
    const float dch = JZDT_DECHROMA;
    const float sat = JZDT_SATURATION;
    const float surround = average;

    // Surround compensation
    float ps;
    if (surround == average) {
        ps = 0.9f;
    } else if (surround == dim) {
        ps = 0.95f;
    } else if (surround == dark) {
        ps = 1.0f;
    }

    const float ds = eotf == 4 ? Lw / 10000.0f
        : eotf == 5            ? Lw / 1000.0f
                               : 1.0f;

    // Calculate tonescale parameters
    const float c = 12.0f * pow(Lw, -0.86f) + 1.17f;
    float p = c * ps;
    const float fl = 1.0f / Lw;
    const float sx = 0.016f * pow(Lw, 0.87f) - 0.17f;
    const float sy = 1.036f + 0.00005f * Lw;

    /* Forward Display Rendering
     ----------------------------------------------------------- */

    if (invert == 0) {
        // rgb = log2lin(rgb, tf); // Assume tf = 0
        vec3 xyz = rgb * in_to_xyz;
        vec3 lms = xyz_to_jzlms(xyz);

        // Tonescale: https://www.desmos.com/calculator/ssx2a1bpsz
        float n = max(lms.x, max(lms.y, lms.z));
        n = max(1e-12f, n);

#ifdef JZDT_EUCLIDEAN
        n = sqrt(sqr(lms.x) + sqr(lms.y) + sqr(lms.z)) / sqrt(3.0);
#endif
        float ns = sy * pow(n / (n + sx), p);
        float nt = ns * ns / (ns + fl);
        float ccf = pow(sx / (n + sx), dch) * sat;
        vec3 dlms = lms * nt / n;
        dlms = nt * (1.0f - ccf) + dlms * ccf;
        xyz = jzlms_to_xyz(dlms);

#ifdef JZDT_PERCEPTUAL_DECHROMA
        vec3 jz = xyz_to_jzazbz(xyz, 1);
        /*#ifdef JZDT_GAMUT_COMPRESS
            jz.y = compress_parabolic(jz.y, 0.015f, 0.05f, 0.03f);
        #endif
        vec3 xyz_ndc = jzlms_to_xyz(lms);
        vec3 jz_ndc = xyz_to_jzazbz(xyz_ndc, 1);*/
        // jz.z = jz_ndc.z;
        xyz = jzazbz_to_xyz(jz, 1);
#endif

        rgb = xyz * xyz_to_display;
        rgb *= ds;

        rgb = clamp01(rgb);
        float eotf_p = 2.0f + eotf * 0.2f;
        if ((eotf > 0) && (eotf < 4)) {
            rgb = pow(rgb, vec3(1.0f / eotf_p));
        } else if (eotf == 4) {
            rgb = eotf_pq(rgb, 1, 0);
        } /*else if (eotf == 5) {
            rgb = eotf_hlg(rgb, 1);
        }*/
    } else {
        rgb = clamp01(rgb);
        float eotf_p = 2.0f + eotf * 0.2f;
        if ((eotf > 0) && (eotf < 4)) {
            rgb = pow(rgb, vec3(eotf_p));
        } else if (eotf == 4) {
            rgb = eotf_pq(rgb, 0, 0);
        } /*else if (eotf == 5) {
            rgb = eotf_hlg(rgb, 0);
        }*/
        rgb /= ds;
        vec3 xyz = rgb * display_to_xyz;
        vec3 lms = xyz_to_jzlms(xyz);

        // Inverse Tonescale
        float n = max(lms.x, max(lms.y, lms.z));
        n = max(1e-12f, min(0.999f, n));
        float nt = (n + sqrt(n * (4.0f * fl + n))) / 2.0f;
        float np = pow(nt / sy, 1.0f / p);
        float ns = (np / (1.0f - np)) * sx;
        float ccf
            = ns == 0.0f ? 0.0f : pow(pow(nt, 1.0f / p) / (ns / sx), dch) * sat;
        vec3 dlms = (n * (ccf - 1.0f) + lms) / ccf * ns / n;

        xyz = jzlms_to_xyz(dlms);
#ifdef JZDT_PERCEPTUAL_DECHROMA
        vec3 jz = xyz_to_jzazbz(xyz, 1);
        vec3 xyz_ndc = jzlms_to_xyz(lms);
        vec3 jz_ndc = xyz_to_jzazbz(xyz_ndc, 1);
        jz.z = jz_ndc.z;
        xyz = jzazbz_to_xyz(jz, 1);
#endif
        rgb = xyz * xyz_to_in;
        // rgb = lin2log(rgb, tf); // Assume tf = 0
    }

    return rgb;
}

#undef average
#undef dim
#undef dark
#undef tf
#undef Lw
#undef invert
#undef eotf

#endif // INCLUDE_TONEMAPPING_OPENDT_JZDT
