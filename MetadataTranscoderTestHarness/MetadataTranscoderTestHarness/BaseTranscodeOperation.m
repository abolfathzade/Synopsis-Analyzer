//
//  BaseTranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "BaseTranscodeOperation.h"
#import "LogController.h"

const NSString* kMetavisualMetadataIdentifier = @"mdta/org.metavisual.somethingsomething";


const NSString* kMetavisualTranscodeVideoSettingsKey = @"kMetavisualVideoTranscodeSettings";
const NSString* kMetavisualTranscodeAudioSettingsKey = @"kMetavisualAudioTranscodeSettings";
const NSString* kMetavisualAnalyzedVideoSampleBufferMetadataKey = @"kMetavisualAnalyzedVideoSampleBufferMetadata";
const NSString* kMetavisualAnalyzedAudioSampleBufferMetadataKey = @"kMetavisualAnalyzedAudioSampleBufferMetadata";
const NSString* kMetavisualAnalyzedGlobalMetadataKey = @"kMetavisualAnalyzedGlobalMetadata";

@implementation BaseTranscodeOperation

@synthesize progress = _progress;

- (id) init
{
    self = [super init];
    if(self)
    {
        self.progress = (CGFloat)0.0;
    }
    
    return self;
}

- (void) dealloc
{
    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Dealloc NSOperation %p", self, nil]];
}

- (void) main
{

    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Run Main NSOperation %p", self, nil]];
   
    @synchronized(self)
    {
        if(self.completionBlock)
        {
            self.completionBlock();

            NSLog(@"COMPLETION BLOCK RUN");
            // Clear so we dont run twice, fucko
            self.completionBlock = nil;
        }
    }
}

- (CGFloat) progress
{
    @synchronized(self)
    {
        return _progress;
    }
}

- (void) setProgress:(CGFloat)progress
{
    @synchronized(self)
    {
        _progress = progress;
    }
    
    if(self.progressBlock)
    {
        self.progressBlock(progress);
    }
}

@end
