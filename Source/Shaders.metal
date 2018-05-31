#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

float2 complexMul(float2 v1, float2 v2) { return float2(v1.x * v2.x - v1.y * v2.y, v1.x * v2.y + v1.y * v2.x); }

kernel void fractalShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 constant Control &control [[buffer(0)]],
 constant float3 *color [[buffer(1)]],          // color lookup table[256]
 uint2 p [[thread_position_in_grid]])
{
    if(p.x > uint(control.xSize)) return; // screen size not evenly divisible by threadGroups
    if(p.y > uint(control.ySize)) return;

    float2 c = float2(control.xmin + control.dx * float(p.x), control.ymin + control.dy * float(p.y));
    int iter;
    int maxIter = 256;
    float avg = 0;
    float lastAdded = 0;
    float count = 0;
    float2 z = float2();
    float z2 = 0;

    for(iter = 0;iter < maxIter;++iter) {
        z = complexMul(z,z) + c;
        
        if(iter >= control.skip) {
            count += 1;
            lastAdded = 0.5 + 0.5 * sin(control.stripeDensity * atan2(z.y, z.x));
            avg += lastAdded;
        }

        if(control.chickenFlag && z.y < 0) { z.y = -z.y; }

        z2 = dot(z,z);
        if (z2 > control.escapeRadius2 && iter > control.skip) break;
    }
    
    float3 icolor = float3();

    if(control.coloringFlag) {
        if(count > 1) {
            float prevAvg = (avg - lastAdded) / (count - 1.0);
            avg = avg / count;
            
            float frac = 1.0 + (log2(log(control.escapeRadius2) / log(z2)));
            float mix = frac * avg + (1.0 - frac) * prevAvg;
        
            if(iter < maxIter) {
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

// ======================================================================
// ======================================================================
// ======================================================================
/*  yesterday's rendition
 
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
 */
// ======================================================================
// ======================================================================
// ======================================================================
/* frag code from fractalforums
 
#include "Progressive2D.frag"
#group Mandelbrot

// Number of iterations
uniform int Iterations; slider[10,200,5000]
uniform float R; slider[0,0,1]
uniform float G; slider[0,0.4,1]
uniform float B; slider[0,0.7,1]
uniform bool Julia; checkbox[false]
uniform float JuliaX; slider[-2,-0.6,2]
uniform float JuliaY; slider[-2,1.3,2]
vec2 c2 = vec2(JuliaX,JuliaY);

void init() {}

vec2 complexMul(vec2 a, vec2 b) {
    return vec2( a.x*b.x - a.y*b.y,a.x*b.y + a.y * b.x);
}

vec2 mapCenter = vec2(0.5,0.5);
float mapRadius =0.4;
uniform bool ShowMap; checkbox[true]
uniform float MapZoom; slider[0.01,2.1,6]

vec3 getMapColor2D(vec2 c) {
    vec2 p = (aaCoord-mapCenter)/(mapRadius);
    p*=MapZoom; p.x/=pixelSize.x/pixelSize.y;
    if (abs(p.x)<2.0*pixelSize.y*MapZoom) return vec3(0.0,0.0,0.0);
    if (abs(p.y)<2.0*pixelSize.x*MapZoom) return vec3(0.0,0.0,0.0);
    p +=vec2(JuliaX, JuliaY) ;
    vec2 z = vec2(0.0,0.0);
    int i = 0;
    for (i = 0; i < Iterations; i++) {
        z = complexMul(z,z) +p;
        if (dot(z,z)> 200.0) break;
    }
    
    if (i < Iterations) {
        float co = float( i) + 1.0 - log2(.5*log2(dot(z,z)));
        co = sqrt(co/256.0);
        return vec3( .5+.5*cos(6.2831*co),.5+.5*cos(6.2831*co),.5+.5*cos(6.2831*co) );
    } else {
        return vec3(0.0);
    }
    
}

// Skip initial iterations in coloring
uniform int Skip; slider[0,1,100]
// Scale color function
uniform float Multiplier; slider[-10,0,10]
uniform float StripeDensity; slider[-10,1,10]
// To test continous coloring
uniform float Test; slider[0,1,1]
uniform float EscapeRadius2; slider[0,1000,100000]

vec3 color(vec2 c) {
    if (ShowMap && Julia) {
        vec2 w = (aaCoord-mapCenter);
        w.y/=(pixelSize.y/pixelSize.x);
        if (length(w)<mapRadius) return getMapColor2D(c);
        if (length(w)<mapRadius+0.01) return vec3(0.0,0.0,0.0);
    }
    
    vec2 z = Julia ? c : vec2(0.0,0.0);
    int i = 0;
    float count = 0.0;
    float avg = 0.0; // our average
    float lastAdded = 0.0;
    float z2 = 0.0; // last squared length
    for ( i = 0; i < Iterations; i++) {
        z = complexMul(z,z) + (Julia ? c2 : c);
        if (i>=Skip) {
            count++;
            lastAdded = 0.5+0.5*sin(StripeDensity*atan(z.y,z.x));
            avg +=  lastAdded;
        }
        z2 = dot(z,z);
        if (z2> EscapeRadius2 && i>Skip) break;
    }
    float prevAvg = (avg -lastAdded)/(count-1.0);
    avg = avg/count;
    float frac =1.0+(log2(log(EscapeRadius2)/log(z2)));
    frac*=Test;
    float mix = frac*avg+(1.0-frac)*prevAvg;
    if (i < Iterations) {
        float co = mix*pow(10.0,Multiplier);
        co = clamp(co,0.0,10000.0);
        return vec3( .5+.5*cos(6.2831*co+R),.5+.5*cos(6.2831*co + G),.5+.5*cos(6.2831*co +B) );
    } else {
        return vec3(0.0);
    }
}

#preset Default
Center = -0.587525,0.297888
Zoom = 1.79585
Iterations = 278
R = 0
G = 0.4
B = 0.7
Julia = false
JuliaX = -0.6
JuliaY = 1.3
ShowMap = true
MapZoom = 2.1
Skip = 6
Multiplier = -0.1098
StripeDensity = 1.5384
Test = 1
EscapeRadius2 = 74468
#endpreset

#preset Julia
Center = -0.302544,-0.043626
Zoom = 4.45019
Iterations = 464
R = 0.58824
G = 0.3728
B = 0.27737
Julia = true
JuliaX = -1.26472
JuliaY = -0.05884
ShowMap = false
MapZoom = 1.74267
Skip = 4
Test = 1
EscapeRadius2 = 91489
Multiplier = 0.4424
StripeDensity = 2.5
#endpreset

#preset nice
Gamma = 2
Brightness = 1
Contrast = 1
Saturation = 1
Center = -0.1049693,0.9272831
Zoom = 4900
ToneMapping = 3
Exposure = 1
AARange = 1.5
AAExp = 6
GaussianAA = true
Iterations = 5000
R = 0
G = 0.4
B = 0.7
Julia = false
JuliaX = -0.6
JuliaY = 1.3
ShowMap = false
MapZoom = 2.1
Skip = 19
Multiplier = 0.9004909
StripeDensity = 1.699857
Test = 1
EscapeRadius2 = 100000
#endpreset

*/

























