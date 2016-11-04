//
//  Defines.h
//  Synopsis
//
//  Created by vade on 8/31/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#ifndef Defines_h
#define Defines_h

#define USE_OPENCL 0
#define USE_CIEDE2000 0

#if USE_OPENCL
#define matType cv::UMat
#else
#define matType cv::Mat
#endif



#endif /* Defines_h */
