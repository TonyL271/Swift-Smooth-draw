#include <metal_stdlib>
using namespace metal;


// Vertex shader output requires a position attribute
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// ---------------------- Phase 1 (offscreen Render) ---------------------------------------------------
// -- Copy previous frame + change draw changes


struct offScreenVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]]; // Special built-in attribute
};

vertex offScreenVertexOut vertex_stroke(
    uint vid [[vertex_id]],
    const device float2* pts [[buffer(0)]]
) {
    offScreenVertexOut out;
    out.position = float4(pts[vid], 0, 1);
    out.pointSize = 30.0;
    return out;
}

fragment float4 fragment_stroke(offScreenVertexOut in [[stage_in]]) {
    return float4(1, 0, 0, 1); // red stroke
}



// ---------------------- Phase 2 (Render using offScreen texture) ---------------------------------------------------

struct QuadVertex {
    float2 pos;
    float2 uv;
};

vertex VertexOut vertex_passthrough(
    uint vid [[vertex_id]],
    const device float4* verts [[buffer(0)]]
) {
    QuadVertex qv;
    qv.pos = verts[vid].xy;
    qv.uv = verts[vid].zw;
    
    VertexOut out;
    out.position = float4(qv.pos, 0.0, 1.0);
    out.uv = qv.uv;
    return out;
}

fragment float4 fragment_texture(
    VertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(address::clamp_to_edge);
    return tex.sample(s, in.uv);
}

