//
//  BaseTranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "BaseTranscodeOperation.h"

// Notification Key, used when our enqueing fires off a new operation
NSString * const kSynopsisNewTranscodeOperationAvailable = @"kSynopsisNewTranscodeOperationAvailable";
// Notification used when an transcode operation updates
NSString* const kSynopsisTranscodeOperationProgressUpdate = @"kSynopsisTranscodeOperationPass1ProgressUpdate";

// Above Notifications sends a user info object that is our operations
// "descriptionDictionary"

// keys for descriptionDictionary
NSString* const kSynopsisTranscodeOperationUUIDKey = @"UUID"; //  NSUUID
NSString* const kSynopsisTranscodeOperationSourceURLKey = @"sourceURL"; // NSURL
NSString* const kSynopsisTranscodeOperationDestinationURLKey = @"destinationURL"; // NSURL
NSString* const kSynopsisTranscodeOperationProgressKey = @"progress";// NSNumber current progress
NSString* const kSynopsisTranscodeOperationTimeElapsedKey = @"timeelapsed"; // NSNumber as NSTimeInterval
NSString* const kSynopsisTranscodeOperationTimeRemainingKey = @"timeremaining"; // NSNumber as NSTimeInterval
NSString* const kSynopsisTranscodeOperationMetadataKey = @"metadata";// NSDictionary of available analyzed metadata - may be nil


// Pass 1
NSString * const kSynopsisTranscodeVideoSettingsKey = @"kSynopsisVideoTranscodeSettings";
NSString * const kSynopsisTranscodeAudioSettingsKey = @"kSynopsisAudioTranscodeSettings";
NSString * const kSynopsisAnalysisSettingsKey = @"kSynopsisAnalysisSettings";
NSString * const kSynopsisAnalysisSettingsQualityHintKey = @"kSynopsisAnalysisSettingsQualityHintKey";
NSString * const kSynopsisAnalysisSettingsEnableConcurrencyKey = @"kSynopsisAnalysisSettingsEnableConcurrencyKey";
NSString * const kSynopsisAnalysisSettingsEnabledPluginsKey = @"kSynopsisAnalysisSettingsEnabledPluginsKey";
NSString * const kSynopsisAnalysisSettingsEnabledPluginModulesKey = @"kSynopsisAnalysisSettingsEnabledPluginModulesKey";

// Pass 2
NSString * const kSynopsisAnalyzedVideoSampleBufferMetadataKey = @"kSynopsisAnalyzedVideoSampleBufferMetadata";
NSString * const kSynopsisAnalyzedAudioSampleBufferMetadataKey = @"kSynopsisAnalyzedAudioSampleBufferMetadata";
NSString * const kSynopsisAnalyzedGlobalMetadataKey = @"kSynopsisAnalyzedGlobalMetadata";

@interface BaseTranscodeOperation ()

@property (atomic, readwrite, strong) NSDictionary* descriptionDictionary;
@property (atomic, readwrite, strong) NSURL* sourceURL;
@property (atomic, readwrite, strong) NSURL* destinationURL;

@property (atomic, readwrite, strong) NSUUID* uuid;
@property (atomic, readwrite, strong) NSDate* startDate;
@property (atomic, readwrite, assign) NSTimeInterval elapsedTime;
@property (atomic, readwrite, assign) NSTimeInterval remainingTime;

@property (atomic, readwrite, assign) BOOL initted;

@end

@implementation BaseTranscodeOperation

@synthesize progress = _progress;
@synthesize audioProgress = _audioProgress;
@synthesize videoProgress = _videoProgress;

- (instancetype) initWithUUID:(NSUUID*)uuid sourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL;
{
    self = [super init];
    if(self)
    {
        self.initted = NO;
        self.uuid = uuid;
        self.sourceURL = sourceURL;
        self.destinationURL = destinationURL;
        
        self.videoProgress = (CGFloat)0.0;
        self.audioProgress = (CGFloat)0.0;
        
        self.descriptionDictionary = @{ kSynopsisTranscodeOperationUUIDKey : self.uuid,
                                        kSynopsisTranscodeOperationSourceURLKey : self.sourceURL,
                                        kSynopsisTranscodeOperationDestinationURLKey : self.destinationURL,
                                        kSynopsisTranscodeOperationProgressKey : @(0),
                                        kSynopsisTranscodeOperationTimeElapsedKey: @(0),
                                        kSynopsisTranscodeOperationTimeRemainingKey : @( DBL_MIN ),
                                        };
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]  postNotificationName:kSynopsisNewTranscodeOperationAvailable object:self.descriptionDictionary];
        });
        
        self.initted = YES;

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
    
}


- (void) calculateEta
{
    self.elapsedTime = [[NSDate date] timeIntervalSinceReferenceDate] - [self.startDate timeIntervalSinceReferenceDate];
    double itemsPerSecond = self.progress / self.elapsedTime;
    double secondsRemaining = (1.0 - self.progress) / itemsPerSecond;
    
    self.remainingTime = secondsRemaining;
    
    // send notification of updated progress and ETA
    if(self.initted)
    {
        [self notifyProgress];
    }
}

- (void) notifyProgress
{
    [self doesNotRecognizeSelector:_cmd];
}

@end
