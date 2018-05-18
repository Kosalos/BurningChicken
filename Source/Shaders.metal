#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

kernel void fractalShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 constant Control &control [[buffer(0)]],
 constant float3 *color [[buffer(1)]],          // color lookup table[256]
 uint2 p [[thread_position_in_grid]])
{
    if(p.x > uint(control.xSize)) return; // screen size not evenly divisible by threadGroups
    if(p.y > uint(control.ySize)) return;

    float x = control.xmin + control.dx * float(p.x);
    float y = control.ymin + control.dy * float(p.y);

    float zx = x;
    float zy = y;
    float zx2,zy2,zx0;
    int iter;
    
    for(iter = 0;iter < 256;++iter) {
        zx2 = zx * zx;
        zy2 = zy * zy;
        if(zx2 + zy2 > 4.0) break;
        
        zx0 = zx2 - zy2 + x;
        zy = 2.0 * zx * zy + y;
        
        if(zy < 0) zy = -zy;        // chicken. remove this for Mandelbrot
        
        zx = zx0;
    }

    int cIndex = iter * 2;
    if(cIndex > 255) cIndex = 255;
    
    outTexture.write(float4(color[255 - cIndex],1),p);
}
