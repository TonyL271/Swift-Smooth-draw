#include <metal_stdlib>
using namespace metal;

// Vertex structure - must match Swift structure
struct Vertex {
    float3 position;
    float3 color;
};

struct VertexOut {
    float4 position [[position]];
    float3 color;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant Vertex* vertices [[buffer(0)]],
                              constant float& rotation [[buffer(1)]]) {
    VertexOut out;
    
    // Get current vertex
    Vertex in = vertices[vertexID];
    
    // Apply internal rotation (separate from layer animation)
    float angle = rotation;
    float x = in.position.x * cos(angle) - in.position.y * sin(angle);
    float y = in.position.x * sin(angle) + in.position.y * cos(angle);
    
    out.position = float4(x, y, in.position.z, 1.0);
    out.color = in.color;
    
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}
