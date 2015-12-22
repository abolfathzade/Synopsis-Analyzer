//
//  TranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "AnalysisAndTranscodeOperation.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "AnalyzerPluginProtocol.h"

#import "NSDictionary+JSONString.h"
#import "BSON/BSONSerialization.h"
#import "GZIP/GZIP.h"

@interface AnalysisAndTranscodeOperation ()
{
}

// Prerequisites
@property (atomic, readwrite, strong) NSDictionary* transcodeOptions;
@property (atomic, readwrite, strong) NSArray* availableAnalyzers;

// If we Transcode
// Pass 1: we create our video decoders and analyzers and encoders

// If we dont Transcode
// Pass 1: we create out video decoders and analyzers

// Pass 2:
// we always make passthrough sample buffer readers and writers
// and make new metadata writers

// If we dont, we simply create our video sample buffer readers and writers for pass 2
@property (atomic, readwrite, assign) BOOL transcodingVideo;
@property (atomic, readwrite, assign) BOOL transcodingAudio;
@property (atomic, readwrite, assign) BOOL transcodeAssetHasVideo;
@property (atomic, readwrite, assign) BOOL transcodeAssetHasAudio;

@property (atomic, readwrite, strong) NSDictionary* videoTranscodeSettings;
@property (atomic, readwrite, strong) NSDictionary* audioTranscodeSettings;

// Eventually becomes our analyzed metadata - this stuff is mutated during reading of frames
@property (atomic, readwrite, strong) NSMutableArray* inFlightVideoSampleBufferMetadata;
@property (atomic, readwrite, strong) NSMutableArray* inFlightAudioSampleBufferMetadata;
@property (atomic, readwrite, strong) NSMutableDictionary* inFlightGlobalMetadata;

// Reading the original sample Data
@property (atomic, readwrite, strong) AVURLAsset* transcodeAsset;
@property (atomic, readwrite, strong) AVAssetReader* transcodeAssetReader;
@property (atomic, readwrite, strong) AVAssetReaderTrackOutput* transcodeAssetReaderVideo;
@property (atomic, readwrite, strong) AVAssetReaderTrackOutput* transcodeAssetReaderAudio;

// We have optional pass through readers, which allow us to output pixel formats for analysis
// But we pass through the original data un-re-encoded to avoid generational loss
// Note that these are only used if our transcodeOptions dictionary is correctly configured
// See header for info.
@property (atomic, readwrite, strong) AVAssetReaderTrackOutput* transcodeAssetReaderVideoPassthrough;
@property (atomic, readwrite, strong) AVAssetReaderTrackOutput* transcodeAssetReaderAudioPassthrough;

// Writing new sample data (passthrough or transcode) + Metdata
@property (atomic, readwrite, strong) AVAssetWriter* transcodeAssetWriter;
@property (atomic, readwrite, strong) AVAssetWriterInput* transcodeAssetWriterVideo;
@property (atomic, readwrite, strong) AVAssetWriterInput* transcodeAssetWriterAudio;

@end

@implementation AnalysisAndTranscodeOperation

- (id) initWithSourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL transcodeOptions:(NSDictionary*)transcodeOptions availableAnalyzers:(NSArray*)analyzers
{
    self = [super init];
    if(self)
    {
        if(transcodeOptions == nil)
        {
            return nil;
        }
        
        // Nil settings provides raw undecoded samples, ie passthrough.
        // Note we still need to decode to send to our analyzers

        self.transcodeOptions = transcodeOptions;
        self.videoTranscodeSettings = nil;
        self.audioTranscodeSettings = nil;
        
        self.transcodingVideo = NO;
        self.transcodingAudio = NO;
        
        if(self.transcodeOptions[kSynopsisTranscodeVideoSettingsKey] != [NSNull null])
        {
            self.videoTranscodeSettings = self.transcodeOptions[kSynopsisTranscodeVideoSettingsKey];
            self.transcodingVideo = YES;
        }
        
        if(self.transcodeOptions[kSynopsisTranscodeAudioSettingsKey] != [NSNull null])
        {
            self.audioTranscodeSettings = self.transcodeOptions[kSynopsisTranscodeAudioSettingsKey];
            self.transcodingAudio = YES;
        }
        

        self.sourceURL = sourceURL;
        self.destinationURL = destinationURL;
        
        // Initialize an array of available analyzers from our analyzer class names
        NSMutableArray* initializedAnalyzers = [NSMutableArray new];
        for(NSString* analyzerClassNameString in analyzers)
        {
            Class pluginClass = NSClassFromString(analyzerClassNameString);
            id<AnalyzerPluginProtocol> pluginInstance = [[pluginClass alloc] init];

            [initializedAnalyzers addObject:pluginInstance];
        }
        
        self.availableAnalyzers = initializedAnalyzers;
        
        self.inFlightGlobalMetadata = [NSMutableDictionary new];
        self.inFlightVideoSampleBufferMetadata = [NSMutableArray new];
        self.inFlightAudioSampleBufferMetadata = [NSMutableArray new];
        
        [self setupTranscodeShitSucessfullyOrDontWhatverMan];
    }
    return self;
}

