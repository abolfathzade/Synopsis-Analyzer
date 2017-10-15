//
//  TranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "Constants.h"
#import <Synopsis/Synopsis.h>
#import "AnalysisAndTranscodeOperation.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "VideoTransformScaleLinearizeHelper.h"

#import "HapInAVFoundation.h"

#import "NSDictionary+JSONString.h"
#import "BSON/BSONSerialization.h"
#import "GZIP/GZIP.h"
#import "AtomicBoolean.h"

@interface BaseTranscodeOperation (Private)
@property (readwrite, assign) BOOL succeeded;
@property (readwrite, strong) NSError* error;
@end

@interface AnalysisAndTranscodeOperation ()
{
    // Decode and Encode Queues - each pair writes or reads to a CMBufferQueue
    CMBufferQueueRef videoPassthroughBufferQueue;
    CMBufferQueueRef videoUncompressedBufferQueue;

}

@property (atomic, readwrite, strong) VideoTransformScaleLinearizeHelper* videoHelper;

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

// HAP Additions
@property (atomic, readwrite, assign) BOOL decodeHAP;
@property (atomic, readwrite, assign) BOOL encodeHAP;


@property (atomic, readwrite, strong) NSDictionary* videoTranscodeSettings;
@property (atomic, readwrite, strong) NSDictionary* audioTranscodeSettings;

// Eventually becomes our analyzed metadata - this stuff is mutated during reading of frames
@property (atomic, readwrite, strong) NSMutableArray<NSDictionary*>* inFlightVideoSampleBufferMetadata;
@property (atomic, readwrite, strong) NSMutableArray<NSDictionary*>* inFlightAudioSampleBufferMetadata;
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

@property (atomic, readwrite, strong) NSArray* requestedAnalyzers;

@property (atomic, readwrite, assign) SynopsisAnalysisQualityHint analysisQualityHint;

//@property (atomic, readwrite, strong) SynopsisMetadataEncoder* metadataEncoder;

// Transcode Operation and Queue objects
// Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
@property (readwrite, strong) dispatch_semaphore_t videoDequeueSemaphore;
@property (readwrite, strong) NSOperationQueue* videoPassthroughDecodeQueue;
@property (readwrite, strong) dispatch_queue_t videoPassthroughEncodeQueue;
@property (readwrite, strong) NSOperationQueue* videoUncompressedDecodeQueue;

@property (readwrite, strong) NSOperationQueue* concurrentVideoAnalysisQueue;
@property (readwrite, strong) NSOperationQueue* videoTransformQueue;
@property (readwrite, strong) NSOperationQueue* jsonEncodeQueue;

@end

@implementation AnalysisAndTranscodeOperation

