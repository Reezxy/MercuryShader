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
// fBm — 6 octaves, lacunarity 2.0, gain 0.5
// ------------------------------------------------------------

static float fbm(float2 p) {
    float value     = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < 6; i++) {
        value     += amplitude * valueNoise(p * frequency);
        frequency *= 2.0;   // lacunarity
        amplitude *= 0.5;   // gain
    }
    return value;
}

// ------------------------------------------------------------
// UV distortion animated by time
// ------------------------------------------------------------

static float2 distort(float2 uv, float t) {
    float2 q = float2(
        fbm(uv + float2(0.0, 0.0) + 0.1 * t),
        fbm(uv + float2(5.2, 1.3) + 0.1 * t)
    );
    float2 r = float2(
        fbm(uv + 4.0 * q + float2(1.7, 9.2) + 0.15 * t),
        fbm(uv + 4.0 * q + float2(8.3, 2.8) + 0.15 * t)
    );
    return uv + 0.25 * r;
}

// ------------------------------------------------------------
// Fake surface normal via finite differences on fBm
// ------------------------------------------------------------

static float3 surfaceNormal(float2 uv, float t) {
    const float eps = 0.002;
    float2 duv = distort(uv, t);
    float hC  = fbm(duv);
    float hDx = fbm(distort(uv + float2(eps, 0.0), t));
    float hDy = fbm(distort(uv + float2(0.0, eps), t));
    float3 n = normalize(float3(hC - hDx, hC - hDy, 0.015));
    return n;
}

// ------------------------------------------------------------
// Vertex shader — fullscreen quad from vertex_id, no VBO needed
// ------------------------------------------------------------

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexShader(uint vid [[vertex_id]]) {
    // Two triangles forming a fullscreen quad
    const float2 positions[6] = {
        {-1.0,  1.0}, {-1.0, -1.0}, { 1.0, -1.0},
        {-1.0,  1.0}, { 1.0, -1.0}, { 1.0,  1.0}
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    // Remap NDC [-1,1] to UV [0,1]; flip Y so top-left is (0,0)
    out.uv = positions[vid] * float2(0.5, -0.5) + 0.5;
    return out;
}

// ------------------------------------------------------------
// Fragment shader
// ------------------------------------------------------------

fragment float4 fragmentShader(
    VertexOut      in       [[stage_in]],
    constant Uniforms& u    [[buffer(0)]],
    texture2d<float> envMap [[texture(0)]]
) {
    constexpr sampler s(address::repeat, filter::linear);

    float2 uv = in.uv;
    // Correct for aspect ratio so the noise is isotropic
    float aspect = u.resolution.x / u.resolution.y;
    uv.x *= aspect;

    // 1. Distort UVs
    float2 dUV = distort(uv, u.time);

    // 2. Fake surface normal
    float3 N = surfaceNormal(uv, u.time);

    // 3. View direction (fixed for a flat 2D surface)
    float3 V = float3(0.0, 0.0, 1.0);

    // 4. Fresnel-Schlick approximation
    float fresnel = pow(1.0 - saturate(dot(V, N)), 3.0);

    // 5. Reflection direction
    float3 R = reflect(-V, N);
    // Project reflected direction onto UV for environment lookup
    float2 envUV = R.xy * 0.5 + 0.5;
    float4 envSample = envMap.sample(s, envUV);
    float3 envColor = envSample.rgb;

    // 6. Specular highlight
    float spec = pow(max(dot(R, V), 0.0), 64.0);

    // 7. Base silver colour
    float3 baseColor = float3(0.55, 0.55, 0.58);

    // Final composite
    float3 color = mix(baseColor, envColor, fresnel) + spec;

    return float4(color, 1.0);
}
