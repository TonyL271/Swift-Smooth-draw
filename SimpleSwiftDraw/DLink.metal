#include <metal_stdlib>
using namespace metal;

// We'll pass positions in buffer(0) and a float4 color in buffer(1).
struct Uniforms {
    float4 color;
};

vertex float4 vertex_main(uint                  vid      [[ vertex_id ]],
                          const device float2*  verts    [[ buffer(0) ]])
{
    // Each float2 is already in clip space for a fullscreen triangle
    return float4(verts[vid], 0.0, 1.0);
}

fragment float4 fragment_main(const device Uniforms& uni [[ buffer(1) ]])
{
    return uni.color;
}
