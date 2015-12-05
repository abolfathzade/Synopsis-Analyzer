//
//  DeepBeliefAnalyzer.m
//  Synopsis
//
//  Created by vade on 12/5/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "DeepBeliefAnalyzer.h"
#import <DeepBelief/DeepBelief.h>

@interface DeepBeliefAnalyzer ()
{
    void* network;
}

// Plugin API requirements
@property (atomic, readwrite, strong) NSString* pluginName;
@property (atomic, readwrite, strong) NSString* pluginIdentifier;
@property (atomic, readwrite, strong) NSArray* pluginAuthors;
@property (atomic, readwrite, strong) NSString* pluginDescription;
@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMinor;
@property (atomic, readwrite, assign) NSUInteger pluginVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginVersionMinor;
@property (atomic, readwrite, strong) NSString* pluginMediaType;

// Some 'metadata' we track
@property (atomic, readwrite, assign) NSUInteger sampleCount;

@end

@implementation DeepBeliefAnalyzer

- (id) init
{
    self = [super init];
    if(self)
    {
        self.pluginName = @"Deep Belief";
        self.pluginIdentifier = @"info.v002.Synopsis.DeepBeliefAnalyzer";
        self.pluginAuthors = @[@"Anton Marini"];
        self.pluginDescription = @"Deep Belief Object Identification Plugin";
        self.pluginAPIVersionMajor = 0;
        self.pluginAPIVersionMinor = 1;
        self.pluginVersionMajor = 0;
        self.pluginVersionMinor = 1;
        self.pluginMediaType = AVMediaTypeVideo;
        
        NSString* networkPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"jetpac" ofType:@"ntwk"];
        if (networkPath == NULL)
        {
            assert(false);
        }
        network = jpcnn_create_network([networkPath UTF8String]);
        assert(network != NULL);
        
    }
    
    return self;
}

- (void) dealloc
{
    if(network)
    {
        jpcnn_destroy_network(network);
    }
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint andEnabledModules:(NSDictionary*)enabledModuleKeys
{

}

- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer transform:(CGAffineTransform)transform error:(NSError**) error
{
    if(sampleBuffer != NULL)
    {
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        if(pixelBuffer != NULL)
        {
            OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType( pixelBuffer );
            
            assert( kCVPixelFormatType_32BGRA == sourcePixelFormat);
            
            const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow( pixelBuffer );
            const int width = (int)CVPixelBufferGetWidth( pixelBuffer );
            const int height = (int)CVPixelBufferGetHeight( pixelBuffer );
            
            CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
            
            unsigned char* sourceStartAddr = CVPixelBufferGetBaseAddress( pixelBuffer );
            const int sourceChannels = 4;
            const int destChannels = 3;
            const int destRowBytes = (width * destChannels);
            const size_t destByteCount = (destRowBytes * height);
            
            // COnvert BGRA to RGB ??
            uint8_t* destData = (uint8_t*)(malloc(destByteCount));
            
            for (int y = 0; y < height; y += 1)
            {
                uint8_t* source = (sourceStartAddr + (y * sourceRowBytes));
                uint8_t* sourceRowEnd = (source + (width * sourceChannels));
                uint8_t* dest = (destData + (y * destRowBytes));
                while (source < sourceRowEnd)
                {
                    dest[0] = source[2]; //r < b
                    dest[1] = source[1]; //g < g
                    dest[2] = source[0]; //b < r
                    source += sourceChannels;
                    dest += destChannels;
                }
            }
            
            void* cnnInput = jpcnn_create_image_buffer_from_uint8_data(destData, width, height, destChannels, destRowBytes, 0, 0);
            
            free(destData);
            CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
            
            float* predictions;
            int predictionsLength;
            char** predictionsLabels;
            int predictionsLabelsLength;
            
            jpcnn_classify_image(network, cnnInput, JPCNN_RANDOM_SAMPLE, 0, &predictions, &predictionsLength, &predictionsLabels, &predictionsLabelsLength);

            jpcnn_destroy_image_buffer(cnnInput);

            NSMutableDictionary* newValues = [NSMutableDictionary dictionary];
            for (int index = 0; index < predictionsLength; index += 1)
            {
                const float predictionValue = predictions[index];
                if (predictionValue > 0.05f)
                {
                    char* label = predictionsLabels[index % predictionsLabelsLength];
                    NSString* labelObject = [NSString stringWithCString:label encoding:NSUTF8StringEncoding];
                    NSNumber* valueObject = [NSNumber numberWithFloat: predictionValue];
                    [newValues setObject: valueObject forKey: labelObject];
                }
            }
            
            return @{ @"Keywords" : newValues};
        }
    }
    
    return nil;
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    return nil;
}

@end

