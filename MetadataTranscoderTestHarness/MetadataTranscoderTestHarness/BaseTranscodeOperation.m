//
//  BaseTranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "BaseTranscodeOperation.h"

const NSString* kMetavisualMetadataIdentifier = @"mdta/org.metavisual.somethingsomething";


const NSString* kMetavisualTranscodeVideoSettingsKey = @"kMetavisualVideoTranscodeSettings";
const NSString* kMetavisualTranscodeAudioSettingsKey = @"kMetavisualAudioTranscodeSettings";
const NSString* kMetavisualAnalyzedVideoSampleBufferMetadataKey = @"kMetavisualAnalyzedVideoSampleBufferMetadata";
const NSString* kMetavisualAnalyzedAudioSampleBufferMetadataKey = @"kMetavisualAnalyzedAudioSampleBufferMetadata";
const NSString* kMetavisualAnalyzedGlobalMetadataKey = @"kMetavisualAnalyzedGlobalMetadata";

@implementation BaseTranscodeOperation

- (id) init
{
    self = [super init];
    if(self)
    {
        
        self.progress = (CGFloat)0.0;
    }
    
    return self;
}

- (void) main
{
    @synchronized(self)
    {
        if(self.completionBlock)
        {
            self.completionBlock();

            // Clear so we dont run twice, fucko
            self.completionBlock = nil;
        }
    }
}

@end