- (instancetype) initWithUUID:(NSUUID*)uuid sourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL transcodeOptions:(NSDictionary*)transcodeOptions
{
    self = [super initWithUUID:uuid sourceURL:sourceURL destinationURL:destinationURL];
    if(self)
    {
        if(transcodeOptions == nil)
        {
            return nil;
        }
        
        // Nil settings provides raw undecoded samples, ie passthrough.
        // Note we still need to decode to send to our analyzers

        self.videoHelper = [[VideoTransformScaleLinearizeHelper alloc] init];
        
        self.transcodeOptions = transcodeOptions;
        self.videoTranscodeSettings = nil;
        self.audioTranscodeSettings = nil;
        
        self.transcodingVideo = NO;
        self.transcodingAudio = NO;
        
        if(self.transcodeOptions[kSynopsisTranscodeVideoSettingsKey] != [NSNull null])
        {
            self.videoTranscodeSettings = self.transcodeOptions[kSynopsisTranscodeVideoSettingsKey];
            self.transcodingVideo = YES;
            
            // See if our encode target is a HAP codec
            if(self.videoTranscodeSettings[AVVideoCodecKey])
            {
                NSString* codecFourCC = self.videoTranscodeSettings[AVVideoCodecKey];
                if([codecFourCC containsString:@"Hap"])
                {
                    self.encodeHAP = YES;
                }
            }
        }
        
        if(self.transcodeOptions[kSynopsisTranscodeAudioSettingsKey] != [NSNull null])
        {
            self.audioTranscodeSettings = self.transcodeOptions[kSynopsisTranscodeAudioSettingsKey];
            self.transcodingAudio = YES;
        }
        
        assert(self.transcodeOptions[kSynopsisAnalysisSettingsKey]);

        NSDictionary* analysisOptions = self.transcodeOptions[kSynopsisAnalysisSettingsKey];
        self.requestedAnalyzers = analysisOptions[kSynopsisAnalysisSettingsEnabledPluginsKey];
        self.analysisQualityHint = [analysisOptions[kSynopsisAnalysisSettingsQualityHintKey] unsignedIntegerValue];
        
        self.inFlightGlobalMetadata = [NSMutableDictionary new];
        self.inFlightVideoSampleBufferMetadata = [NSMutableArray new];
        self.inFlightAudioSampleBufferMetadata = [NSMutableArray new];
        
#pragma mark - Video Requirements

        CMItemCount numBuffers = 0;
        
        // since we are using passthrough - we have to ensure we use DTS not PTS since buffers may be out of order.
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &videoPassthroughBufferQueue);
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForSampleBuffersSortedByOutputPTS(), &videoUncompressedBufferQueue);
        
        self.videoPassthroughDecodeQueue = [[NSOperationQueue alloc] init];
        self.videoPassthroughDecodeQueue.maxConcurrentOperationCount = 1;
        
        self.videoPassthroughEncodeQueue = dispatch_queue_create("videoPassthroughEncodeQueue", DISPATCH_QUEUE_SERIAL);
        
        // We always need to decode uncompressed frames to send to our analysis plugins
        self.videoUncompressedDecodeQueue = [[NSOperationQueue alloc] init];
        self.videoUncompressedDecodeQueue.maxConcurrentOperationCount = 1;
        
        // Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
        self.videoDequeueSemaphore = dispatch_semaphore_create(0);
        
        // Number of simultaneous Jobs:
        BOOL concurrentFrames = [[[NSUserDefaults standardUserDefaults] objectForKey:kSynopsisAnalyzerConcurrentFrameAnalysisPreferencesKey] boolValue];
        
        self.concurrentVideoAnalysisQueue = [[NSOperationQueue alloc] init];
        self.concurrentVideoAnalysisQueue.maxConcurrentOperationCount = (concurrentFrames) ? NSOperationQueueDefaultMaxConcurrentOperationCount : 1;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(concurrentFramesDidChange:) name:kSynopsisAnalyzerConcurrentFrameAnalysisDidChangeNotification object:nil];
        
        self.videoTransformQueue = [[NSOperationQueue alloc] init];
        self.videoTransformQueue.maxConcurrentOperationCount = 1;

        self.jsonEncodeQueue = [[NSOperationQueue alloc] init];
        self.jsonEncodeQueue.maxConcurrentOperationCount = 1;
        
//        self.metadataEncoder = [[SynopsisMetadataEncoder alloc] initWithVersion:kSynopsisMetadataVersionValue];
    }
    return self;
}

- (NSString*) description
{
    return [NSString stringWithFormat:@"Transcode Operation: %p, Source: %@, Destination: %@, options: %@", self, self.sourceURL, self.destinationURL, self.transcodeOptions];
}

- (void) main
{
    // Initialize an array of available analyzers from our analyzer class names
    NSMutableArray* initializedAnalyzers = [NSMutableArray new];
    for(NSString* analyzerClassNameString in self.requestedAnalyzers)
    {
        Class pluginClass = NSClassFromString(analyzerClassNameString);
        id<AnalyzerPluginProtocol> pluginInstance = [[pluginClass alloc] init];
        
        if([[pluginInstance pluginMediaType] isEqualToString:AVMediaTypeVideo])
        {
            pluginInstance.successLog = ^void(NSString* log){[[LogController sharedLogController] appendSuccessLog:log];};
            pluginInstance.warningLog = ^void(NSString* log){[[LogController sharedLogController] appendWarningLog:log];};
            pluginInstance.verboseLog = ^void(NSString* log){[[LogController sharedLogController] appendVerboseLog:log];};
            pluginInstance.errorLog = ^void(NSString* log){[[LogController sharedLogController] appendErrorLog:log];};
            
            [initializedAnalyzers addObject:pluginInstance];
        }
        else
        {
            NSLog(@"%@ incompatible with analysis type - not using", analyzerClassNameString);
            pluginInstance = nil;
        }
    }
    
    self.availableAnalyzers = initializedAnalyzers;

    NSError* error = nil;
    
    if([self setupTranscode:&error])
    {
        [self transcodeAndAnalyzeAsset];
        [super main];
    }
    else
    {
        self.succeeded = NO;
        self.error = error;
        [[LogController sharedLogController] appendWarningLog:[NSString stringWithFormat:@"Analysis Operation for %@, failed with error: %@", [self.sourceURL lastPathComponent], error]];

        [self cancel];
    }
}

