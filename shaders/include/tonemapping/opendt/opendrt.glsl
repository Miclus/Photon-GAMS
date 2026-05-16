#ifndef INCLUDE_TONEMAPPING_OPENDT_OPENDRT
#define INCLUDE_TONEMAPPING_OPENDT_OPENDRT

#include "/include/utility/color.glsl"

/*  OpenDRT -------------------------------------------------/
      v0.2.8
      Written by Jed Smith
      https://github.com/jedypod/open-display-transform

      License: GPL v3
-------------------------------------------------*/

#define Lp 100.0

/*
DEFINE_UI_PARAMS(Lp, Lp, DCTLUI_SLIDER_FLOAT, 100.0, 100.0, 1000.0, 10.0)
DEFINE_UI_PARAMS(gb, grey boost, DCTLUI_SLIDER_FLOAT, 0.12, 0.0, 1.0, 0.0)
DEFINE_UI_PARAMS(in_gamut, input gamut, DCTLUI_COMBO_BOX, 11, {i_xyz, i_ap0,
i_ap1, i_p3d65, i_rec2020, i_rec709, i_awg3, i_awg4, i_rwg, i_sgamut3,
i_sgamut3cine, i_bmdwg, i_egamut, i_davinciwg}, {XYZ, ACES 2065-1, ACEScg,
P3D65, Rec.2020, Rec.709, Arri Wide Gamut 3, Arri Wide Gamut 4, Red Wide Gamut
RGB, Sony SGamut3, Sony SGamut3Cine, Blackmagic Wide Gamut, Filmlight E - Gamut,
DaVinci Wide Gamut}) DEFINE_UI_PARAMS(display_gamut, display gamut,
DCTLUI_COMBO_BOX, 0, {Rec709, P3D65, Rec2020}, {Rec.709, P3 D65, Rec.2020})
DEFINE_UI_PARAMS(EOTF, display eotf, DCTLUI_COMBO_BOX, 2, {lin, srgb, rec1886,
dci, pq, hlg}, {Linear, 2.2 Power sRGB Display, 2.4 Power Rec .1886, 2.6 Power
DCI, ST 2084 PQ, HLG})
*/

// hypotf3 = length(vec3 x)
// #define spow(a, b) (a <= 0.0 ? a : pow(a, b))
// #define spow3(a, b) (a <= vec3(0.0) ? a : pow(a, vec3(b)))
#define spow(a, b) (sign(a) * pow(abs(a), b))
#define spow3(a, b) (sign(a) * pow(abs(a), vec3(b)))

// Input gamut conversion matrix (CAT02 chromatic adaptation to D65)
// #define in_to_xyz matrix_rec2020_to_xyz
// #define xyz_to_display matrix_xyz_to_rec2020
#define eotf EOTF_lin

const int EOTF_lin = 0;
const int EOTF_srgb = 1;
const int EOTF_rec1886 = 2;
const int EOTF_dci = 3;
const int EOTF_pq = 4;
const int EOTF_hlg = 5;

