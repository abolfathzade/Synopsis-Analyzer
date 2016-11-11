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
#if OPTICAL_FLOW
    std::vector<cv::Point2f> frameFeatures[2];
    int numFeaturesToTrack;
    CGPoint summedFullMotionVector;
    CGPoint summedFrameMotionVector;
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
        
        summedFullMotionVector = CGPointZero;
        summedFrameMotionVector = CGPointZero;
        
        switch (qualityHint) {
            case SynopsisAnalysisQualityHintLow:
                numFeaturesToTrack = 25;
                break;
            case SynopsisAnalysisQualityHintMedium:
                numFeaturesToTrack = 50;
                break;
            case SynopsisAnalysisQualityHintHigh:
                numFeaturesToTrack = 100;
                break;
            case SynopsisAnalysisQualityHintOriginal:
                numFeaturesToTrack = 200;
                break;
                
            default:
                break;
        }
        
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

#pragma mark - Optical Flow

#if OPTICAL_FLOW

BOOL hasInitialized = false;
int tryCount = 0;
- (NSDictionary*) detectFeaturesFlow:(matType)current previousImage:(matType) previous
{
    cv::TermCriteria termcrit(cv::TermCriteria::COUNT|cv::TermCriteria::EPS,20,0.03);
    std::vector<float> err;
    std::vector<uchar> status;

    if(!hasInitialized || (tryCount == 0) )
    {
        cv::goodFeaturesToTrack(current, // the image
                                frameFeatures[1],   // the output detected features
                                numFeaturesToTrack,  // the maximum number of features
                                0.01,     // quality level
                                5     // min distance between two features
                                );
        
        //cv::cornerSubPix(current, currentFrameFeatures, cv::Size(10, 10), cv::Size(-1,-1), termcrit);

    }
    
    else if( !frameFeatures[0].empty() )
    {
        cv::Size optical_flow_window = cvSize(3,3);
        cv::calcOpticalFlowPyrLK(previous,
                                 current, // 2 consecutive images
                                 frameFeatures[0], // input point positions in first im
                                 frameFeatures[1], // output point positions in the 2nd
                                 status,    // tracking success
                                 err,      // tracking error
                                 optical_flow_window,
                                 3,
                                 termcrit
                                 );
    }
    


    NSMutableArray* pointsArray = [NSMutableArray new];
    int numAccumulatedFlowPoints = 0;
    
    for(int i = 0; i < frameFeatures[0].size(); i++)
    {
        cv::Point prev = frameFeatures[0][i];
        cv::Point curr = frameFeatures[1][i];
        
        CGPoint point = CGPointZero;
        {
            point = CGPointMake((float)curr.x / (float)current.size().width,
                                1.0 - (float)curr.y / (float)current.size().height);
        }
        
        [pointsArray addObject:@[ @(point.x), @(point.y)]];
        
        // check to see we found flow for the tracking point so we can accumulate it.
        if(status.size())
        {
            if(status[i])
            {
                float diffX = prev.x - curr.x;
                float diffY = prev.y - curr.y;
                
                summedFrameMotionVector.x += diffX;
                summedFrameMotionVector.y += diffY;
                numAccumulatedFlowPoints++;
            }
        }
    }
    
    summedFrameMotionVector.x /= numAccumulatedFlowPoints;
    summedFrameMotionVector.y /= numAccumulatedFlowPoints;

    if( isnan(summedFrameMotionVector.x) || isinf(summedFrameMotionVector.x) )
        summedFrameMotionVector.x = 0;

    if( isnan(summedFrameMotionVector.y) || isinf(summedFrameMotionVector.y))
        summedFrameMotionVector.y = 0;

    float summedFrameMotionMagnitude = sqrtf( (summedFrameMotionVector.x * summedFrameMotionVector.x) + (summedFrameMotionVector.y + summedFrameMotionVector.y) );
    
    if( isnan(summedFrameMotionMagnitude) || isinf(summedFrameMotionMagnitude) )
        summedFrameMotionMagnitude = 0;

    summedFullMotionVector.x += summedFrameMotionVector.x;
    summedFullMotionVector.y += summedFrameMotionVector.y;
    
    
    
    
    // Add Features to metadata
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    metadata[@"Features"] = pointsArray;
    metadata[@"MotionVector"] = @[@(summedFrameMotionVector.x), @(summedFrameMotionVector.y)];
    metadata[@"Motion"] = @(summedFrameMotionMagnitude);

    // Switch up our last frame
    std::swap(frameFeatures[1], frameFeatures[0]);
    hasInitialized = true;

    // If we havent found half of our tracking points, thats a problem
    if(numAccumulatedFlowPoints < (numFeaturesToTrack / 2))
    {
        tryCount++;
        
        if(tryCount > 1)
        {
            tryCount = 0; // causes reset?
            frameFeatures[0].clear();
            frameFeatures[1].clear();
        }
    }
    
    return metadata;
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