- (void) cancel
{
    [super cancel];

    [self.videoPassthroughDecodeQueue cancelAllOperations];
    [self.videoUncompressedDecodeQueue cancelAllOperations];
    [self.concurrentVideoAnalysisQueue cancelAllOperations];
    [self.jsonEncodeQueue cancelAllOperations];
    [self.videoTransformQueue cancelAllOperations];
}

- (BOOL) setupTranscode:(NSError * __autoreleasing *)error
{
    CGAffineTransform prefferedTrackTransform = CGAffineTransformIdentity;
    CGSize nativeSize = CGSizeZero;
    
    self.transcodeAsset = [AVURLAsset URLAssetWithURL:self.sourceURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @TRUE}];
    
    BOOL readable = self.transcodeAsset.readable;
    if(!readable)
    {
        if(error)
        {
            NSDictionary<NSErrorUserInfoKey, id>* errorInfo = @{
                                                                NSLocalizedDescriptionKey : @"Unable to read asset file",
                                                                };
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:errorInfo];
        }
        return NO;
    }
    
    self.transcodeAssetHasVideo = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual].count ? YES : NO;
    self.transcodeAssetHasAudio = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicAudible].count ? YES : NO;
    
    // Readers
    self.transcodeAssetReader = [AVAssetReader assetReaderWithAsset:self.transcodeAsset error:error];
    
    // Video Reader -
    if(self.transcodeAssetHasVideo)
    {
        self.decodeHAP = [self.transcodeAsset containsHapVideoTrack];
        
        AVAssetTrack* firstVideoTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual][0];
        
        // read our CMFormatDescription from our video track
        // use that to determine what video color properties we should set for output to decode to linear
        if(firstVideoTrack.formatDescriptions.count > 0)
        {
//            CMVideoFormatDescriptionRef videoFormat = (__bridge CMVideoFormatDescriptionRef)(firstVideoTrack.formatDescriptions[0]);
            
            
        }
        NSDictionary* HDProperties =  @{AVVideoColorPrimariesKey : AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey : AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey : AVVideoYCbCrMatrix_ITU_R_709_2 };

        NSDictionary* SDProperties =  @{AVVideoColorPrimariesKey : AVVideoColorPrimaries_SMPTE_C, AVVideoTransferFunctionKey : AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey : AVVideoYCbCrMatrix_ITU_R_601_4 };

        if(self.decodeHAP)
        {
            self.transcodeAssetReaderVideo = [[AVAssetReaderHapTrackOutput alloc] initWithTrack:firstVideoTrack outputSettings:@{(NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
//                                                                                                                                 AVVideoColorPropertiesKey : HDProperties
                                                                                                                                }];
        }
        else
        {
            self.transcodeAssetReaderVideo = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack
                                                                                        outputSettings:@{(NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
//                                                                                                         AVVideoColorPropertiesKey : HDProperties
                                                                                                         }];
        }
        self.transcodeAssetReaderVideo.alwaysCopiesSampleData = NO;
        prefferedTrackTransform = firstVideoTrack.preferredTransform;
        nativeSize = firstVideoTrack.naturalSize;
        
        // Do we use passthrough?
        if(!self.transcodingVideo)
        {
            self.transcodeAssetReaderVideoPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack outputSettings:nil];
            self.transcodeAssetReaderVideoPassthrough.alwaysCopiesSampleData = NO;
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

        unsigned int numberOfChannels = 0;
        
        if(layout != NULL)
        {
            numberOfChannels = AudioChannelLayoutTag_GetNumberOfChannels(layout->mChannelLayoutTag);
        }
        
        // Looks like we need to get an ASBD instead
        
        const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription);
        
        if(asbd != NULL)
        {
            numberOfChannels = asbd->mChannelsPerFrame;
        }
        
        if(self.audioTranscodeSettings[AVNumberOfChannelsKey] == [NSNull null])
        {
            NSMutableDictionary* newAudioSettingsWithChannelCountAndLayout = [self.audioTranscodeSettings mutableCopy];
            
            if(layout != nil)
            {
                NSData* audioLayoutData = [[NSData alloc] initWithBytes:layout length:layoutSize];
                newAudioSettingsWithChannelCountAndLayout[AVChannelLayoutKey] = audioLayoutData;
            }
            
            newAudioSettingsWithChannelCountAndLayout[AVNumberOfChannelsKey] = @(numberOfChannels);
            
            self.audioTranscodeSettings = newAudioSettingsWithChannelCountAndLayout;
        }
        
        self.transcodeAssetReaderAudio = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstAudioTrack
                                                                                outputSettings:@{(NSString*) AVFormatIDKey : @(kAudioFormatLinearPCM)}];
        self.transcodeAssetReaderAudio.alwaysCopiesSampleData = NO;
        
        if(!self.transcodingAudio)
        {
            self.transcodeAssetReaderAudioPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstAudioTrack outputSettings:nil];
            self.transcodeAssetReaderAudioPassthrough.alwaysCopiesSampleData = NO;
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
    
    // check if we need to use our natural size - we might not have AVVideoHeightKey or AVVideoWidthKey
    if(!self.videoTranscodeSettings[AVVideoHeightKey] || !self.videoTranscodeSettings[AVVideoWidthKey])
    {
        NSMutableDictionary* newVideoSettings = [self.videoTranscodeSettings mutableCopy];
        newVideoSettings[AVVideoHeightKey] = @(nativeSize.height);
        newVideoSettings[AVVideoWidthKey] = @(nativeSize.width);
        
        self.videoTranscodeSettings = newVideoSettings;
    }
    
    // Writers
    self.transcodeAssetWriter = [AVAssetWriter assetWriterWithURL:self.destinationURL fileType:AVFileTypeQuickTimeMovie error:error];
    
    if(self.encodeHAP)
    {
        self.transcodeAssetWriterVideo = [[AVAssetWriterHapInput alloc] initWithOutputSettings:self.videoTranscodeSettings];
    }
    else
    {
        self.transcodeAssetWriterVideo = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:self.videoTranscodeSettings];
    }
        
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
        [analyzer beginMetadataAnalysisSessionWithQuality:self.analysisQualityHint];
    }
    
    if(*error)
        return NO;

    return YES;
}


