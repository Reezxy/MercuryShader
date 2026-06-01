#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// ------------------------------------------------------------
// Hash & value noise
// ------------------------------------------------------------

static float hash(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i + float2(0.0, 0.0));
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ------------------------------------------------------------
// fBm — 4 octaves (was 6; sufficient detail, ~33 % cheaper)
// ------------------------------------------------------------

static float fbm(float2 p) {
    float value     = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 4; i++) {
        value     += amplitude * valueNoise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// ------------------------------------------------------------
// UV distortion — single-warp (was double; 2 fbm calls vs 4)
// ------------------------------------------------------------

static float2 distort(float2 uv, float t) {
    float2 r = float2(
        fbm(uv + float2(0.00, 0.00) + 0.10 * t),
        fbm(uv + float2(5.20, 1.30) + 0.10 * t)
    );
    return uv + 0.35 * r;
}

// ------------------------------------------------------------
// Vertex shader — fullscreen quad from vertex_id, no VBO needed
// ------------------------------------------------------------

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexShader(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        {-1.0,  1.0}, {-1.0, -1.0}, { 1.0, -1.0},
        {-1.0,  1.0}, { 1.0, -1.0}, { 1.0,  1.0}
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * float2(0.5, -0.5) + 0.5;
    return out;
}

// ------------------------------------------------------------
// Fragment shader
// ------------------------------------------------------------

fragment float4 fragmentShader(
    VertexOut        in     [[stage_in]],
    constant Uniforms& u    [[buffer(0)]],
    texture2d<float> envMap [[texture(0)]]
) {
    constexpr sampler s(address::repeat, filter::linear);

    float2 uv = in.uv;
    uv.x *= u.resolution.x / u.resolution.y;   // aspect-correct noise

    // 1. Distort UVs — computed ONCE and reused everywhere below.
    //    Old code recomputed distort() 3 more times inside surfaceNormal;
    //    finite-differencing dUV directly avoids that entirely.
    float2 dUV = distort(uv, u.time);           // 2 fbm calls

    // 2. Surface normal via finite differences directly on distorted coords
    //    Cost: 3 fbm calls (vs 12+ before)
    const float eps = 0.004;
    float hC  = fbm(dUV);
    float hDx = fbm(dUV + float2(eps, 0.0));
    float hDy = fbm(dUV + float2(0.0, eps));
    float3 N  = normalize(float3(hC - hDx, hC - hDy, 0.02));

    // 3. View direction (flat fullscreen surface)
    float3 V = float3(0.0, 0.0, 1.0);

    // 4. Fresnel-Schlick
    float fresnel = pow(1.0 - saturate(dot(V, N)), 3.0);

    // 5. Reflection + environment map
    float3 R       = reflect(-V, N);
    float2 envUV   = R.xy * 0.5 + 0.5;
    float3 envColor = envMap.sample(s, envUV).rgb;

    // 6. Specular highlight
    float spec = pow(max(dot(R, V), 0.0), 64.0);

    // 7. Base silver colour
    float3 baseColor = float3(0.55, 0.55, 0.58);

    // Final composite
    float3 color = mix(baseColor, envColor, fresnel) + spec;

    return float4(color, 1.0);
}
