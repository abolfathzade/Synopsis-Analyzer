//
//  OpenCVAnalyzerPlugin.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

// Include OpenCV before anything else because FUCK C++
#import "opencv.hpp"
#import "types_c.h"
#import "features2d.hpp"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

#import "OpenCVAnalyzerPlugin.h"

@interface OpenCVAnalyzerPlugin ()
{
    CMSampleBufferRef lastSampleBuffer;
    cv::Ptr<cv::ORB> detector;
}

@property (atomic, readwrite, strong) NSString* pluginName;
@property (atomic, readwrite, strong) NSString* pluginIdentifier;

@property (atomic, readwrite, strong) NSArray* pluginAuthors;

@property (atomic, readwrite, strong) NSString* pluginDescription;

@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMinor;

@property (atomic, readwrite, assign) NSUInteger pluginVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginVersionMinor;

@property (atomic, readwrite, strong) NSDictionary* pluginReturnedMetadataKeysAndDataTypes;

@property (atomic, readwrite, strong) NSString* pluginMediaType;

@end

@implementation OpenCVAnalyzerPlugin

- (id) init
{
    self = [super init];
    if(self)
    {
        self.pluginName = @"OpenCV Analyzer";
        self.pluginIdentifier = @"info.v002.Synopsis.OpenCVAnalyzer";
        self.pluginAuthors = @[@"Anton Marini"];
        self.pluginDescription = @"OpenCV analyzer";
        self.pluginAPIVersionMajor = 0;
        self.pluginAPIVersionMinor = 1;
        self.pluginVersionMajor = 0;
        self.pluginVersionMinor = 1;
        self.pluginMediaType = AVMediaTypeVideo;
        
        detector = cv::ORB::create();

    }
    
    return self;
}

- (void) dealloc
{
    detector.release();
}

- (void) beginMetadataAnalysisSession
{
    
}

// NOTE YOU HAVE TO MANUALLY MANAGE LOCKING AND UNLOCKING YOURSELF - lifetime of the baseAddress is yours to manage
- (cv::Mat) cvPixelBufferToCVMat:(CVPixelBufferRef)pixelBuffer
{
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
//    size_t width = CVPixelBufferGetWidth( pixelBuffer );
    size_t height = CVPixelBufferGetHeight( pixelBuffer );
    size_t stride = CVPixelBufferGetBytesPerRow( pixelBuffer );
    size_t extendedWidth = stride / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits
    
    // Since the OpenCV Mat is wrapping the CVPixelBuffer's pixel data, we must do all of our modifications while its base address is locked.
    // If we want to operate on the buffer later, we'll have to do an expensive deep copy of the pixel data, using memcpy or Mat::clone().
    
    // Use extendedWidth instead of width to account for possible row extensions (sometimes used for memory alignment).
    // We only need to work on columms from [0, width - 1] regardless.
    
    cv::Mat bgraImage = cv::Mat( (int)height, (int)extendedWidth, CV_8UC4, base );
    
    return bgraImage;
}

- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError**) error
{
//    return nil;
    
    if(sampleBuffer == NULL)
    {
        if (error != NULL)
        {
            *error = [[NSError alloc] initWithDomain:@"Synopsis.noSampleBuffer" code:-6666 userInfo:nil];
        }
        return nil;
    }
    else
    {
        // Our Mutable Metadata Dictionary:
        NSMutableDictionary* metadata = [NSMutableDictionary new];
        
        // Step 1, grab a CVImageBuffer from our CMSampleBuffer
        // This requires our sample buffer to be decoded, not passthrough.
        CVPixelBufferRef currentPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        if(currentPixelBuffer == NULL)
        {
            if (error != NULL)
            {
                *error = [[NSError alloc] initWithDomain:@"Synopsis.noPixelBufferInSampleBuffer" code:-666 userInfo:nil];
            }
            return nil;
        }
        else
        {
            CVPixelBufferLockBaseAddress( currentPixelBuffer, 0 );
            cv::Mat currentBGRAImage = [self cvPixelBufferToCVMat:currentPixelBuffer];
            
#pragma mark - Average Color

            // Half width/height image -
            // TODO: Maybe this becomes part of a quality preference?
            cv::Mat quarterResBGRA;
            cv::resize(currentBGRAImage, quarterResBGRA, cv::Size(currentBGRAImage.size().width * 0.5,
                                                                  currentBGRAImage.size().height * 0.5));
            
            cv::Scalar avgPixelIntensity = cv::mean(quarterResBGRA);

            // Add to metadata - normalize to float
            metadata[@"AverageColor"] = @[@(avgPixelIntensity.val[2] / 255.0), // R
                                          @(avgPixelIntensity.val[1] / 255.0), // G
                                          @(avgPixelIntensity.val[0] / 255.0), // B
                                          ];
            
#pragma mark - Dominant Colors / kMeans
            
            // We choose k = 5 to match Adobe Kuler because whatever.
            int k = 5;
            int n = quarterResBGRA.rows * quarterResBGRA.cols;

            // Convert img BGRA to CIE_LAB or LCh
//            cv::Mat quarterResBGR;
//            cv::Mat quarterResLAB;
//            
//            cv::cvtColor(quarterResBGRA, quarterResBGR, cv::COLOR_BGRA2BGR);
//            cv::cvtColor(quarterResBGR, quarterResLAB, cv::COLOR_BGR2Lab);
            
            std::vector<cv::Mat> imgSplit;
            cv::split(quarterResBGRA,imgSplit);
            
            cv::Mat img3xN(n,3,CV_8U);
            
            for(int i = 0; i != 3; ++i)
            {
                imgSplit[i].reshape(1,n).copyTo(img3xN.col(i));
            }
            
            img3xN.convertTo(img3xN,CV_32F);
            
            cv::Mat bestLables;
            cv::Mat centers;
            
            // TODO: figure out what the fuck makes sense here.
            cv::kmeans(img3xN,
                       k,
                       bestLables,
//                       cv::TermCriteria(),
                       cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 5.0, 1.0),
                       1,
                       cv::KMEANS_PP_CENTERS,
                       centers);
            
            NSMutableArray* dominantColors = [NSMutableArray new];
            
            // LAB to BGR
//            cv::Mat centersBGR;
//            cv::cvtColor(centersLAB.reshape(3,1), centersBGR, cv::COLOR_Lab2BGR);

            for(int i = 0; i < centers.rows; i++)
            {
                // 0 1 or 0 - 255 .0 ?
                cv::Vec3f colorBGR = centers.at<cv::Vec3f>(i, 0);
                
                [dominantColors addObject: @[@(colorBGR.val[2] / 255.0), // R
                                             @(colorBGR.val[1] / 255.0), // G
                                             @(colorBGR.val[0] / 255.0), // B
                                            ]];
            }
            
            metadata[@"DominantColors"] = dominantColors;
            
#pragma mark - Feature Detection
            
            std::vector<cv::KeyPoint> keypoints;// = new std::vector<cv::KeyPoint>;
            detector->detect(currentBGRAImage, keypoints, cv::noArray());
            
            NSMutableArray* keyPointsArray = [NSMutableArray new];
            
            for(std::vector<cv::KeyPoint>::iterator keyPoint = keypoints.begin(); keyPoint != keypoints.end(); ++keyPoint)
            {
                NSArray* point = nil;
                // Ensure our coordinate system is correct
                if(CVImageBufferIsFlipped(currentPixelBuffer))
                {
                    point = @[@(keyPoint->pt.x / currentBGRAImage.size().width),
                              @(1.0 - (keyPoint->pt.y / currentBGRAImage.size().height))
                              ];
                    
                }
                else
                {
                    point = @[@(keyPoint->pt.x / currentBGRAImage.size().width),
                              @(keyPoint->pt.y / currentBGRAImage.size().height)
                              ];
                }
                
                [keyPointsArray addObject:point];
            }
            
            // Add Features to metadata
            metadata[@"Features"] = keyPointsArray;

            
#pragma mark - Frame Difference Motion

            // Can we do frame differencing - note all these tests should pass because we got it last time when the sample was current
            // otherwise it wouldnt be set as last.
            if(lastSampleBuffer != NULL)
            {
                CVPixelBufferRef lastPixelBuffer = CMSampleBufferGetImageBuffer(lastSampleBuffer);
                if(lastPixelBuffer)
                {
                    CVPixelBufferRetain(lastPixelBuffer);

                    CVPixelBufferLockBaseAddress( lastPixelBuffer, 0 );
                    cv::Mat lastBGRAImage = [self cvPixelBufferToCVMat:lastPixelBuffer];
                    
                    // Convert to greyscale
                    cv::Mat currentGreyImage;
                    cv::Mat lastGreyImage;
                    cv::cvtColor(currentBGRAImage, currentGreyImage, cv::COLOR_BGRA2GRAY);
                    cv::cvtColor(lastBGRAImage, lastGreyImage, cv::COLOR_BGRA2GRAY);
                    
                    cv::Mat diff;
                    cv::subtract(currentGreyImage, lastGreyImage, diff);
                    
                    // Average the difference:
                    cv::Scalar avgMotion = cv::mean(diff);

                    // Normalize to float
                    metadata[@"Motion"] = @(avgMotion.val[0] / 255.0);
                    
                    CVPixelBufferUnlockBaseAddress(lastPixelBuffer, 0);
                    CVPixelBufferRelease(lastPixelBuffer);
                }
            }
            
#pragma mark -
            
            // Finished with our current pixel buffer, we have to unlock it.
            CVPixelBufferUnlockBaseAddress( currentPixelBuffer, 0 );
                              
            // If we have our old last sample buffer, free it
            if(lastSampleBuffer != NULL)
            {
                CFRelease(lastSampleBuffer);
                lastSampleBuffer = NULL;
            }
            
            // set a new one
            lastSampleBuffer = (CMSampleBufferRef)CFRetain(sampleBuffer);
        }
        
        return metadata;
    }
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    // If we have our old last sample buffer, free it
    if(lastSampleBuffer != NULL)
    {
        CFRelease(lastSampleBuffer);
        lastSampleBuffer = NULL;
    }
    
    return nil;
}

@end