- (NSString*) description
{
    return [NSString stringWithFormat:@"Transcode Operation: %p, Source: %@, Destination: %@, options: %@", self, self.sourceURL, self.destinationURL, self.transcodeOptions];
}

- (void) main
{
    [self transcodeAndAnalyzeAsset];

    [super main];
}


- (NSError*) setupTranscodeShitSucessfullyOrDontWhatverMan
{
    CGAffineTransform prefferedTrackTransform = CGAffineTransformIdentity;
    
    self.transcodeAsset = [AVURLAsset URLAssetWithURL:self.sourceURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @TRUE}];
    
    self.transcodeAssetHasVideo = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual].count ? YES : NO;
    self.transcodeAssetHasAudio = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicAudible].count ? YES : NO;
    
    // TODO: error checking / handling
    NSError* error = nil;
    
    // Readers
    self.transcodeAssetReader = [AVAssetReader assetReaderWithAsset:self.transcodeAsset error:&error];
    
    // Video Reader -
    if(self.transcodeAssetHasVideo)
    {
        AVAssetTrack* firstVideoTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual][0];
        
        self.transcodeAssetReaderVideo = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack
                                                                                    outputSettings:@{(NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                                                                                      }];
        self.transcodeAssetReaderVideo.alwaysCopiesSampleData = YES;
        prefferedTrackTransform = firstVideoTrack.preferredTransform;
        
        // Do we use passthrough?
        if(!self.transcodingVideo)
        {
            self.transcodeAssetReaderVideoPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack outputSettings:nil];
            self.transcodeAssetReaderVideoPassthrough.alwaysCopiesSampleData = YES;
        }
    }
    
    // Audio Reader -
    if(self.transcodeAssetHasAudio)
    {
        AVAssetTrack* firstAudioTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicAudible][0];
        
        // get our audio tracks channel layout - we need this because we ought to match our audios channel count even if we transcode
        
        CMAudioFormatDescriptionRef audioDescription = (__bridge CMAudioFormatDescriptionRef)([firstAudioTrack formatDescriptions][0]);
        
        size_t layoutSize;
        const AudioChannelLayout* layout = CMAudioFormatDescriptionGetChannelLayout(audioDescription, &layoutSize);
        
        unsigned int numberOfChannels = AudioChannelLayoutTag_GetNumberOfChannels(layout->mChannelLayoutTag);
        
        if(self.audioTranscodeSettings[AVNumberOfChannelsKey] == [NSNull null])
        {
            NSMutableDictionary* newAudioSettingsWithChannelCountAndLayout = [self.audioTranscodeSettings mutableCopy];
        
            NSData* audioLayoutData = [[NSData alloc] initWithBytes:layout length:layoutSize];
            
            newAudioSettingsWithChannelCountAndLayout[AVChannelLayoutKey] = audioLayoutData;
            newAudioSettingsWithChannelCountAndLayout[AVNumberOfChannelsKey] = @(numberOfChannels);
            
            self.audioTranscodeSettings = newAudioSettingsWithChannelCountAndLayout;
        }
        
        
        self.transcodeAssetReaderAudio = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstAudioTrack
                                                                                outputSettings:@{(NSString*) AVFormatIDKey : @(kAudioFormatLinearPCM)}];
        self.transcodeAssetReaderAudio.alwaysCopiesSampleData = YES;
        
        if(!self.transcodingAudio)
        {
            self.transcodeAssetReaderAudioPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstAudioTrack outputSettings:nil];
            self.transcodeAssetReaderAudioPassthrough.alwaysCopiesSampleData = YES;
        }
    }

    // Assign all our specific Outputs to our Reader
    // TODO: Error handling if we cant add outputs
    if(self.transcodeAssetHasVideo)
    {
        // Always decoding in Pass 1
        if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderVideo])
        {
            [self.transcodeAssetReader addOutput:self.transcodeAssetReaderVideo];
        }
        
        if(!self.transcodingVideo)
        {
            if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderVideoPassthrough])
            {
                // only add outputs if we are using them.
                [self.transcodeAssetReader addOutput:self.transcodeAssetReaderVideoPassthrough];
            }
        }
    }

    if(self.transcodeAssetHasAudio)
    {
        if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderAudio])
        {
            [self.transcodeAssetReader addOutput:self.transcodeAssetReaderAudio];
        }

        if(!self.transcodingAudio)
        {
            if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderAudioPassthrough])
            {
                [self.transcodeAssetReader addOutput:self.transcodeAssetReaderAudioPassthrough];
            }
        }
    }
    
    NSLog(@"Final Audio Settings: %@", self.audioTranscodeSettings);
    
    // Writers
    self.transcodeAssetWriter = [AVAssetWriter assetWriterWithURL:self.destinationURL fileType:AVFileTypeQuickTimeMovie error:&error];
    self.transcodeAssetWriterVideo = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:self.videoTranscodeSettings];
    self.transcodeAssetWriterAudio = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:self.audioTranscodeSettings];
    
    self.transcodeAssetWriterVideo.expectsMediaDataInRealTime = NO;
    self.transcodeAssetWriterVideo.transform = prefferedTrackTransform;
    
    self.transcodeAssetWriterAudio.expectsMediaDataInRealTime = NO;
    
    // Assign all our specific inputs to our Writer
    if([self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterVideo]
       && [self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterAudio]
       )
    {
        if(self.transcodeAssetHasVideo)
            [self.transcodeAssetWriter addInput:self.transcodeAssetWriterVideo];
        
        if(self.transcodeAssetHasAudio)
            [self.transcodeAssetWriter addInput:self.transcodeAssetWriterAudio];
    }

    // For every Analyzer, begin an new Analysis Session
    for(id<AnalyzerPluginProtocol> analyzer in self.availableAnalyzers)
    {
        [analyzer beginMetadataAnalysisSessionWithQuality:SynopsisAnalysisQualityHintHigh andEnabledModules:nil];
    }
    
    return error;
}