- (void) transcodeAndAnalyzeAsset
{
    CGFloat assetDurationInSeconds = CMTimeGetSeconds(self.transcodeAsset.duration);
    
    if([self.transcodeAssetWriter startWriting] && [self.transcodeAssetReader startReading] && !self.isCancelled)
    {
        [self.transcodeAssetWriter startSessionAtSourceTime:kCMTimeZero];
    
        // We need a dispatch group since we have to wrangle multiple queues successfully.
        // Signal both audio and video are done within this task
        dispatch_group_t g = dispatch_group_create();

        // 0 = use as much as you want.
        // Probably want to throttle this and set a small usleep to keep threads happy
        // Or use the CMBufferqueue callbacks with a semaphore signal
        CMItemCount numBuffers = 0;
        

        if(self.transcodeAssetHasVideo)
        {
            dispatch_group_enter(g);
            dispatch_group_enter(g);
            dispatch_group_enter(g);
        }
        
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
        
//        dispatch_queue_t concurrentAudioAnalysisQueue = dispatch_queue_create("concurrentAudioAnalysisQueue", DISPATCH_QUEUE_CONCURRENT);

#pragma mark - Read Video pass through

        __block AtomicBoolean *finishedReadingAllPassthroughVideo = [[AtomicBoolean alloc] init];;
        
        if(self.transcodeAssetHasVideo)
        {
            // Passthrough Video Read into our Buffer Queue
            [self.videoPassthroughDecodeQueue addOperationWithBlock: ^{
                
                // read sample buffers from our video reader - and append them to the queue.
                // only read while we have samples, and while our buffer queue isnt full
                
                [[LogController sharedLogController] appendVerboseLog:@"Begun Passthrough Video"];
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading && !self.isCancelled)
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
                                dispatch_semaphore_signal(self.videoDequeueSemaphore);
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
                
                [finishedReadingAllPassthroughVideo setValue:YES];

                [[LogController sharedLogController] appendVerboseLog:@"Finished Passthrough Video Buffers"];

                // Fire final semaphore signal to hit finalization
                dispatch_semaphore_signal(self.videoDequeueSemaphore);

                dispatch_group_leave(g);
            }];
        }
        
#pragma mark - Read Audio pass through
        
        __block AtomicBoolean* finishedReadingAllPassthroughAudio = [[AtomicBoolean alloc] init];

        if(self.transcodeAssetHasAudio)
        {
            // Passthrough Video Read into our Buffer Queue
            dispatch_async(audioPassthroughDecodeQueue, ^{
                
                // read sample buffers from our video reader - and append them to the queue.
                // only read while we have samples, and while our buffer queue isnt full
                
                [[LogController sharedLogController] appendVerboseLog:@"Begun Passthrough Audio"];
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading && !self.isCancelled)
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
                
                [finishedReadingAllPassthroughAudio setValue:YES];
                
                [[LogController sharedLogController] appendSuccessLog:@"Finished Passthrough Audio Buffers"];
                
                // Fire final semaphore signal to hit finalization
                dispatch_semaphore_signal(audioDequeueSemaphore);
                
                dispatch_group_leave(g);
            });
        }
        
