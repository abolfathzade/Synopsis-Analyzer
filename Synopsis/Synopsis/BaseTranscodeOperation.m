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

@interface BaseTranscodeOperation ()

@property (atomic, readwrite, strong) NSDate* startDate;
@property (atomic, readwrite, assign) NSTimeInterval elapsedTime;
@property (atomic, readwrite, assign) NSTimeInterval remainingTime;

@end

@implementation BaseTranscodeOperation

@synthesize progress = _progress;
@synthesize audioProgress = _audioProgress;
@synthesize videoProgress = _videoProgress;

- (id) init
{
    self = [super init];
    if(self)
    {
        self.videoProgress = (CGFloat)0.0;
        self.audioProgress = (CGFloat)0.0;
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

    self.startDate = [NSDate date];
    self.elapsedTime = 0;
    self.remainingTime = DBL_MIN;

    [super start];
}

- (void) main
{
    @synchronized(self)
    {
        if(self.completionBlock)
        {
            [self setVideoProgress:1.0];
            [self setAudioProgress:1.0];
            
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
        return ((self.videoProgress * 0.9) + (self.audioProgress * 0.1));
    }
}

- (CGFloat) videoProgress
{
    @synchronized(self)
    {
        return _videoProgress;
    }
}

- (void) setVideoProgress:(CGFloat)progress
{
    @synchronized(self)
    {
        _videoProgress = progress;
    }
    
    [self calculateEta];
        
    if(self.progressBlock)
    {
        self.progressBlock(self.progress);
    }
}

- (CGFloat) audioProgress
{
    @synchronized(self)
    {
        return _audioProgress;
    }
}

- (void) setAudioProgress:(CGFloat)progress
{
    @synchronized(self)
    {
        _audioProgress = progress;
    }
    
    [self calculateEta];
    
    if(self.progressBlock)
    {
        self.progressBlock(self.progress);
    }
}


- (void) calculateEta
{
    self.elapsedTime = [[NSDate date] timeIntervalSinceReferenceDate] - [self.startDate timeIntervalSinceReferenceDate];
    double itemsPerSecond = self.progress / self.elapsedTime;
    double secondsRemaining = (1.0 - self.progress) / itemsPerSecond;
    
    self.remainingTime = secondsRemaining;
}

@end
