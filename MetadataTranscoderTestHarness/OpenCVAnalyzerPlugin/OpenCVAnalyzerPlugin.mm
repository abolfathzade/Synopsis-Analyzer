//
//  OpenCVAnalyzerPlugin.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
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
        self.pluginIdentifier = @"org.metavisual.OpenCVAnalyzer";
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


- (void) beginMetadataAnalysisSession
{
    
}

// NOTE YOU HAVE TO MANUALLY MANAGE LOCKING AND UNLOCKING YOURSELF - lifetime of the baseAddress is yours to manage
- (cv::Mat) cvPixelBufferToCVMat:(CVPixelBufferRef)pixelBuffer
{
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
    size_t width = CVPixelBufferGetWidth( pixelBuffer );
    size_t height = CVPixelBufferGetHeight( pixelBuffer );
    size_t stride = CVPixelBufferGetBytesPerRow( pixelBuffer );
    size_t extendedWidth = stride / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits
    
    // Since the OpenCV Mat is wrapping the CVPixelBuffer's pixel data, we must do all of our modifications while its base address is locked.
    // If we want to operate on the buffer later, we'll have to do an expensive deep copy of the pixel data, using memcpy or Mat::clone().
    
    // Use extendedWidth instead of width to account for possible row extensions (sometimes used for memory alignment).
    // We only need to work on columms from [0, width - 1] regardless.
    
    cv::Mat bgraImage = cv::Mat( (int)height, (int)extendedWidth, CV_8UC4, base );
    
    // Populate BGRA image with data references from our pixel buffer
    for ( uint32_t y = 0; y < height; y++ )
    {
        for ( uint32_t x = 0; x < width; x++ )
        {
            // Todo: This is forcing alpha to 0. Do we give a shit about that?
            bgraImage.at<cv::Vec<uint8_t,4> >(y,x);//[3] = 0;
        }
    }

    return bgraImage;
}

- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError**) error
{
    if(sampleBuffer == NULL)
    {
        NSError* noSampleBufferError = [[NSError alloc] initWithDomain:@"Metavisual.noSampleBuffer" code:-6666 userInfo:nil];
        *error = noSampleBufferError;
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
                NSError* noPixelBufferError = [[NSError alloc] initWithDomain:@"Metavisual.noPixelBufferInSampleBuffer" code:-666 userInfo:nil];
                *error = noPixelBufferError;
                return nil;
        }
        else
        {
            CVPixelBufferLockBaseAddress( currentPixelBuffer, 0 );
            cv::Mat currentBGRAImage = [self cvPixelBufferToCVMat:currentPixelBuffer];

            // Get our average Color
            cv::Scalar avgPixelIntensity = cv::mean(currentBGRAImage);
            
#pragma mark - Average Color

            // Add to metadata - normalize to float
            metadata[@"AverageColor"] = @[@(avgPixelIntensity.val[2] / 255.0), // R
                                          @(avgPixelIntensity.val[1] / 255.0), // G
                                          @(avgPixelIntensity.val[0] / 255.0), // B
                                          ];
            
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
                    
#pragma mark - Frame Difference Motion
                    
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
                    
#pragma mark - Feature Detection
                    
//                    if(detector == NULL)
//                    {
//                    }
                    
                    std::vector<cv::KeyPoint> keypoints;// = new std::vector<cv::KeyPoint>;
                    detector->empty();
//
                    
                    
                    
                    
                    
                    
                    
                    
                    
                    detector->detect(currentBGRAImage, keypoints, cv::noArray());

//                    std::cout << "Found " << keypoints.size() << " Keypoints " << std::endl;
                    
                    NSMutableArray* keyPointsArray = [NSMutableArray new];

                    for(std::vector<cv::KeyPoint>::iterator keyPoint = keypoints.begin(); keyPoint != keypoints.end(); ++keyPoint)
                    {
                        // Ensure our coordinate system is correct
                        if(CVImageBufferIsFlipped(currentPixelBuffer))
                        {
                            NSArray* point = @[@(keyPoint->pt.x / currentBGRAImage.size().width),
                                               @(1.0 - (keyPoint->pt.y / currentBGRAImage.size().height))
                                               ];
                            
                            [keyPointsArray addObject:point];
                        }
                        else
                        {
                            NSArray* point = @[@(keyPoint->pt.x / currentBGRAImage.size().width),
                                               @(keyPoint->pt.y / currentBGRAImage.size().height)
                                               ];
                            
                            [keyPointsArray addObject:point];
                        }
                    }
                    
                    // Add Features to metadata
                    metadata[@"Features"] = keyPointsArray;
                    
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
