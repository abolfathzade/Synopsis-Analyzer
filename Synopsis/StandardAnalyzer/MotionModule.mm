//
//  MotionModule.m
//  Synopsis
//
//  Created by vade on 11/10/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#include "opencv2/imgproc/imgproc.hpp"
#include "opencv2/video/tracking.hpp"
#import "MotionModule.h"

#define OPTICAL_FLOW 1

@interface MotionModule ()
{
    std::vector<cv::Point2f> frameFeatures[2];
    CGPoint summedFullMotionVector;
    CGPoint summedFrameMotionVector;
}
@end

@implementation MotionModule

- (instancetype) initWithQualityHint:(SynopsisAnalysisQualityHint)qualityHint
{
    self = [super initWithQualityHint:qualityHint];
    {
        summedFullMotionVector = CGPointZero;
        summedFrameMotionVector = CGPointZero;
    }
    return self;
}

- (NSString*) moduleName
{
    return @"Motion";
}

- (FrameCacheFormat) currentFrameFormat
{
    return FrameCacheFormatGray8;
}

- (FrameCacheFormat) previousFrameFormat
{
    return FrameCacheFormatGray8;
}

- (NSDictionary*) analyzedMetadataForCurrentFrame:(matType)frame previousFrame:(matType)lastFrame
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];

#if OPTICAL_FLOW
    [metadata addEntriesFromDictionary:[self detectFeaturesFlow:frame previousImage:lastFrame]];
#else

    [metadata addEntriesFromDictionary:[self detectFeaturesORBCVMat:frame]];
    [metadata addEntriesFromDictionary:[self detectMotionInCVMatAVG:frame lastImage:lastFrame]];
#endif
    return metadata;
}

- (NSDictionary*) finaledAnalysisMetadata
{
    return nil;
}

- (NSDictionary*) detectFeaturesFlow:(matType)current previousImage:(matType) previous
{
    // Empty mat - will be zeros
    cv::Mat flow;
    
    if(!previous.empty())
        cv::calcOpticalFlowFarneback(previous, current, flow, 0.5, 3, 15, 3, 5, 1.2, 0);
    
    // Avg entire flow field
    cv::Scalar avgMotion = cv::mean(flow);
    
    float xMotion = avgMotion[0] / current.size().width;
    float yMotion = -avgMotion[1] / current.size().height;
    
    float avgVectorMagnitude = sqrtf(  (xMotion * xMotion)
                                     + (yMotion * yMotion)
                                     );
    
    // Add Features to metadata
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    metadata[@"MotionVector"] = @[@(xMotion), @(yMotion)];
    metadata[@"Motion"] = @(avgVectorMagnitude);
    
    
    return metadata;
}

@end