- (void) transcodeAndAnalyzeAsset
{
    CGFloat assetDurationInSeconds = CMTimeGetSeconds(self.transcodeAsset.duration);
    
    if([self.transcodeAssetWriter startWriting] && [self.transcodeAssetReader startReading])
    {
        [self.transcodeAssetWriter startSessionAtSourceTime:kCMTimeZero];
    
        // We need a dispatch group since we have to wrangle multiple queues successfully.
        // Signal both audio and video are done within this task
        dispatch_group_t g = dispatch_group_create();

        // 0 = use as much as you want.
        // Probably want to throttle this and set a small usleep to keep threads happy
        // Or use the CMBufferqueue callbacks with a semaphore signal
        CMItemCount numBuffers = 0;
        
#pragma mark - Video Requirements
        
        // Decode and Encode Queues - each pair writes or reads to a CMBufferQueue
        CMBufferQueueRef videoPassthroughBufferQueue;
        // since we are using passthrough - we have to ensure we use DTS not PTS since buffers may be out of order.
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &videoPassthroughBufferQueue);

        CMBufferQueueRef videoUncompressedBufferQueue;
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForSampleBuffersSortedByOutputPTS(), &videoUncompressedBufferQueue);

        dispatch_queue_t videoPassthrougDecodeQueue = dispatch_queue_create("videoPassthrougDecodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        dispatch_queue_t videoPassthroughEncodeQueue = dispatch_queue_create("videoPassthroughEncodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        // We always need to decode uncompressed frames to send to our analysis plugins
        dispatch_queue_t videoUncompressedDecodeQueue = dispatch_queue_create("videoUncompressedDecodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        // Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
        dispatch_semaphore_t videoDequeueSemaphore = dispatch_semaphore_create(0);
        
        dispatch_queue_t concurrentVideoAnalysisQueue = dispatch_queue_create("concurrentVideoAnalysisQueue", DISPATCH_QUEUE_CONCURRENT);
        
#pragma mark - Audio Requirements
        
        CMBufferQueueRef audioPassthroughBufferQueue;
        // since we are using passthrough - we have to ensure we use DTS not PTS since buffers may be out of order.
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &audioPassthroughBufferQueue);

        CMBufferQueueRef audioUncompressedBufferQueue;
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForSampleBuffersSortedByOutputPTS(), &audioUncompressedBufferQueue);

        dispatch_queue_t audioPassthroughDecodeQueue = dispatch_queue_create("audioPassthroughDecodeQueue", 0);
        if(self.transcodeAssetHasAudio)
            dispatch_group_enter(g);
        
        dispatch_queue_t audioPassthroughEncodeQueue = dispatch_queue_create("audioPassthroughEncodeQueue", 0);
        if(self.transcodeAssetHasAudio)
            dispatch_group_enter(g);
        
        // We always need to decode uncompressed frames to send to our analysis plugins
        dispatch_queue_t audioUncompressedDecodeQueue = dispatch_queue_create("audioUncompressedDecodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasAudio)
            dispatch_group_enter(g);
        
        // Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
        dispatch_semaphore_t audioDequeueSemaphore = dispatch_semaphore_create(0);
        
        dispatch_queue_t concurrentAudioAnalysisQueue = dispatch_queue_create("concurrentAudioAnalysisQueue", DISPATCH_QUEUE_CONCURRENT);

#pragma mark - Read Video pass through

        __block BOOL finishedReadingAllPassthroughVideo = NO;
        
        if(self.transcodeAssetHasVideo)
        {
            // Passthrough Video Read into our Buffer Queue
            dispatch_async(videoPassthrougDecodeQueue, ^{
                
                // read sample buffers from our video reader - and append them to the queue.
                // only read while we have samples, and while our buffer queue isnt full
                
                [[LogController sharedLogController] appendVerboseLog:@"Begun Passthrough Video"];
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading)
                {
                    @autoreleasepool
                    {
                        CMSampleBufferRef passthroughVideoSampleBuffer = [self.transcodeAssetReaderVideoPassthrough copyNextSampleBuffer];
                        if(passthroughVideoSampleBuffer)
                        {
                            // Only add to our passthrough buffer queue if we are going to use those buffers on the encoder end.
                            if(!self.transcodingVideo)
                            {
                                CMBufferQueueEnqueue(videoPassthroughBufferQueue, passthroughVideoSampleBuffer);
                                // Free to dequeue on other thread
                                dispatch_semaphore_signal(videoDequeueSemaphore);
                            }
                            
                            CFRelease(passthroughVideoSampleBuffer);
                        }
                        else
                        {
                            // Got NULL - were done
                            break;
                        }
                    }
                }
                
                finishedReadingAllPassthroughVideo = YES;

                [[LogController sharedLogController] appendSuccessLog:@"Finished Passthrough Video Buffers"];

                // Fire final semaphore signal to hit finalization
                dispatch_semaphore_signal(videoDequeueSemaphore);

                dispatch_group_leave(g);
            });
        }
        
