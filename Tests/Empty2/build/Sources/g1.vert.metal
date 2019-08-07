// g1_vert_main

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct g1_vert_main_in
{
    float3 pos [[attribute(0)]];
    float2 tex [[attribute(1)]];
};

struct g1_vert_main_out
{
    float2 texCoord [[user(locn0)]];
    float4 gl_Position [[position]];
};

vertex g1_vert_main_out g1_vert_main(g1_vert_main_in in [[stage_in]], uint gl_VertexID [[vertex_id]], uint gl_InstanceID [[instance_id]])
{
    g1_vert_main_out out = {};
    out.gl_Position = float4(in.pos.x, in.pos.y, 0.5, 1.0);
    out.texCoord = in.tex;
    out.gl_Position.z = (out.gl_Position.z + out.gl_Position.w) * 0.5;       // Adjust clip-space for Metal
    return out;
}

