// shader_vert_main

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct shader_vert_main_in
{
    float3 pos [[attribute(0)]];
};

struct shader_vert_main_out
{
    float4 gl_Position [[position]];
};

vertex shader_vert_main_out shader_vert_main(shader_vert_main_in in [[stage_in]], uint gl_VertexID [[vertex_id]], uint gl_InstanceID [[instance_id]])
{
    shader_vert_main_out out = {};
    out.gl_Position = float4(in.pos.x, in.pos.y, 0.5, 1.0);
    out.gl_Position.z = (out.gl_Position.z + out.gl_Position.w) * 0.5;       // Adjust clip-space for Metal
    return out;
}

