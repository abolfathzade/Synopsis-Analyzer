//
//  BaseTranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "BaseTranscodeOperation.h"

NSString * const kSynopsisNewTranscodeOperationAvailable = @"kSynopsisNewTranscodeOperationAvailable";

NSString * const kSynopsislMetadataIdentifier = @"mdta/info.v002.synopsis.metadata";

NSString * const kSynopsisTranscodeVideoSettingsKey = @"kSynopsisVideoTranscodeSettings";
NSString * const kSynopsisTranscodeAudioSettingsKey = @"kSynopsisAudioTranscodeSettings";
NSString * const kSynopsisAnalyzedVideoSampleBufferMetadataKey = @"kSynopsisAnalyzedVideoSampleBufferMetadata";
NSString * const kSynopsisAnalyzedAudioSampleBufferMetadataKey = @"kSynopsisAnalyzedAudioSampleBufferMetadata";
NSString * const kSynopsisAnalyzedGlobalMetadataKey = @"kSynopsisAnalyzedGlobalMetadata";

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

- (void) start
{
    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Start Main NSOperation %p", self, nil]];
    
    [super start];
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

    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Finish Main NSOperation %p", self, nil]];
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
