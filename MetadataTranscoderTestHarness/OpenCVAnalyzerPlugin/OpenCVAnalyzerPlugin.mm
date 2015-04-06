//
//  OpenCVAnalyzerPlugin.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

// Include OpenCV before anything else because FUCK C++
#import "opencv.hpp"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>

#import "OpenCVAnalyzerPlugin.h"

@interface OpenCVAnalyzerPlugin ()

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
    }
    
    return self;
}


- (void) beginMetadataAnalysisSession
{
    
}

- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError**) error
{
    // Step 1, grab a CVImageBuffer from our CMSampleBuffer
    // This requires our sample buffer to be decoded, not passthrough.
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // Early Bail
    if(pixelBuffer)
    {
        // All pixel buffers are BGRA
        
        CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
        
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
        
        for ( uint32_t y = 0; y < height; y++ )
        {
            for ( uint32_t x = 0; x < width; x++ )
            {
                bgraImage.at<cv::Vec<uint8_t,4> >(y,x)[1] = 0;
            }
        }
        
        cv::Scalar avgPixelIntensity = cv::mean( bgraImage );

        NSDictionary* metadata = @{@"Intensity" : @[ @(avgPixelIntensity.val[0]), @(avgPixelIntensity.val[1]), @(avgPixelIntensity.val[2])]
                                   };
        
        CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
        
        return metadata;
    }
    
    // No pixelbuffer in our sample buffer. Thats bad.
    else
    {
        NSError* noPixelBufferError = [[NSError alloc] initWithDomain:@"Metavisual.noPixelBufferInSampleBuffer" code:-666 userInfo:nil];
        
        *error = noPixelBufferError;
        
        return nil;

    }
    
    
    return nil;
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    return nil;    
}

@end
