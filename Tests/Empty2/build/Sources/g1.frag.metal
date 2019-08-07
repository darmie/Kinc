// g1_frag_main

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct g1_frag_main_in
{
    float2 texCoord [[user(locn0)]];
};

struct g1_frag_main_out
{
    float4 FragColor [[color(0)]];
};

fragment g1_frag_main_out g1_frag_main(g1_frag_main_in in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler texSmplr [[sampler(0)]])
{
    g1_frag_main_out out = {};
    out.FragColor = tex.sample(texSmplr, in.texCoord);
    return out;
}

