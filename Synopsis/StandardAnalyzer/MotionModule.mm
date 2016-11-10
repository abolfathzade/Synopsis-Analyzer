//
//  MotionModule.m
//  Synopsis
//
//  Created by vade on 11/10/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#import "MotionModule.h"

#define OPTICAL_FLOW 0

@interface MotionModule ()
{
#if OPTICAL_FLOW
    std::vector<cv::Point> lastFrameFeatures;
    std::vector<cv::Point> currentFrameFeatures;

#else
    cv::Ptr<cv::ORB> detector;
#endif
}
@end

@implementation MotionModule

- (instancetype) initWithQualityHint:(SynopsisAnalysisQualityHint)qualityHint
{
    self = [super initWithQualityHint:qualityHint];
    {
#if OPTICAL_FLOW
#else
   
        // TODO: Adjust based on Quality.
        // Default parameters of ORB
        int nfeatures=100;
        float scaleFactor=1.2f;
        int nlevels=8;
        int edgeThreshold=20; // Changed default (31);
        int firstLevel=0;
        int WTA_K=2;
        int scoreType=cv::ORB::HARRIS_SCORE;
        int patchSize=31;
        int fastThreshold=20;
        
        detector = cv::ORB::create(nfeatures,
                                   scaleFactor,
                                   nlevels,
                                   edgeThreshold,
                                   firstLevel,
                                   WTA_K,
                                   scoreType,
                                   patchSize,
                                   fastThreshold );
#endif
    }
    return self;
}

- (void) dealloc
{
#if OPTICAL_FLOW
#else
    detector.release();
#endif
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

#pragma mark - Optical Flow

#if OPTICAL_FLOW

- (NSDictionary*) detectFeaturesFlow:(matType)image
{
    if(lastFrameFeatures.empty())
    {
        
        cv::goodFeaturesToTrack(image, // the image
                                currentFrameFeatures,   // the output detected features
                                100,  // the maximum number of features
                                8,     // quality level
                                5     // min distance between two features
                                );
        
    }
    
    if(!currentFrameFeatures.empty() && !lastFrameFeatures.empty() )
    {
        
    }
    
    
    // Switch up our last frame
}

#pragma mark - Old

#else

- (NSDictionary*) detectFeaturesORBCVMat:(matType)image
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    std::vector<cv::KeyPoint> keypoints;
    detector->detect(image, keypoints, cv::noArray());
    
    NSMutableArray* keyPointsArray = [NSMutableArray new];
    
    for(std::vector<cv::KeyPoint>::iterator keyPoint = keypoints.begin(); keyPoint != keypoints.end(); keyPoint++)
    {
        CGPoint point = CGPointZero;
        {
            point = CGPointMake((float)keyPoint->pt.x / (float)image.size().width,
                                (float)keyPoint->pt.y / (float)image.size().height);
        }
        
        [keyPointsArray addObject:@[ @(point.x), @(point.y)]];
    }
    
    // Add Features to metadata
    metadata[@"Features"] = keyPointsArray;
    
    return metadata;
}

- (NSDictionary*) detectFeaturesFLowCVMat:(matType)image
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    cv::Mat corners;
    cv::goodFeaturesToTrack(image, corners, 200, 1.0, 0.1);
    
    
    for(int i = 0; i < corners.rows; i++)
    {
        cv::Vec2f corner = corners.at<cv::Vec2f>(i, 0);
        
    }
    
    // Add Features to metadata
    //    metadata[@"Features"] = keyPointsArray;
    
    return metadata;
}


#pragma mark - Frame Difference Motion

- (NSDictionary*) detectMotionInCVMatAVG:(matType)image lastImage:(matType)lastImage
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // Can we do frame differencing - note all these tests should pass because we got it last time when the sample was current
    // otherwise it wouldnt be set as last.
    if(!lastImage.empty())
    {
        matType diff;
        cv::subtract(image, lastImage, diff);
        
        // Average the difference:
        cv::Scalar avgMotion = cv::mean(diff);
        
        // Normalize to float
        metadata[@"Motion"] = @(avgMotion.val[0] / 255.0);
    }
    else {
        metadata[@"Motion"] = @(0);
    }
    
    return metadata;
}
#endif


@end
