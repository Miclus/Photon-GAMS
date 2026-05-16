#ifndef INCLUDE_TONEMAPPING_OPENDT_UTILS_GAMUT_CONVERT
#define INCLUDE_TONEMAPPING_OPENDT_UTILS_GAMUT_CONVERT

struct chr {
    vec2 r;
    vec2 g;
    vec2 b;
    vec2 w;
};

// set diagonal row of 3x3 matrix m to vec3 v
mat3 diag(mat3 m, vec3 v) {
    m[0][0] = v.x;
    m[1][1] = v.y;
    m[2][2] = v.z;
    return m;
}

/* Calculate the Normalized Primaries Matrix for the specified chromaticities
      Adapted from RP 177:1993
      SMPTE Recommended Practice - Derivation of Basic Television Color
   Equations http://doi.org/10.5594/S9781614821915
      https://mega.nz/file/frAnCIYK#CNRW5Q99G-w_QZtv5ey_0AkRWNrQVh7bM70kVwv42NQ
*/
mat3 npm(chr p) {
    mat3 P = mat3(0.0);
    P[0] = vec3(p.r.x, p.r.y, 1.0f - p.r.x - p.r.y);
    P[1] = vec3(p.g.x, p.g.y, 1.0f - p.g.x - p.g.y);
    P[2] = vec3(p.b.x, p.b.y, 1.0f - p.b.x - p.b.y);
    P = transpose(P);
    vec3 W = vec3(p.w.x, p.w.y, 1.0f - p.w.x - p.w.y);
    W = vec3(W.x / W.y, 1.0f, W.z / W.y);
    vec3 C = vdot(inv(P), W);
    mat3 M = diag(mat3(0.0), C);
    return P * M;
}

// Convert xy chromaticity coordinate to XYZ tristimulus with Y=1.0
vec3 xy_to_XYZ(vec2 xy) {
    return vec3(xy.x / xy.y, 1.0, (1.0 - xy.x - xy.y) / xy.y);
}

/* Calculate a von Kries style chromatic adaptation matrix
    given xy chromaticities for source white (ws) and destination white (wd)
      Source: Mark D. Fairchild - 2013 - Color Appearance Models Third Edition
   p. 181-186 Source: Bruce Lindbloom - Chromatic Adaptation -
   http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
*/
mat3 cat(vec2 ws, vec2 wd, int method) {
    if (ws.x == wd.x && ws.y == wd.y) {
        return mat3(1.0); // Whitepoints are equal, nothing to do
    }
    mat3 mcat = mat3(1.0);
    if (method == 0) { // CAT02
        mcat = mat3(
            vec3(0.7328f, 0.4296f, -0.1624f),
            vec3(-0.7036f, 1.6975f, 0.0061f),
            vec3(0.003f, 0.0136f, 0.9834f)
        );
    } else if (method == 1) { // Bradford
        mcat = mat3(
            vec3(0.8951f, 0.2664f, -0.1614f),
            vec3(-0.7502f, 1.7135f, 0.0367f),
            vec3(0.0389f, -0.0685f, 1.0296f)
        );
    }

    vec3 sXYZ = xy_to_XYZ(ws); // source normalized XYZ
    vec2 dXYZ = xy_to_XYZ(wd); // destination normalized XYZ

    vec3 sm = dot(mcat, sXYZ); // source mult
    vec3 dm = dot(mcat, dXYZ); // destination mult

    mat3 smat = diag(mat3(0.0), vec3(dm.x / sm.x, dm.y / sm.y, dm.z / sm.z));
    mat3 nmat = matmul(inverse(mcat), smat);
    return matmul(nmat, mcat);
}

#endif // INCLUDE_TONEMAPPING_OPENDT_UTILS_GAMUT_CONVERT