/*
// Gamut Conversion Matrices
const mat3 matrix_xyz_to_xyz = mat3(1.0);
const mat3 matrix_ap0_to_xyz = mat3(vec3(0.93863094875f, -0.00574192055f,
0.017566898852f), vec3(0.338093594922f, 0.727213902811f, -0.065307497733f),
vec3(0.000723121511f, 0.000818441849f, 1.0875161874f)); const mat3
matrix_ap1_to_xyz = mat3(vec3(0.652418717672f, 0.127179925538f,
0.170857283842f), vec3(0.268064059194f, 0.672464478993f, 0.059471461813f),
vec3(-0.00546992851f, 0.005182799977f, 1.08934487929f)); const mat3
matrix_rec709_to_xyz = mat3(vec3(0.412390917540f, 0.357584357262f,
0.180480793118f), vec3(0.212639078498f, 0.715168714523f, 0.072192311287f),
vec3(0.019330825657f, 0.119194783270f, 0.950532138348f)); const mat3
matrix_p3d65_to_xyz = mat3(vec3(0.486571133137f, 0.265667706728f,
0.198217317462f), vec3(0.228974640369f, 0.691738605499f, 0.079286918044f),
vec3(-0.000000000000f, 0.045113388449, 1.043944478035f)); const mat3
matrix_rec2020_to_xyz = mat3(vec3(0.636958122253f, 0.144616916776f,
0.168880969286f), vec3(0.262700229883f, 0.677998125553f, 0.059301715344f),
vec3(0.000000000000f, 0.028072696179, 1.060985088348f)); const mat3
matrix_arriwg3_to_xyz = mat3(vec3(0.638007619284f, 0.214703856337f,
0.097744451431f), vec3(0.291953779f, 0.823841041511f, -0.11579482051f),
vec3(0.002798279032f, -0.067034235689f, 1.15329370742f)); const mat3
matrix_arriwg4_to_xyz = mat3(vec3(0.704858320407f, 0.12976029517f,
0.115837311474f), vec3(0.254524176404f, 0.781477732712f, -0.036001909116f),
vec3(0.0f, 0.0f, 1.08905775076f)); const mat3 matrix_redwg_to_xyz =
mat3(vec3(0.735275208950f, 0.068609409034f, 0.146571278572f),
vec3(0.286694079638f, 0.842979073524f, -0.129673242569f), vec3(-0.079680845141f,
-0.347343206406, 1.516081929207f)); const mat3 matrix_sonysgamut3_to_xyz =
mat3(vec3(0.706482713192f, 0.128801049791f, 0.115172164069f),
vec3(0.270979670813f, 0.786606411221f, -0.057586082034f), vec3(-0.009677845386f,
0.004600037493f, 1.09413555865f)); const mat3 matrix_sonysgamut3cine_to_xyz =
mat3(vec3(0.599083920758f, 0.248925516115f, 0.102446490178f),
vec3(0.215075820116f, 0.885068501744f, -0.100144321859f), vec3(-0.032065849545f,
-0.027658390679f, 1.14878199098f)); const mat3 matrix_bmdwg_to_xyz =
mat3(vec3(0.606538414955f, 0.220412746072f, 0.123504832387f),
vec3(0.267992943525f, 0.832748472691f, -0.100741356611f), vec3(-0.029442556202f,
-0.086612440646, 1.205112814903f)); const mat3 matrix_egamut_to_xyz =
mat3(vec3(0.705396831036f, 0.164041340351f, 0.081017754972f),
vec3(0.280130714178f, 0.820206701756f, -0.100337378681f), vec3(-0.103781513870f,
-0.072907261550, 1.265746593475f)); const mat3 matrix_davinciwg_to_xyz =
mat3(vec3(0.700622320175f, 0.148774802685f, 0.101058728993f),
vec3(0.274118483067f, 0.873631775379f, -0.147750422359f), vec3(-0.098962903023f,
-0.137895315886, 1.325916051865f));

const mat3 matrix_xyz_to_rec709 = mat3(vec3(3.2409699419f, -1.53738317757f,
-0.498610760293f), vec3(-0.969243636281f, 1.87596750151f, 0.041555057407f),
vec3(0.055630079697f, -0.203976958889f, 1.05697151424f)); const mat3
matrix_xyz_to_p3d65 = mat3(vec3(2.49349691194f, -0.931383617919f,
-0.402710784451f), vec3(-0.829488969562f, 1.76266406032f, 0.023624685842f),
vec3(0.035845830244f, -0.076172389268f, 0.956884524008f)); const mat3
matrix_xyz_to_rec2020 = mat3(vec3(1.71665118797f, -0.355670783776f,
-0.253366281374f), vec3(-0.666684351832f, 1.61648123664f, 0.015768545814f),
vec3(0.017639857445f, -0.042770613258f, 0.942103121235f));
*/