#pragma mark - Read Video Decompressed
        
        // TODO : look at SampleTimingInfo Struct to better get a handle on this shit.
        __block AtomicBoolean* finishedReadingAllUncompressedVideo = [[AtomicBoolean alloc] init];
        
        if(self.transcodeAssetHasVideo)
        {
            [self.videoUncompressedDecodeQueue addOperationWithBlock: ^{
                
                [[LogController sharedLogController] appendVerboseLog:@"Begun Decompressing Video"];
                
                BOOL hapGotFirstZerothFrameHack = NO;
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading && !self.isCancelled)
                {
                    @autoreleasepool
                    {
                        CMSampleBufferRef uncompressedVideoSampleBuffer = [self.transcodeAssetReaderVideo copyNextSampleBuffer];
                        if(uncompressedVideoSampleBuffer)
                        {
                            if(self.decodeHAP)
                            {
                                // Seems like on some HAP encoders, we get duplicate frames marked kCMTimeZero?
                                // the Hap video track output bails if thats the case
                                // so I've commented out that code (maybe thats a horrible idea?)
                                // But this appears to allow us to decode HAP to other formats + analyze
                                CMTime sampleTime = CMSampleBufferGetPresentationTimeStamp(uncompressedVideoSampleBuffer);
                                if(CMTIME_COMPARE_INLINE(kCMTimeZero, ==, sampleTime) &&  !hapGotFirstZerothFrameHack)
                                {
                                    hapGotFirstZerothFrameHack = YES;
                                    CFRelease(uncompressedVideoSampleBuffer);
                                    continue;
                                }
                            }
                            
                            // Only add to our uncompressed buffer queue if we are going to use those buffers on the encoder end.
                            if(self.transcodingVideo)
                            {
                                CMBufferQueueEnqueue(videoUncompressedBufferQueue, uncompressedVideoSampleBuffer);
                                // Free to dequeue on other thread
                                dispatch_semaphore_signal(self.videoDequeueSemaphore);
                            }

                            CMTime currentSamplePTS = CMSampleBufferGetOutputPresentationTimeStamp(uncompressedVideoSampleBuffer);
                            CMTime currentSampleDuration = CMSampleBufferGetOutputDuration(uncompressedVideoSampleBuffer);
                            CMTimeRange currentSampleTimeRange = CMTimeRangeMake(currentSamplePTS, currentSampleDuration);
                            CGFloat currentPresetnationTimeInSeconds = CMTimeGetSeconds(currentSamplePTS);

                            NSLock* dictionaryLock = [[NSLock alloc] init];
                            
                            NSMutableDictionary* aggregatedAndAnalyzedMetadata = [NSMutableDictionary new];

                            // grab our image buffer
                            CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(uncompressedVideoSampleBuffer);
                            
                            assert( kCVPixelFormatType_32BGRA == CVPixelBufferGetPixelFormatType(pixelBuffer));
                            
                            CGRect originalRect = CGRectMake(0, 0, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
                            
//                            dont vend a pixel buffer, vend an object that has cached format variants for our plugins to use.
                            NSOperation* transformOperation = [self.videoHelper pixelBuffer:pixelBuffer
                                                                              withTransform:self.transcodeAssetWriterVideo.transform
                                                                                       rect:rectForQualityHint(originalRect, self.analysisQualityHint)
                                                                            completionBlock:^(SynopsisVideoFormatConverter* converter, NSError * error){
                                              
                                              CFRelease(uncompressedVideoSampleBuffer);
                                                                                
                                              // Run an analysis pass on each plugin
                                              NSMutableArray* analysisOperations = [NSMutableArray array];
                                              
                                              for(id<AnalyzerPluginProtocol> analyzer in self.availableAnalyzers)
                                              {
                                                  NSBlockOperation* operation = [NSBlockOperation blockOperationWithBlock: ^{
                                                      
                                                      NSString* newMetadataKey = [analyzer pluginIdentifier];
                                                      
                                                      [analyzer analyzeCurrentCVPixelBufferRef:converter
                                                                             completionHandler:^(NSDictionary * newMetadataValue, NSError *analyzerError) {
                                                                                 if(analyzerError)
                                                                                 {
                                                                                     NSString* errorString = [@"Error Analyzing Sample buffer: " stringByAppendingString:[analyzerError description]];
                                                                                     [[LogController sharedLogController] appendErrorLog:errorString];
                                                                                 }
                                                                                 
                                                                                 if(newMetadataValue)
                                                                                 {
                                                                                     // provide some thread safety to our now async fetches.
                                                                                     [dictionaryLock lock];
                                                                                     [aggregatedAndAnalyzedMetadata setObject:newMetadataValue forKey:newMetadataKey];
                                                                                     [dictionaryLock unlock];
                                                                                 }
                                                                             }];
                                                  }];
                                                  
                                                  [analysisOperations addObject:operation];
                                              }
                                              
                                              NSBlockOperation* jsonEncodeOperation = [NSBlockOperation blockOperationWithBlock: ^{
                                                  
                                                  // Store out running metadata
//                                                  AVTimedMetadataGroup *group = [self.metadataEncoder encodeSynopsisMetadataToTimesMetadataGroup:aggregatedAndAnalyzedMetadata timeRange:currentSampleTimeRange];
//                                                  if(group)
                                                  {
                                                      NSValue* timeRangeValue = [NSValue valueWithCMTimeRange:currentSampleTimeRange];
                                                      NSDictionary* metadata = @{@"TimeRange" : timeRangeValue,
                                                                                 @"Metadata" : aggregatedAndAnalyzedMetadata
                                                                                 };
                                                      
                                                      [self.inFlightVideoSampleBufferMetadata addObject:metadata];
                                                  }
//                                                  else
//                                                  {
//                                                      [[LogController sharedLogController] appendErrorLog:@"Unable To Convert Metadata to JSON Format, invalid object"];
//                                                  }
                                                  
                                                  self.videoProgress = currentPresetnationTimeInSeconds / assetDurationInSeconds;
                                              }];
                                              
                                              for(NSOperation* analysisOperation in analysisOperations)
                                              {
                                                  [jsonEncodeOperation addDependency:analysisOperation];
                                              }
                                              
                                              [self.concurrentVideoAnalysisQueue addOperations:analysisOperations waitUntilFinished:YES];
                                              [self.jsonEncodeQueue addOperation:jsonEncodeOperation];
                                }];
                            

                            [self.videoTransformQueue addOperations:@[transformOperation] waitUntilFinished:YES];
                            
                        }
                        else
                        {
                            // Got NULL - were done
                            // Todo: Move Analysis Finalization here
                            break;
                        }
                    }
                }

                [finishedReadingAllUncompressedVideo setValue:YES];

                [[LogController sharedLogController] appendVerboseLog:@"Finished Reading Uncompressed Video Buffers"];
                
                // Fire final semaphore signal to hit finalization
                dispatch_semaphore_signal(self.videoDequeueSemaphore);

                dispatch_group_leave(g);
            }];
        }
        