#pragma mark - Read Audio pass through
        
        __block BOOL finishedReadingAllPassthroughAudio = NO;

        if(self.transcodeAssetHasAudio)
        {
            // Passthrough Video Read into our Buffer Queue
            dispatch_async(audioPassthroughDecodeQueue, ^{
                
                // read sample buffers from our video reader - and append them to the queue.
                // only read while we have samples, and while our buffer queue isnt full
                
                [[LogController sharedLogController] appendVerboseLog:@"Begun Passthrough Audio"];
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading)
                {
                    @autoreleasepool
                    {
                        CMSampleBufferRef passthroughAudioSampleBuffer = [self.transcodeAssetReaderAudioPassthrough copyNextSampleBuffer];
                        if(passthroughAudioSampleBuffer)
                        {
                            // Only add to our passthrough buffer queue if we are going to use those buffers on the encoder end.
                            if(!self.transcodingAudio)
                            {
                                CMBufferQueueEnqueue(audioPassthroughBufferQueue, passthroughAudioSampleBuffer);
                                // Free to dequeue on other threao
                                dispatch_semaphore_signal(audioDequeueSemaphore);
                            }
                            
                            CFRelease(passthroughAudioSampleBuffer);
                        }
                        else
                        {
                            // Got NULL - were done
                            break;
                        }
                    }
                }
                
                finishedReadingAllPassthroughAudio = YES;
                
                [[LogController sharedLogController] appendSuccessLog:@"Finished Passthrough Audio Buffers"];
                
                // Fire final semaphore signal to hit finalization
                dispatch_semaphore_signal(audioDequeueSemaphore);
                
                dispatch_group_leave(g);
            });
        }
        