// Apply the HLG Forward or Inverse EOTF. Implements the full ambient surround
// illumination model ITU-R Rec BT.2100-2 https://www.itu.int/rec/R-REC-BT.2100
// ITU-R Rep BT.2390-8: https://www.itu.int/pub/R-REP-BT.2390
// Perceptual Quantiser (PQ) to Hybrid Log-Gamma (HLG) Transcoding:
// https://www.bbc.co.uk/rd/sites/50335ff370b5c262af000004/assets/592eea8006d63e5e5200f90d/BBC_HDRTV_PQ_HLG_Transcode_v2.pdf
vec3 eotf_hlg(vec3 rgb, int inverse) {
    const float HLG_Lw = 1000.0;
    // const float HLG_Lb = 0.0;
    const float HLG_Ls = 5.0;
    const float h_a = 0.17883277;
    const float h_b = 1.0 - 4.0 * 0.17883277;
    const float h_c = 0.5 - h_a * log(4.0 * h_a);
    const float h_g = 1.2 * pow(1.111, log2(HLG_Lw / 1000.0f))
        * pow(0.98f, log2(max(1e-6, HLG_Ls) / 5.0));
    if (inverse == 1) {
        float Yd = 0.2627 * rgb.x + 0.6780 * rgb.y + 0.0593 * rgb.z;
        // HLG Inverse OOTF
        rgb = rgb * pow(Yd, (1.0 - h_g) / h_g);
        // HLG OETF
        rgb.x = rgb.x <= 1.0 / 12.0 ? sqrt(3.0 * rgb.x)
                                    : h_a * log(12.0 * rgb.x - h_b) + h_c;
        rgb.y = rgb.y <= 1.0 / 12.0 ? sqrt(3.0 * rgb.y)
                                    : h_a * log(12.0 * rgb.y - h_b) + h_c;
        rgb.z = rgb.z <= 1.0 / 12.0 ? sqrt(3.0 * rgb.z)
                                    : h_a * log(12.0 * rgb.z - h_b) + h_c;
    } else {
        // HLG Inverse OETF
        rgb.x = rgb.x <= 0.5 ? rgb.x * rgb.x / 3.0
                             : (exp((rgb.x - h_c) / h_a) + h_b) / 12.0;
        rgb.y = rgb.y <= 0.5 ? rgb.y * rgb.y / 3.0
                             : (exp((rgb.y - h_c) / h_a) + h_b) / 12.0;
        rgb.z = rgb.z <= 0.5 ? rgb.z * rgb.z / 3.0
                             : (exp((rgb.z - h_c) / h_a) + h_b) / 12.0;
        // HLG OOTF
        float Ys = 0.2627 * rgb.x + 0.6780 * rgb.y + 0.0593 * rgb.z;
        rgb = rgb * pow(Ys, h_g - 1.0f);
    }
    return rgb;
}

/* Apply the ST-2084 PQ Forward or Inverse EOTF
      ITU-R Rec BT.2100-2 https://www.itu.int/rec/R-REC-BT.2100
      ITU-R Rep BT.2390-9 https://www.itu.int/pub/R-REP-BT.2390
      Note: in the spec there is a normalization for peak display luminance.
      For this function we assume the input is already normalized such that 1.0
   = 10,000 nits
  */
vec3 eotf_pq(vec3 rgb, int inverse) {
    // const float Lp = 1.0f;
    const float m1 = 2610.0f / 16384.0f;
    const float m2 = 2523.0f / 32.0f;
    const float c1 = 107.0f / 128.0f;
    const float c2 = 2413.0f / 128.0f;
    const float c3 = 2392.0f / 128.0f;

    if (inverse == 1) {
        // rgb /= Lp;
        rgb = spow3(rgb, m1);
        rgb = spow3((c1 + c2 * rgb) / (1.0f + c3 * rgb), m2);
    } else {
        rgb = spow3(rgb, 1.0f / m2);
        rgb = spow3((rgb - c1) / (c2 - c3 * rgb), 1.0f / m1);
        // rgb *= Lp;
    }
    return rgb;
}

vec3 narrow_hue_angles(vec3 v) {
    return vec3(
        min(2.0, max(0.0, v.x - (v.y + v.z))),
        min(2.0, max(0.0, v.y - (v.x + v.z))),
        min(2.0, max(0.0, v.z - (v.x + v.y)))
    );
}

float tonescale(float x, float m, float s, float c, int invert) {
    if (invert == 0) {
        return spow(m * x / (x + s), c);
    } else {
        float ip = 1.0 / c;
        return spow(s * x, ip) / (m - spow(x, ip));
    }
}

float flare(float x, float fl, int invert) {
    if (invert == 0) {
        return spow(x, 2.0) / (x + fl);
    } else {
        return (x + sqrt(x * (4.0 * fl + x))) / 2.0;
    }
}

// https://www.desmos.com/calculator/gfubm2kvlu
float powerp(float x, float p, float m) {
    float y = x <= 0.0f ? x : x * spow(spow(x / m, 1.0 / p) + 1.0, -p);
    return y;
}

// https://www.desmos.com/calculator/jrff9lrztn
float powerptoe(float x, float p, float m, float t0) {
    float y = x > t0
        ? x
        : (x - t0) * spow(spow((t0 - x) / (t0 - m), 1.0 / p) + 1.0, -p) + t0;
    return y;
}