#pragma mark - Read Audio Decompressed
        
        // TODO : look at SampleTimingInfo Struct to better get a handle on this shit.
        __block AtomicBoolean* finishedReadingAllUncompressedAudio = [[AtomicBoolean alloc] init];
        
        if(self.transcodeAssetHasAudio)
        {
            dispatch_async(audioUncompressedDecodeQueue, ^{
            
            [[LogController sharedLogController] appendVerboseLog:@"Begun Decompressing Audio"];
            
            while(self.transcodeAssetReader.status == AVAssetReaderStatusReading && !self.isCancelled)
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
//                        CMTime currentSampleDuration = CMSampleBufferGetOutputDuration(uncompressedAudioSampleBuffer);
//                        CMTimeRange currentSampleTimeRange = CMTimeRangeMake(currentSamplePTS, currentSampleDuration);
                        
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
            
                [finishedReadingAllUncompressedAudio setValue:YES];
            
            [[LogController sharedLogController] appendSuccessLog:@"Finished Reading Uncompressed Audio Buffers"];
            
            // Fire final semaphore signal to hit finalization
            dispatch_semaphore_signal(audioDequeueSemaphore);
            
            dispatch_group_leave(g);
        });
        }
        
#pragma mark - Write Video (Pass through or Encoded)
        
        if(self.transcodeAssetHasVideo)
        {
            [self.transcodeAssetWriterVideo requestMediaDataWhenReadyOnQueue:self.videoPassthroughEncodeQueue usingBlock:^
            {
                [[LogController sharedLogController] appendVerboseLog:@"Begun Writing Video"];
                
                while([self.transcodeAssetWriterVideo isReadyForMoreMediaData] )
                {
                    // Are we done reading,
                    if( ([finishedReadingAllPassthroughVideo getValue] && [finishedReadingAllUncompressedVideo getValue]) || self.isCancelled)
                    {
//                        NSLog(@"Finished Reading waiting to empty queue...");
                        dispatch_semaphore_signal(self.videoDequeueSemaphore);

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
                                    NSString* warning = [@"No Global Analysis Data for Analyzer " stringByAppendingString:analyzer.pluginIdentifier];
                                    [[LogController sharedLogController] appendWarningLog:warning];
                                }
                            }
                        
                            self.inFlightGlobalMetadata[kSynopsisMetadataVersionKey] = @(kSynopsisMetadataVersionValue);
                            
                            [self.transcodeAssetWriterVideo markAsFinished];
                            
                            [[LogController sharedLogController] appendVerboseLog:@"Finished Writing Video"];

                            dispatch_group_leave(g);
                            break;
                        }
                    }
                    
                    CMSampleBufferRef videoSampleBuffer = NULL;

                    // wait to dequeue until we have an enqueued buffer / signal from our enqueue thread.
                    dispatch_semaphore_wait(self.videoDequeueSemaphore, DISPATCH_TIME_FOREVER);

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
                if( ([finishedReadingAllPassthroughVideo getValue] && [finishedReadingAllUncompressedVideo getValue]) || self.isCancelled)
                {
                    if(!CMBufferQueueIsEmpty(videoPassthroughBufferQueue) || !CMBufferQueueIsEmpty(videoUncompressedBufferQueue))
                    {
                        [[LogController sharedLogController] appendVerboseLog:@"Stopped Requesting Destination Video but did not empty Source Queues"];
                    }
                }
                else
                {
                    [[LogController sharedLogController] appendVerboseLog:@"Stopped Requesting Destination Video but did not finish reading Source Video"];
                    
                    if(!CMBufferQueueIsEmpty(videoPassthroughBufferQueue) || !CMBufferQueueIsEmpty(videoUncompressedBufferQueue))
                    {
                        [[LogController sharedLogController] appendVerboseLog:@"Stopped Requesting Destination Video but did not empty Source Queues"];
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
                     if( ([finishedReadingAllPassthroughAudio getValue] && [finishedReadingAllUncompressedAudio getValue]) || self.isCancelled)
                     {
//                         NSLog(@"Finished Reading waiting to empty queue...");
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
                 if( ([finishedReadingAllPassthroughAudio getValue] && [finishedReadingAllUncompressedAudio getValue]) || self.isCancelled)
                 {
                     if(!CMBufferQueueIsEmpty(audioPassthroughBufferQueue) || !CMBufferQueueIsEmpty(audioUncompressedBufferQueue))
                     {
                         [[LogController sharedLogController] appendVerboseLog:@"Stopped Requesting Destination Audio but did not empty Source Queues"];
                     }
                 }
                 else
                 {
                     [[LogController sharedLogController] appendVerboseLog:@"Stopped Requesting Destination Audio but did not finish reading Source Video"];
                     
                     if(!CMBufferQueueIsEmpty(audioPassthroughBufferQueue) || !CMBufferQueueIsEmpty(audioUncompressedBufferQueue))
                     {
                         [[LogController sharedLogController] appendVerboseLog:@"Stopped Requesting Destination Audio but did not empty Source Queues"];
                     }
                 }
             }];
        }
        
#pragma mark - Cleanup
        
        [self.videoPassthroughDecodeQueue waitUntilAllOperationsAreFinished];
        [self.videoUncompressedDecodeQueue waitUntilAllOperationsAreFinished];
        [self.concurrentVideoAnalysisQueue waitUntilAllOperationsAreFinished];
        [self.jsonEncodeQueue waitUntilAllOperationsAreFinished];
        [self.videoTransformQueue waitUntilAllOperationsAreFinished];
        
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
		
		self.succeeded = YES;
        [[LogController sharedLogController] appendVerboseLog:[@"Finished Pass 1 Operation for " stringByAppendingString:[self.destinationURL lastPathComponent]]];
    }
    else
    {
        [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Unable to start transcode from %@ to %@:", self.sourceURL, self.destinationURL]];
        if(self.transcodeAssetReader.error)
        {
            [[LogController sharedLogController] appendErrorLog:[@"Read Error" stringByAppendingString:self.transcodeAssetReader.error.debugDescription]];
        }
        if(self.transcodeAssetWriter.error)
        {
            [[LogController sharedLogController] appendErrorLog:[@"Write Error" stringByAppendingString:self.transcodeAssetWriter.error.debugDescription]];
        }
		self.succeeded = NO;
    }
}


