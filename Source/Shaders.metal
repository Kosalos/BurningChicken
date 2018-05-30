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
    
    float avg = 0;
    float lastAdded = 0;
    float count = 0;

    for(iter = 0;iter < 256;++iter) {
        zx2 = zx * zx;
        zy2 = zy * zy;
        
        if(iter >= control.skip) {
            count += 1;
            lastAdded = 0.5 + 0.5 * sin(control.stripeDensity * atan2(zy2, zx2));
            avg += lastAdded;
        }
        
        if(zx2 + zy2 > 4.0) break;
        
        zx0 = zx2 - zy2 + x;
        zy = 2.0 * zx * zy + y;
        
        if(control.chickenFlag && zy < 0) zy = -zy;        // chicken. remove this for Mandelbrot
        
        zx = zx0;
    }
    
    float3 icolor = float3();

    if(control.coloringFlag) {
        if(count > 1) {
            float prevAvg = (avg - lastAdded) / (count - 1.0);
            avg = avg / count;
            
            float frac = 1.0 + (log2(log(control.escapeRadius2) / log(zx2 + zy2)));
            float mix = frac * avg + (1.0 - frac) * prevAvg;
        
            if(iter < 256) {
                float co = mix * pow(10.0,control.multiplier);
                co = clamp(co,0.0,10000.0) * 6.2831;
                icolor.x = 0.5 + 0.5 * cos(co + control.R);
                icolor.y = 0.5 + 0.5 * cos(co + control.G);
                icolor.z = 0.5 + 0.5 * cos(co + control.B);
            }
        }
    }
    else {
        iter *= 2;
        if(iter > 255) iter = 255;
        icolor = color[iter];
    }
    
    outTexture.write(float4(icolor,1),p);
    
}