vec3 opendrtransform(vec3 rgb) {
    // **************************************************
    // Parameter Setup
    // --------------------------------------------------

    // Grey Boost
    float gb = OPENDRT_GRAY_BOOST; // 0.12

    // Dechroma
    float dch = OPENDRT_DECHROMA; // 0.4

    // Chroma contrast
    float chc_p = OPENDRT_CHROMA_CONTRAST; // 1.2 // amount of contrast
    float chc_m = OPENDRT_CONRTAST_PIVOT; // 0.5 // pivot of contrast curve

    // Tonescale parameters
    float c = OPENDRT_CONTRAST; // 1.1 // contrast
    float fl = OPENDRT_FLARE; // 0.01 // flare/glare compensation

    // Weights: controls the "vibrancy" of each channel, and influences all
    // other aspects of the display-rendering.
    vec3 weights = vec3(
        OPENDRT_WEIGHT_RED,
        OPENDRT_WEIGHT_GREEN,
        OPENDRT_WEIGHT_BLUE
    ); // 0.25 0.45 0.3

    // Hue Shift RGB controls
    vec3 hs = vec3(
        OPENDRT_HS_RED,
        OPENDRT_HS_GREEN,
        OPENDRT_HS_BLUE
    ); // 0.3 -0.1 -0.5

    /* Display Scale ---------------*
          Remap peak white in display linear depending on the selected inverse
       EOTF. In our tonescale model, 1.0 is 100 nits, and as we scale up peak
       display luminance (Lp), we multiply up by the same amount. So if
       Lp=1,000, peak output of the tonescale model will be 10.0.

          So in ST2084 PQ, 1.0 is 10,000 nits, so we need to divide by 100 to
       fit out output into the container.

          Similarly in HLG, 1.0 is 1,000 nits, so we need to divide by 10.

          If we are in an SDR mode, instead we just scale the peak so it hits
       display 1.0.
      */
    const float ds
        = eotf == 4 ? Lp / 10000.0f : (eotf == 5 ? Lp / 1000.0f : 1.0f);

    /* Tonescale Parameters
          ----------------------
        For the tonescale compression function, we use one inspired by the
       wisdom shared by Daniele Siragusano on the tonescale thread on
       acescentral:
       https://community.acescentral.com/t/output-transform-tone-scale/3498/224

        This is a variation which puts the power function _after_ the
       display-linear scale, which allows a simpler and exact solution for the
       intersection constraints. The resulting function is pretty much identical
       to Daniele's but simpler. Here is a desmos graph with the math.
       https://www.desmos.com/calculator/hglnae2ame

        And for more info on the derivation, see the "Michaelis-Menten
       Constrained" Tonescale Function here:
        https://colab.research.google.com/drive/1aEjQDPlPveWPvhNoEfK4vGH5Tet8y1EB#scrollTo=Fb_8dwycyhlQ

        For the user parameter space, we include the following creative
       controls:
        - Lp: display peak luminance. This sets the display device peak
       luminance and allows rendering for HDR.
        - contrast: This is a pivoted power function applied after the
       hyperbolic compress function, which keeps middle grey and peak white the
       same but increases contrast in between.
        - flare: Applies a parabolic toe compression function after the
       hyperbolic compression function. This compresses values near zero without
       clipping. Used for flare or glare compensation.
        - gb: Grey Boost. This parameter controls how many stops to boost middle
       grey per stop of peak luminance increase.

        Notes on the other non user-facing parameters:
        - (px, py): This is the peak luminance intersection constraint for the
       compression function. px is the input scene-linear x-intersection
       constraint. That is, the scene-linear input value which is mapped to py
       through the compression function. By default this is set to 128 at
       Lp=100, and 256 at Lp=1000. Here is the regression calculation using a
       logarithmic function to match:
       https://www.desmos.com/calculator/chdqwettsj
        - (gx, gy): This is the middle grey intersection constraint for the
       compression function. Scene-linear input value gx is mapped to
       display-linear output gy through the function. Why is gy set to 0.11696
       at Lp=100? This matches the position of middle grey through the Rec709
       system. We use this value for consistency with the Arri and TCAM Rec.1886
       display rendering transforms.
      */

    // input scene-linear peak x intercept
    float px = 256.0 * log(Lp) / log(100.0) - 128.0f;
    // output display-linear peak y intercept
    float py = Lp / 100.0f;
    // input scene-linear middle grey x intercept
    float gx = 0.18f;
    // output display-linear middle grey y intercept
    float gy = 11.696f / 100.0f * (1.0f + gb * log(py) / log(2.0f));
    // s0 and s are input x scale for middle grey intersection constraint
    // m0 and m are output y scale for peak white intersection constraint
    float s0 = flare(gy, fl, 1);
    float m0 = flare(py, fl, 1);
    float ip = 1.0f / c;
    float s = (px * gx * (pow(m0, ip) - pow(s0, ip)))
        / (px * pow(s0, ip) - gx * pow(m0, ip));
    float m = pow(m0, ip) * (s + px) / px;

    /* Rendering Code ------------------------------------------ */

    // Convert into display gamut
    /*rgb = rgb * in_to_xyz;
    rgb = rgb * xyz_to_display;*/

    /* Take the the weighted sum of RGB. The weights
          scale the vector of each color channel, controlling the "vibrancy".
          We use this as a vector norm for separating color and intensity.
      */
    weights *= rgb; // multiply rgb by weights
    float lum = max(1e-8f, weights.x + weights.y + weights.z); // take the norm

    // RGB Ratios
    vec3 rats = sdiv(rgb, lum);

    // Apply tonescale function to lum
    float ts;
    ts = tonescale(lum, m, s, c, 0);
    ts = flare(ts, fl, 0);

    // Normalize so peak luminance is at 1.0
    ts *= 100.0f / Lp;

    // Clamp ts to display peak
    ts = min(1.0f, ts);

    /* Gamut Compress ------------------------------------------ *
        Most of our data is now inside of the display gamut cube, but there may
       still be some gradient disruptions due to highly chromatic colors going
       outside of the display cube on the lower end and then being clipped
        whether implicitly or explicitly. To combat this, our last step is to do
       a soft clip or gamut compression. In RGB Ratios, 0,0,0 is the gamut
       boundary, and anything outside of gamut will have one or more negative
        components. So to compress the gamut we use lift these negative values
       and compress them into a small range near 0. We use the "PowerP"
       hyperbolic compression function but it could just as well be anything.
      */
    rats.x = powerptoe(rats.x, 0.05f, -0.05f, 1.0f);
    rats.y = powerptoe(rats.y, 0.05f, -0.05f, 1.0f);
    rats.z = powerptoe(rats.z, 0.05f, -0.05f, 1.0f);

    /* Calculate RGB CMY hue angles from the input RGB.
        The classical way of calculating hue angle from RGB is something like
       this mx = max(r,g,b) mn = min(r,g,b) c = mx - mn hue =
       (c==0?0:r==mx?((g-b)/c+6)%6:g==mx?(b-r)/c+2:b==mx?(r-g)/c+4:0) With
       normalized chroma (distance from achromatic), being calculated like this
        chroma = (mx - mn)/mx
        chroma can also be calculated as 1 - mn/mx

        Here we split apart the calculation for hue and chroma so that we have
       access to RGB CMY individually without having to linear step extract the
       result again.

        To do this, we first calculate the "wide" hue angle:
          wide hue RGB = (RGB - mn)/mx
          wide hue CMY = (mx - RGB)/mx
        and then "narrow down" the hue angle for each with channel subtraction
       (see narrow_hue_angles() function).
      */

    float mx = max(rats.x, max(rats.y, rats.z));
    float mn = min(rats.x, min(rats.y, rats.z));

    vec3 rats_h = sdiv(rats - mn, mx);
    rats_h = narrow_hue_angles(rats_h);

    // Calculate "Chroma" (the normalized distance from achromatic).
    float rats_ch = 1.0f - sdiv(mn, mx);

    /* Chroma Value Compression ------------------------------------------ *
          RGB ratios may be greater than 1.0, which can result in
       discontinuities in highlight gradients. We compensate for this by
       normalizing the RGB Ratios so that max(r,g,b) does not exceed 1, and then
       mix the result. The factor for the mix is derived from tonescale *
       chroma, then taking only the top end of this with a compression function,
       so that we normalize only bright and saturated pixels.
      */

    // Normalization mix factor based on ccf * rgb chroma, smoothing transitions
    // between r->g hue gradients
    float chf = ts
        * max(spow(rats_h.x, 2.0f),
              max(spow(rats_h.y, 2.0f), spow(rats_h.z, 2.0f)));

    float chf_m = 0.25f;
    float chf_p = 0.65f;
    chf = 1.0f - spow(spow(chf / chf_m, 1.0f / chf_p) + 1.0f, -chf_p);

    // Max of rgb ratios
    float rats_mx = max(rats.x, max(rats.y, rats.z));

    // Normalized rgb ratios
    vec3 rats_n = sdiv(rats, rats_mx);

    // Mix based on chf
    rats = rats_n * chf + rats * (1.0f - chf);

    /* Chroma Compression ------------------------------------------ *
          Here we set up the chroma compression factor, used to lerp towards 1.0
          in RGB Ratios, thereby compressing color towards display peak.
          This factor is driven by ts, biased by a power function to control
       chroma compression amount `dch`.
      */
    // float ccf = 1.0f - pow(ts, 1.0f/dch);
    float ccf = 1.0f - (pow(ts, 1.0f / dch) * (1.0f - ts) + ts * ts);

    // Apply chroma compression to RGB Ratios
    rats = rats * ccf + 1.0f - ccf;

    /* Chroma Compression Hue Shift ------------------------------------------ *
          Since we compress chroma by lerping in a straight line towards 1.0 in
       rgb ratios, this can result in perceptual hue shifts due to the Abney
       effect. For example, pure blue compressed in a straight line towards
       achromatic appears to shift in hue towards purple.

          To combat this, and to add another important user control for image
       appearance, we add controls to curve the hue paths as they move towards
       achromatic. We include only controls for primary colors: RGB. In my
       testing, it was of limited use to control hue paths for CMY.

          To accomplish this, we use the inverse of the chroma compression
       factor multiplied by the RGB hue angles as a factor for a lerp between
       the various rgb components.

          We don't include the toe chroma compression for this hue shift. It is
       mostly important for highlights.
      */
    vec3 hsf = ccf * rats_h;

    // Apply hue shift to RGB Ratios
    vec3 rats_hs = vec3(
        rats.x + hsf.z * hs.z - hsf.y * hs.y,
        rats.y + hsf.x * hs.x - hsf.z * hs.z,
        rats.z + hsf.y * hs.y - hsf.x * hs.x
    );

    // Mix hue shifted RGB ratios by ts, so that we shift where highlights were
    // chroma compressed plus a bit.
    rats = rats_hs * ts + rats * (1.0f - ts);

    /* Chroma Contrast
          Without this step, mid-range chroma in shadows and midtones looks too
       grey and dead. This is common with chromaticity-linear view transforms.
          In order to improve skin-tone rendering and overal "vibrance" of the
       image, which we are used to seeing with per-channel style view
       transforms, we boost mid-range chroma in shadows and midtones using a
       "chroma contrast" setup.

          Basically we take classical chroma (distance from achromatic), we take
       the compressed tonescale curve, and we apply a contrast to the tonescale
       curve mixed by a parabolic center extraction of chroma, so that we do not
       boost saturation at grey (increases noise), nor do we boost saturation of
       highly saturated colors which might already be near the edge of the gamut
       volume.
      */
    float chc_f = 4.0f * rats_ch * (1.0f - rats_ch);
    float chc_sa = min(
        2.0f,
        sdiv(
            lum,
            chc_m * spow(sdiv(lum, chc_m), chc_p) * chc_f + lum * (1.0f - chc_f)
        )
    );
    float chc_L = 0.23f * rats.x + 0.69f * rats.y
        + 0.08f * rats.z; // Roughly P3 weights, doesn't matter

    // Apply mid-range chroma contrast saturation boost
    rats = chc_L * (1.0f - chc_sa) + rats * chc_sa;

    // Apply tonescale to RGB Ratios
    rgb = rats * ts;

    // Apply display scale
    rgb *= ds;

    // Clamp
    rgb = max(vec3(0.0), rgb);
    rgb = min(vec3(ds), rgb);

    // Apply inverse Display EOTF
    float eotf_p = 2.0f + eotf * 0.2f;
    if ((eotf > 0) && (eotf < 4)) {
        rgb = spow3(rgb, 1.0f / eotf_p);
    } else if (eotf == 4) {
        rgb = eotf_pq(rgb, 1);
    } else if (eotf == 5) {
        rgb = eotf_hlg(rgb, 1);
    }

    return rgb;
}

#undef Lp
#undef eotf

#undef spow
#undef spow3

#endif // INCLUDE_TONEMAPPING_OPENDT_OPENDRT