#pragma mark - CVPixelBuffer Transform and scale helper

#define SynopsisvImageTileFlag kvImageNoFlags
//#define SynopsisvImageTileFlag kvImageDoNotTile

//static const CGRect lowQuality = (CGRect) { 0, 0, 80, 60 };
static const CGRect lowQuality = (CGRect) { 0, 0, 160, 120 };
static const CGRect mediumQuality = (CGRect) { 0, 0, 320, 240 };
static const CGRect highQuality = (CGRect) { 0, 0, 640, 480 };

static inline CGRect rectForQualityHint(CGRect originalRect, SynopsisAnalysisQualityHint quality)
{
    switch (quality)
    {
        case SynopsisAnalysisQualityHintLow:
        {
            return AVMakeRectWithAspectRatioInsideRect(originalRect.size, lowQuality);
            break;
        }
        case SynopsisAnalysisQualityHintMedium:
        {
            return AVMakeRectWithAspectRatioInsideRect(originalRect.size, mediumQuality);
            break;
        }
        case SynopsisAnalysisQualityHintHigh:
        {
            return AVMakeRectWithAspectRatioInsideRect(originalRect.size, highQuality);
            break;
        }
        case SynopsisAnalysisQualityHintOriginal:
            return originalRect;
            break;
    }

}

#pragma mark - Notification

- (void) concurrentFramesDidChange:(NSNotification*)notification
{
    // Number of simultaneous Jobs:
    BOOL concurrentFrames = [[[NSUserDefaults standardUserDefaults] objectForKey:kSynopsisAnalyzerConcurrentFrameAnalysisPreferencesKey] boolValue];
    
    // Serial transcode queue
    self.concurrentVideoAnalysisQueue.maxConcurrentOperationCount = (concurrentFrames) ? NSOperationQueueDefaultMaxConcurrentOperationCount : 1;
}



@end