#pragma mark - Read Video Decompressed
        
        // TODO : look at SampleTimingInfo Struct to better get a handle on this shit.
        __block BOOL finishedReadingAllUncompressedVideo = NO;
        
        if(self.transcodeAssetHasVideo)
        {
            dispatch_async(videoUncompressedDecodeQueue, ^{
                
                [[LogController sharedLogController] appendVerboseLog:@"Begun Decompressing Video"];
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading)
                {
                    @autoreleasepool
                    {
                        CMSampleBufferRef uncompressedVideoSampleBuffer = [self.transcodeAssetReaderVideo copyNextSampleBuffer];
                        if(uncompressedVideoSampleBuffer)
                        {
                            // Only add to our uncompressed buffer queue if we are going to use those buffers on the encoder end.
                            if(self.transcodingVideo)
                            {
                                CMBufferQueueEnqueue(videoUncompressedBufferQueue, uncompressedVideoSampleBuffer);
                                // Free to dequeue on other thread
                                dispatch_semaphore_signal(videoDequeueSemaphore);
                            }

                            CMTime currentSamplePTS = CMSampleBufferGetOutputPresentationTimeStamp(uncompressedVideoSampleBuffer);
                            CMTime currentSampleDuration = CMSampleBufferGetOutputDuration(uncompressedVideoSampleBuffer);
                            CMTimeRange currentSampleTimeRange = CMTimeRangeMake(currentSamplePTS, currentSampleDuration);
                            
                            CGFloat currentPresetnationTimeInSeconds = CMTimeGetSeconds(currentSamplePTS);
                            
                            self.videoProgress = currentPresetnationTimeInSeconds / assetDurationInSeconds;

                            __block NSError* analyzerError = nil;

                                NSLock* dictionaryLock = [[NSLock alloc] init];
                            
                            NSMutableDictionary* aggregatedAndAnalyzedMetadata = [NSMutableDictionary new];
                            
                            dispatch_group_t analysisGroup = dispatch_group_create();
                            
                            for(id<AnalyzerPluginProtocol> analyzer in self.availableAnalyzers)
                            {
                                // enter our group.
                                dispatch_group_enter(analysisGroup);
                                
                                // Run an analysis pass on each
                                dispatch_async(concurrentVideoAnalysisQueue, ^{
                                    
                                    NSString* newMetadataKey = [analyzer pluginIdentifier];
                                    NSDictionary* newMetadataValue = [analyzer analyzedMetadataDictionaryForSampleBuffer:uncompressedVideoSampleBuffer transform:self.transcodeAssetWriterVideo.transform error:&analyzerError];
                                    
                                    if(analyzerError)
                                    {
                                        NSString* errorString = [@"Error Analyzing Sample buffer - bailing: " stringByAppendingString:[analyzerError description]];
                                        [[LogController sharedLogController] appendErrorLog:errorString];
                                    }
                                    
                                    if(newMetadataValue)
                                    {
                                        // provide some thread safety to our now async fetches.
                                        [dictionaryLock lock];
                                        [aggregatedAndAnalyzedMetadata setObject:newMetadataValue forKey:newMetadataKey];
                                        [dictionaryLock unlock];
                                    }

                                    dispatch_group_leave(analysisGroup);

                                });
                                
                                dispatch_group_wait(analysisGroup, DISPATCH_TIME_FOREVER);
                                
                                // if we had an analyzer error, bail.
                                if(analyzerError)
                                    break;
                            }
                            
                            // Store out running metadata
                            AVTimedMetadataGroup *group = [self compressedTimedMetadataFromDictionary:aggregatedAndAnalyzedMetadata atTime:currentSampleTimeRange];
                            if(group)
                            {
                                [self.inFlightVideoSampleBufferMetadata addObject:group];
                            }
                            else
                            {
                                [[LogController sharedLogController] appendErrorLog:@"Unable To Convert Metadata to JSON Format, invalid object"];
                            }

                            CFRelease(uncompressedVideoSampleBuffer);
                        }
                        else
                        {
                            // Got NULL - were done
                            // Todo: Move Analysis Finalization here
                            break;
                        }
                        
                    }
                }

                finishedReadingAllUncompressedVideo = YES;

                [[LogController sharedLogController] appendSuccessLog:@"Finished Reading Uncompressed Video Buffers"];
                
                // Fire final semaphore signal to hit finalization
                dispatch_semaphore_signal(videoDequeueSemaphore);

                dispatch_group_leave(g);
            });
        }
        
