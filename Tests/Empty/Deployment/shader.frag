#version 330
#ifdef GL_ARB_shading_language_420pack
#extension GL_ARB_shading_language_420pack : require
#endif

out vec4 frag;

void main()
{
    frag = vec4(1.0, 0.0, 0.0, 1.0);
}

