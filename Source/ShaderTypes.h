#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

struct Control {
    int version;
    int xSize,ySize;
    
    float xmin,xmax,dx;
    float ymin,ymax,dy;

    int coloringFlag;
    int chickenFlag;
    int skip;
    float stripeDensity;
    float escapeRadius2;
    float multiplier;
    float R;
    float G;
    float B;

    float future1;
    float future2;
    float future3;
    float future4;
    float future5;
};

#endif /* ShaderTypes_h */