#pragma mark - Read Audio Decompressed
        
        // TODO : look at SampleTimingInfo Struct to better get a handle on this shit.
        __block BOOL finishedReadingAllUncompressedAudio = NO;
        
        if(self.transcodeAssetHasAudio)
        {
            dispatch_async(audioUncompressedDecodeQueue, ^{
            
            [[LogController sharedLogController] appendVerboseLog:@"Begun Decompressing Audio"];
            
            while(self.transcodeAssetReader.status == AVAssetReaderStatusReading)
            {
                @autoreleasepool
                {
                    CMSampleBufferRef uncompressedAudioSampleBuffer = [self.transcodeAssetReaderAudio copyNextSampleBuffer];
                    if(uncompressedAudioSampleBuffer)
                    {
                        // Only add to our uncompressed buffer queue if we are going to use those buffers on the encoder end.
                        if(self.transcodingAudio)
                        {
                            CMBufferQueueEnqueue(audioUncompressedBufferQueue, uncompressedAudioSampleBuffer);
                            // Free to dequeue on other thread
                            dispatch_semaphore_signal(audioDequeueSemaphore);
                        }
                        
                        CMTime currentSamplePTS = CMSampleBufferGetOutputPresentationTimeStamp(uncompressedAudioSampleBuffer);
                        CMTime currentSampleDuration = CMSampleBufferGetOutputDuration(uncompressedAudioSampleBuffer);
                        CMTimeRange currentSampleTimeRange = CMTimeRangeMake(currentSamplePTS, currentSampleDuration);
                        
                        CGFloat currentPresetnationTimeInSeconds = CMTimeGetSeconds(currentSamplePTS);
                        
                        self.audioProgress = currentPresetnationTimeInSeconds / assetDurationInSeconds;
                        
                        // Disable Audio Analysis Plugins for now.
//                        __block NSError* analyzerError = nil;
//                        
//                        NSLock* dictionaryLock = [[NSLock alloc] init];
//                        
//                        NSMutableDictionary* aggregatedAndAnalyzedMetadata = [NSMutableDictionary new];
//                        
//                        dispatch_group_t analysisGroup = dispatch_group_create();

//                        for(id<AnalyzerPluginProtocol> analyzer in self.availableAnalyzers)
//                        {
//                            // enter our group.
//                            dispatch_group_enter(analysisGroup);
//                            
//                            // Run an analysis pass on each
//                            dispatch_async(concurrentAudioAnalysisQueue, ^{
//                                
//                                NSString* newMetadataKey = [analyzer pluginIdentifier];
//                                NSDictionary* newMetadataValue = [analyzer analyzedMetadataDictionaryForSampleBuffer:uncompressedAudioSampleBuffer transform:self.transcodeAssetWriterVideo.transform error:&analyzerError];
//                                
//                                if(analyzerError)
//                                {
//                                    NSString* errorString = [@"Error Analyzing Sample buffer - bailing: " stringByAppendingString:[analyzerError description]];
//                                    [[LogController sharedLogController] appendErrorLog:errorString];
//                                }
//                                
//                                if(newMetadataValue)
//                                {
//                                    // provide some thread safety to our now async fetches.
//                                    [dictionaryLock lock];
//                                    [aggregatedAndAnalyzedMetadata setObject:newMetadataValue forKey:newMetadataKey];
//                                    [dictionaryLock unlock];
//                                }
//                                
//                                dispatch_group_leave(analysisGroup);
//                                
//                            });
//                            
//                            dispatch_group_wait(analysisGroup, DISPATCH_TIME_FOREVER);
//                            
//                            // if we had an analyzer error, bail.
//                            if(analyzerError)
//                                break;
//                        }
//                        
//                        // Store out running metadata
//                        AVTimedMetadataGroup *group = [self compressedTimedMetadataFromDictionary:aggregatedAndAnalyzedMetadata atTime:currentSampleTimeRange];
//                        if(group)
//                        {
//                            [self.inFlightVideoSampleBufferMetadata addObject:group];
//                        }
//                        else
//                        {
//                            [[LogController sharedLogController] appendErrorLog:@"Unable To Convert Metadata to JSON Format, invalid object"];
//                        }
                        
                        CFRelease(uncompressedAudioSampleBuffer);
                    }
                    else
                    {
                        // Got NULL - were done
                        // Todo: Move Analysis Finalization here
                        break;
                    }
                    
                }
            }
            
            finishedReadingAllUncompressedAudio = YES;
            
            [[LogController sharedLogController] appendSuccessLog:@"Finished Reading Uncompressed Audio Buffers"];
            
            // Fire final semaphore signal to hit finalization
            dispatch_semaphore_signal(audioDequeueSemaphore);
            
            dispatch_group_leave(g);
        });
        }
        
#pragma mark - Write Video (Pass through or Encoded)
        
        if(self.transcodeAssetHasVideo)
        {
            [self.transcodeAssetWriterVideo requestMediaDataWhenReadyOnQueue:videoPassthroughEncodeQueue usingBlock:^
            {
                [[LogController sharedLogController] appendVerboseLog:@"Begun Writing Video"];
                
                while([self.transcodeAssetWriterVideo isReadyForMoreMediaData])
                {
                    // Are we done reading,
                    if(finishedReadingAllPassthroughVideo && finishedReadingAllUncompressedVideo)
                    {
                        NSLog(@"Finished Reading waiting to empty queue...");
                        dispatch_semaphore_signal(videoDequeueSemaphore);

                        if(CMBufferQueueIsEmpty(videoPassthroughBufferQueue) && CMBufferQueueIsEmpty(videoUncompressedBufferQueue))
                        {
                            // TODO: AGGREGATE METADATA THAT ISNT PER FRAME
                            NSError* analyzerError = nil;
                            for(id<AnalyzerPluginProtocol> analyzer in self.availableAnalyzers)
                            {
                                NSDictionary* finalizedMetadata = [analyzer finalizeMetadataAnalysisSessionWithError:&analyzerError];
                                if(analyzerError)
                                {
                                    NSString* errorString = [@"Error Finalizing Analysis - bailing: " stringByAppendingString:[analyzerError description]];
                                    [[LogController sharedLogController] appendErrorLog:errorString];

                                    dispatch_group_leave(g);

                                    break;
                                }
                                
                                // set our global metadata for the analyzer
                                if(finalizedMetadata)
                                {
                                    self.inFlightGlobalMetadata[analyzer.pluginIdentifier] = finalizedMetadata;
                                }
                                else
                                {
                                    NSString* warning = [@"No Global Analysis Data for Analyzer %@ " stringByAppendingString:analyzer.pluginIdentifier];
                                    [[LogController sharedLogController] appendWarningLog:warning];
                                }
                            }
                        
                            [self.transcodeAssetWriterVideo markAsFinished];
                            
                            [[LogController sharedLogController] appendSuccessLog:@"Finished Writing Video"];

                            dispatch_group_leave(g);
                            break;
                        }
                    }
                    
                    CMSampleBufferRef videoSampleBuffer = NULL;

                    // wait to dequeue until we have an enqueued buffer / signal from our enqueue thread.
                    dispatch_semaphore_wait(videoDequeueSemaphore, DISPATCH_TIME_FOREVER);

                    // Pull from an appropriate source - passthrough or decompressed
                    if(self.transcodingVideo)
                    {
                        videoSampleBuffer = (CMSampleBufferRef) CMBufferQueueDequeueAndRetain(videoUncompressedBufferQueue);
                    }
                    else
                    {
                        videoSampleBuffer = (CMSampleBufferRef) CMBufferQueueDequeueAndRetain(videoPassthroughBufferQueue);
                    }
                    
                    if(videoSampleBuffer)
                    {
                        //[[LogController sharedLogController] appendVerboseLog:@"Dequeueing and Writing Uncompressed Sample Buffer"];
                        if(![self.transcodeAssetWriterVideo appendSampleBuffer:videoSampleBuffer])
                        {
                            NSString* errorString = [@"Unable to append sampleBuffer: " stringByAppendingString:[self.transcodeAssetWriter.error description]];
                            [[LogController sharedLogController] appendErrorLog:errorString];
                        }
                        CFRelease(videoSampleBuffer);
                    }
                }
                
                // some debug code to see 
                if(finishedReadingAllPassthroughVideo && finishedReadingAllUncompressedVideo)
                {
                    if(!CMBufferQueueIsEmpty(videoPassthroughBufferQueue) || !CMBufferQueueIsEmpty(videoUncompressedBufferQueue))
                    {
                        [[LogController sharedLogController] appendWarningLog:@"Stopped Requesting Destination Video but did not empty Source Queues"];
                    }
                }
                else
                {
                    [[LogController sharedLogController] appendWarningLog:@"Stopped Requesting Destination Video but did not finish reading Source Video"];
                    
                    if(!CMBufferQueueIsEmpty(videoPassthroughBufferQueue) || !CMBufferQueueIsEmpty(videoUncompressedBufferQueue))
                    {
                        [[LogController sharedLogController] appendWarningLog:@"Stopped Requesting Destination Video but did not empty Source Queues"];
                    }
                }
            
            }];
        }
        
