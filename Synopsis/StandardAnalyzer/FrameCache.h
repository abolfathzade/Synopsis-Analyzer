//
//  FrameCache.h
//  Synopsis
//
//  Created by vade on 11/10/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

// OpenCV/OpenCL compile type config

#import "opencv.hpp"
#import "ocl.hpp"
#import "types_c.h"
#import "utility.hpp"

#import <Foundation/Foundation.h>
#import "AnalyzerPluginProtocol.h"

#import "StandardAnalyzerDefines.h"


@interface FrameCache : NSObject

- (instancetype) initWithQualityHint:(SynopsisAnalysisQualityHint)qualityHint NS_DESIGNATED_INITIALIZER;

- (void) cacheAndConvertBuffer:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow;

// Current Frame Accessors
@property (readonly) matType currentBGR_32FC3_Frame;
@property (readonly) matType currentBGR_8UC3I_Frame;
@property (readonly) matType currentGray_8UC1_Frame;
@property (readonly) matType currentPerceptual_32FC3_Frame;

// Last Frame Accessors
@property (readonly) matType lastBGR_32FC3_Frame;
@property (readonly) matType lastBGR_8UC3I_Frame;
@property (readonly) matType lastGray_8UC1_Frame;
@property (readonly) matType lastPerceptual_32FC3_Frame;

@end