#pragma mark - Write Audio (Pass through or Encoded)
        
        if(self.transcodeAssetHasAudio)
        {
            [self.transcodeAssetWriterAudio requestMediaDataWhenReadyOnQueue:audioPassthroughEncodeQueue usingBlock:^
             {
                 [[LogController sharedLogController] appendVerboseLog:@"Begun Writing Audio"];
                 
                 while([self.transcodeAssetWriterAudio isReadyForMoreMediaData])
                 {
                     // Are we done reading,
                     if(finishedReadingAllPassthroughAudio && finishedReadingAllUncompressedAudio)
                     {
                         NSLog(@"Finished Reading waiting to empty queue...");
                         dispatch_semaphore_signal(audioDequeueSemaphore);
                         
                         if(CMBufferQueueIsEmpty(audioPassthroughBufferQueue) && CMBufferQueueIsEmpty(audioUncompressedBufferQueue))
                         {
                             // TODO: AGGREGATE METADATA THAT ISNT PER FRAME
    //                         NSError* analyzerError = nil;
    //                         for(id<AnalyzerPluginProtocol> analyzer in self.availableAnalyzers)
    //                         {
    //                             NSDictionary* finalizedMetadata = [analyzer finalizeMetadataAnalysisSessionWithError:&analyzerError];
    //                             if(analyzerError)
    //                             {
    //                                 NSString* errorString = [@"Error Finalizing Analysis - bailing: " stringByAppendingString:[analyzerError description]];
    //                                 [[LogController sharedLogController] appendErrorLog:errorString];
    //                                 
    //                                 dispatch_group_leave(g);
    //                                 
    //                                 break;
    //                             }
    //                             
    //                             // set our global metadata for the analyzer
    //                             if(finalizedMetadata)
    //                             {
    //                                 self.inFlightGlobalMetadata[analyzer.pluginIdentifier] = finalizedMetadata;
    //                             }
    //                             else
    //                             {
    //                                 NSString* warning = [@"No Global Analysis Data for Analyzer %@ " stringByAppendingString:analyzer.pluginIdentifier];
    //                                 [[LogController sharedLogController] appendWarningLog:warning];
    //                             }
    //                         }
                             
                             [self.transcodeAssetWriterAudio markAsFinished];
                             
                             [[LogController sharedLogController] appendSuccessLog:@"Finished Writing Audio"];
                             
                             dispatch_group_leave(g);
                             break;
                         }
                     }
                     
                     CMSampleBufferRef audioSampleBuffer = NULL;
                     
                     // wait to dequeue until we have a enqueued buffer signal from our enqueue thread.
                     dispatch_semaphore_wait(audioDequeueSemaphore, DISPATCH_TIME_FOREVER);
                     
                     // Pull from an appropriate source - passthrough or decompressed
                     if(self.transcodingAudio)
                     {
                         audioSampleBuffer = (CMSampleBufferRef) CMBufferQueueDequeueAndRetain(audioUncompressedBufferQueue);
                     }
                     else
                     {
                         audioSampleBuffer = (CMSampleBufferRef) CMBufferQueueDequeueAndRetain(audioPassthroughBufferQueue);
                     }
                     
                     if(audioSampleBuffer)
                     {
                         //[[LogController sharedLogController] appendVerboseLog:@"Dequeueing and Writing Uncompressed Sample Buffer"];
                         if(![self.transcodeAssetWriterAudio appendSampleBuffer:audioSampleBuffer])
                         {
                             NSString* errorString = [@"Unable to append sampleBuffer: " stringByAppendingString:[self.transcodeAssetWriter.error description]];
                             [[LogController sharedLogController] appendErrorLog:errorString];
                         }
                         CFRelease(audioSampleBuffer);
                     }
                 }
                 
                 // some debug code to see
                 if(finishedReadingAllPassthroughAudio && finishedReadingAllUncompressedAudio)
                 {
                     if(!CMBufferQueueIsEmpty(audioPassthroughBufferQueue) || !CMBufferQueueIsEmpty(audioUncompressedBufferQueue))
                     {
                         [[LogController sharedLogController] appendWarningLog:@"Stopped Requesting Destination Audio but did not empty Source Queues"];
                     }
                 }
                 else
                 {
                     [[LogController sharedLogController] appendWarningLog:@"Stopped Requesting Destination Audio but did not finish reading Source Video"];
                     
                     if(!CMBufferQueueIsEmpty(audioPassthroughBufferQueue) || !CMBufferQueueIsEmpty(audioUncompressedBufferQueue))
                     {
                         [[LogController sharedLogController] appendWarningLog:@"Stopped Requesting Destination Audio but did not empty Source Queues"];
                     }
                 }
                 
             }];
        }
        
#pragma mark - Cleanup
        
        // Wait until every queue is finished processing
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        
        // re-enter g
        dispatch_group_enter(g);
        
        [self.transcodeAssetWriter finishWritingWithCompletionHandler:^{

            dispatch_group_leave(g);
            
        }];
        
        // Wait until every queue is finished processing
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);

        self.analyzedGlobalMetadata = self.inFlightGlobalMetadata;
        self.analyzedVideoSampleBufferMetadata = self.inFlightVideoSampleBufferMetadata;
        self.analyzedAudioSampleBufferMetadata = self.inFlightAudioSampleBufferMetadata;
        
        // reset / empty our buffer queues
        CMBufferQueueReset(videoPassthroughBufferQueue);
        CMBufferQueueReset(videoUncompressedBufferQueue);
        CMBufferQueueReset(audioPassthroughBufferQueue);
        CMBufferQueueReset(audioUncompressedBufferQueue);
        
        // cleanup
        CFRelease(videoPassthroughBufferQueue);
        CFRelease(videoUncompressedBufferQueue);
        CFRelease(audioPassthroughBufferQueue);
        CFRelease(audioUncompressedBufferQueue);
        
        // dealloc any analyzers now
        self.availableAnalyzers = nil;
        
        [[LogController sharedLogController] appendSuccessLog:@"Finished Analysis Operation"];
    }
    else
    {
        [[LogController sharedLogController] appendErrorLog:@"Unable to start transcode:"];
        [[LogController sharedLogController] appendErrorLog:[@"Read Error" stringByAppendingString:self.transcodeAssetReader.error.debugDescription]];
        [[LogController sharedLogController] appendErrorLog:[@"Write Error" stringByAppendingString:self.transcodeAssetWriter.error.debugDescription]];
    }
}

#pragma mark - Metadata Helper

-(AVTimedMetadataGroup*) compressedTimedMetadataFromDictionary:(NSDictionary*)aggregatedAndAnalyzedMetadata atTime:(CMTimeRange)currentSampleTimeRange
{
    if([NSJSONSerialization isValidJSONObject:aggregatedAndAnalyzedMetadata])
    {
        // TODO: Probably want to mark to NO for shipping code:
        NSString* aggregateMetadataAsJSON = [aggregatedAndAnalyzedMetadata jsonStringWithPrettyPrint:NO];
        NSData* jsonData = [aggregateMetadataAsJSON dataUsingEncoding:NSUTF8StringEncoding];
        
        NSData* gzipData = [jsonData gzippedData];
        
        // Annotation text item
        AVMutableMetadataItem *textItem = [AVMutableMetadataItem metadataItem];
        textItem.identifier = kSynopsislMetadataIdentifier;
        textItem.dataType = (__bridge NSString *)kCMMetadataBaseDataType_RawData;
        textItem.value = gzipData;
        
        AVTimedMetadataGroup *group = [[AVTimedMetadataGroup alloc] initWithItems:@[textItem] timeRange:currentSampleTimeRange];
        
        return group;
    }

    return nil;
}

@end
