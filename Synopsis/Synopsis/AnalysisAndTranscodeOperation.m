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
#import <Accelerate/Accelerate.h>

#import "AnalyzerPluginProtocol.h"

#import "NSDictionary+JSONString.h"
#import "BSON/BSONSerialization.h"
#import "GZIP/GZIP.h"

@interface AnalysisAndTranscodeOperation ()
{
    // We use this pixel buffer pool to handle memory for our resized pixel buffers
    CVPixelBufferPoolRef transformPixelBufferPool;
    CVPixelBufferPoolRef scaledPixelBufferPool;
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

@property (atomic, readwrite, strong) NSArray* requestedAnalyzers;

@end

@implementation AnalysisAndTranscodeOperation


- (instancetype) initWithSourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL transcodeOptions:(NSDictionary*)transcodeOptions availableAnalyzers:(NSArray*)analyzers
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
        
        self.requestedAnalyzers = analyzers;
        
        self.inFlightGlobalMetadata = [NSMutableDictionary new];
        self.inFlightVideoSampleBufferMetadata = [NSMutableArray new];
        self.inFlightAudioSampleBufferMetadata = [NSMutableArray new];
        
        // Lazy init of our pixel buffers once we know our target size
        // See pixelBuffer:withTransform:forQuality:
        transformPixelBufferPool = NULL;
        scaledPixelBufferPool = NULL;
        
    }
    return self;
}

- (void) dealloc
{
    if(transformPixelBufferPool != NULL)
    {
        CVPixelBufferPoolRelease(transformPixelBufferPool);
        transformPixelBufferPool = NULL;
    }
    
    if(scaledPixelBufferPool != NULL)
    {
        CVPixelBufferPoolRelease(scaledPixelBufferPool);
        scaledPixelBufferPool = NULL;
    }
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
            [initializedAnalyzers addObject:pluginInstance];
        }
        else
        {
            NSLog(@"%@ incompatible with analysis type - not using", analyzerClassNameString);
            pluginInstance = nil;
        }
    }
    
    self.availableAnalyzers = initializedAnalyzers;

    [self setupTranscodeShitSucessfullyOrDontWhatverMan];

    [self transcodeAndAnalyzeAsset];

    [super main];
}


- (NSError*) setupTranscodeShitSucessfullyOrDontWhatverMan
{
    CGAffineTransform prefferedTrackTransform = CGAffineTransformIdentity;
    CGSize nativeSize = CGSizeZero;
    
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
        
        NSDictionary* HDProperties =  @{AVVideoColorPrimariesKey : AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey : AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey : AVVideoYCbCrMatrix_ITU_R_709_2 };

        NSDictionary* SDProperties =  @{AVVideoColorPrimariesKey : AVVideoColorPrimaries_SMPTE_C, AVVideoTransferFunctionKey : AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey : AVVideoYCbCrMatrix_ITU_R_601_4 };

        self.transcodeAssetReaderVideo = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack
                                                                                    outputSettings:@{(NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
//                                                                                                     AVVideoColorPropertiesKey : HDProperties
                                                                                                     }];
        
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
        [analyzer beginMetadataAnalysisSessionWithQuality:SynopsisAnalysisQualityHintMedium];
    }
    
    return error;
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
        
#pragma mark - Video Requirements
        
        // Decode and Encode Queues - each pair writes or reads to a CMBufferQueue
        CMBufferQueueRef videoPassthroughBufferQueue;
        // since we are using passthrough - we have to ensure we use DTS not PTS since buffers may be out of order.
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &videoPassthroughBufferQueue);

        CMBufferQueueRef videoUncompressedBufferQueue;
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForSampleBuffersSortedByOutputPTS(), &videoUncompressedBufferQueue);

        dispatch_queue_t videoPassthroughDecodeQueue = dispatch_queue_create("videoPassthrougDecodeQueue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        dispatch_queue_t videoPassthroughEncodeQueue = dispatch_queue_create("videoPassthroughEncodeQueue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        // We always need to decode uncompressed frames to send to our analysis plugins
        dispatch_queue_t videoUncompressedDecodeQueue = dispatch_queue_create("videoUncompressedDecodeQueue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        // Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
        dispatch_semaphore_t videoDequeueSemaphore = dispatch_semaphore_create(0);
        
        dispatch_queue_t concurrentVideoAnalysisQueue = dispatch_queue_create("concurrentVideoAnalysisQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        
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
        dispatch_queue_t audioUncompressedDecodeQueue = dispatch_queue_create("audioUncompressedDecodeQueue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        if(self.transcodeAssetHasAudio)
            dispatch_group_enter(g);
        
        // Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
        dispatch_semaphore_t audioDequeueSemaphore = dispatch_semaphore_create(0);
        
//        dispatch_queue_t concurrentAudioAnalysisQueue = dispatch_queue_create("concurrentAudioAnalysisQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);

#pragma mark - Read Video pass through

        __block BOOL finishedReadingAllPassthroughVideo = NO;
        
        if(self.transcodeAssetHasVideo)
        {
            // Passthrough Video Read into our Buffer Queue
            dispatch_async(videoPassthroughDecodeQueue, ^{
                
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
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading && !self.isCancelled)
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

                            // grab our image buffer
                            CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(uncompressedVideoSampleBuffer);
                            
                            CVPixelBufferRetain(pixelBuffer);
                            
                            assert( kCVPixelFormatType_32BGRA == CVPixelBufferGetPixelFormatType(pixelBuffer));
                            
                            // resize and transform it to match expected raster
                            CVPixelBufferRef transformedPixelBuffer = [self createPixelBuffer:pixelBuffer withTransform:self.transcodeAssetWriterVideo.transform forQuality:SynopsisAnalysisQualityHintMedium];
                            
                            CVPixelBufferLockBaseAddress(transformedPixelBuffer, kCVPixelBufferLock_ReadOnly);
                            
                            // Run an analysis pass on each plugin
                            for(id<AnalyzerPluginProtocol> analyzer in self.availableAnalyzers)
                            {
                                
                                [analyzer submitAndCacheCurrentVideoBuffer:CVPixelBufferGetBaseAddress(transformedPixelBuffer)
                                                                     width:CVPixelBufferGetWidth(transformedPixelBuffer)
                                                                    height:CVPixelBufferGetHeight(transformedPixelBuffer)
                                                               bytesPerRow:CVPixelBufferGetBytesPerRow(transformedPixelBuffer)];

                                // enter our group.
                                if([analyzer hasModules])
                                {
                                    // dont overwrite the keys. we have one entry for the  plugin, and then many entries for the ley
                                    NSString* newMetadataKey = [analyzer pluginIdentifier];
                                    NSMutableDictionary* newMetadataValue = [NSMutableDictionary new];
                                    
                                    for(NSInteger moduleIndex = 0; moduleIndex < [analyzer moduleClasses].count; moduleIndex++)
                                    {
                                        // enter our group.
                                        dispatch_group_enter(analysisGroup);
                                        
                                        
                                        // dispatch a single module
                                        dispatch_async(concurrentVideoAnalysisQueue, ^{
                                            
                                            NSDictionary* newModuleValue = [analyzer analyzeMetadataDictionaryForModuleIndex:moduleIndex
                                                                                                                       error:&analyzerError];
                                            
                                            if(analyzerError)
                                            {
                                                NSString* errorString = [@"Error Analyzing Sample buffer: " stringByAppendingString:[analyzerError description]];
                                                [[LogController sharedLogController] appendErrorLog:errorString];
                                            }
                                            
                                            [dictionaryLock lock];
                                            [newMetadataValue addEntriesFromDictionary:newModuleValue];
                                            [dictionaryLock unlock];
                                            
                                            dispatch_group_leave(analysisGroup);
                                        });
                                    }
                                    
                                    if(newMetadataValue)
                                    {
                                        // provide some thread safety to our now async fetches.
                                        [dictionaryLock lock];
                                        [aggregatedAndAnalyzedMetadata setObject:newMetadataValue forKey:newMetadataKey];
                                        [dictionaryLock unlock];
                                    }
                                    
                                }
                                
                                // otherwise we dispatch once and run the
                                else
                                {
                                    // enter our group.
                                    dispatch_group_enter(analysisGroup);
                                    
                                    dispatch_async(concurrentVideoAnalysisQueue, ^{
                                        
                                        NSString* newMetadataKey = [analyzer pluginIdentifier];
                                        NSDictionary* newMetadataValue = [analyzer analyzeMetadataDictionaryForModuleIndex:SynopsisModuleIndexNone
                                                                                                                   error:&analyzerError];
                                        
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
                                        
                                        dispatch_group_leave(analysisGroup);
                                    });
                                }
                                
                                dispatch_group_wait(analysisGroup, DISPATCH_TIME_FOREVER);
                                
                                // if we had an analyzer error, bail.
                                if(analyzerError)
                                {
                                    break;
                                }
                            }
                            
                            CVPixelBufferUnlockBaseAddress(transformedPixelBuffer, kCVPixelBufferLock_ReadOnly);
                            CVPixelBufferRelease(transformedPixelBuffer);
                            CVPixelBufferRelease(pixelBuffer);

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
                
                while([self.transcodeAssetWriterVideo isReadyForMoreMediaData] )
                {
                    // Are we done reading,
                    if( (finishedReadingAllPassthroughVideo && finishedReadingAllUncompressedVideo) || self.isCancelled)
                    {
//                        NSLog(@"Finished Reading waiting to empty queue...");
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
                if( (finishedReadingAllPassthroughVideo && finishedReadingAllUncompressedVideo) || self.isCancelled)
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
                     if( (finishedReadingAllPassthroughAudio && finishedReadingAllUncompressedAudio) || self.isCancelled)
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
                 if( (finishedReadingAllPassthroughAudio && finishedReadingAllUncompressedAudio) || self.isCancelled)
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
        if(self.transcodeAssetReader.error)
        {
            [[LogController sharedLogController] appendErrorLog:[@"Read Error" stringByAppendingString:self.transcodeAssetReader.error.debugDescription]];
        }
        if(self.transcodeAssetWriter.error)
        {
            [[LogController sharedLogController] appendErrorLog:[@"Write Error" stringByAppendingString:self.transcodeAssetWriter.error.debugDescription]];
        }
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

- (CVPixelBufferRef) createScaledPixelBuffer:(CVPixelBufferRef)pixelBuffer forQuality:(SynopsisAnalysisQualityHint)quality
{
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    CGRect originalRect = {0, 0, width, height};

    CGRect resizeRect = rectForQualityHint(originalRect, quality);

    // Avoid half pixel values.
    resizeRect = CGRectIntegral(resizeRect);

    CGSize resizeSize = CGSizeZero;
    resizeSize = resizeRect.size;

    // Lazy Pixel Buffer Pool initialization
    // TODO: Our pixel buffer pool wont re-init if for some reason pixel buffer sizes change
    if(scaledPixelBufferPool == NULL)
    {
        NSDictionary* poolAttributes = @{ (NSString*)kCVPixelBufferWidthKey : @(resizeSize.width),
                                          (NSString*)kCVPixelBufferHeightKey : @(resizeSize.height),
                                          (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                          };
        CVReturn err = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef _Nullable)(poolAttributes), &scaledPixelBufferPool);
        if(err != kCVReturnSuccess)
        {
            NSLog(@"Error : %i", err);
        }
    }

    // Create our input vImage from our CVPixelBuffer
    CVPixelBufferLockBaseAddress(pixelBuffer,kCVPixelBufferLock_ReadOnly);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    vImage_Buffer inBuff;
    inBuff.height = CVPixelBufferGetHeight(pixelBuffer);
    inBuff.width = CVPixelBufferGetWidth(pixelBuffer);
    inBuff.rowBytes = bytesPerRow;
    inBuff.data = baseAddress;

    // Scale our transformmed buffer
    CVPixelBufferRef scaledBuffer;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, scaledPixelBufferPool, &scaledBuffer);
    
    CVPixelBufferLockBaseAddress(scaledBuffer, 0);
    unsigned char *resizedBytes = CVPixelBufferGetBaseAddress(scaledBuffer);
    
    vImage_Buffer resized = {resizedBytes, CVPixelBufferGetHeight(scaledBuffer), CVPixelBufferGetWidth(scaledBuffer), CVPixelBufferGetBytesPerRow(scaledBuffer)};
    //    err = vImageBuffer_InitWithCVPixelBuffer(&resized, &desiredFormat, scaledBuffer, NULL, backColorF, kvImageNoFlags);
    //    if (err != kvImageNoError)
    //        NSLog(@" error %ld", err);
    
    vImage_Error err = vImageScale_ARGB8888(&inBuff, &resized, NULL, SynopsisvImageTileFlag);
    if (err != kvImageNoError)
        NSLog(@" error %ld", err);

    
    // Free / unlock
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    inBuff.data = NULL; // explicit

    CVPixelBufferUnlockBaseAddress(scaledBuffer, 0);
    
    return scaledBuffer;
}

- (CVPixelBufferRef) createTransformedPixelBuffer:(CVPixelBufferRef)pixelBuffer withTransform:(CGAffineTransform)transform flip:(BOOL)flip
{
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    CGRect originalRect = {0, 0, width, height};
    
    CVPixelBufferLockBaseAddress(pixelBuffer,kCVPixelBufferLock_ReadOnly);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    vImage_Buffer inBuff;
    inBuff.height = CVPixelBufferGetHeight(pixelBuffer);
    inBuff.width = CVPixelBufferGetWidth(pixelBuffer);
    inBuff.rowBytes = bytesPerRow;
    inBuff.data = baseAddress;
    
    // Transform
    CGAffineTransform finalTransform = transform;
    if(flip)
    {
        CGRect flippedRect = CGRectApplyAffineTransform(originalRect, finalTransform);
        flippedRect = CGRectIntegral(flippedRect);
        
        CGAffineTransform flip = CGAffineTransformMakeTranslation(flippedRect.size.width * 0.5, flippedRect.size.height * 0.5);
        flip = CGAffineTransformScale(flip, 1, -1);
        flip = CGAffineTransformTranslate(flip, -flippedRect.size.width * 0.5, -flippedRect.size.height * 0.5);
        
        finalTransform = CGAffineTransformConcat(finalTransform, flip);
    }
    
    CGRect transformedRect = CGRectApplyAffineTransform(originalRect, finalTransform);
    
    vImage_CGAffineTransform finalAffineTransform;
    finalAffineTransform.a = finalTransform.a;
    finalAffineTransform.b = finalTransform.b;
    finalAffineTransform.c = finalTransform.c;
    finalAffineTransform.d = finalTransform.d;
    finalAffineTransform.tx = finalTransform.tx;
    finalAffineTransform.ty = finalTransform.ty;

    // Create our pixel buffer pool for our transformed size
    // TODO: Our pixel buffer pool wont re-init if for some reason pixel buffer sizes change
    if(transformPixelBufferPool == NULL)
    {
        NSDictionary* poolAttributes = @{ (NSString*)kCVPixelBufferWidthKey : @(transformedRect.size.width),
                                          (NSString*)kCVPixelBufferHeightKey : @(transformedRect.size.height),
                                          (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                          };
        CVReturn err = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef _Nullable)(poolAttributes), &transformPixelBufferPool);
        if(err != kCVReturnSuccess)
        {
            NSLog(@"Error : %i", err);
        }
    }

    CVPixelBufferRef transformedBuffer;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, transformPixelBufferPool, &transformedBuffer);
    
    CVPixelBufferLockBaseAddress(transformedBuffer, 0);
    unsigned char *transformBytes = CVPixelBufferGetBaseAddress(transformedBuffer);
    
    const uint8_t backColorU[4] = {0};
    
    //    vImage_CGImageFormat desiredFormat;
    //    desiredFormat.bitsPerComponent = 8;
    //    desiredFormat.bitsPerPixel = 32;
    //    desiredFormat.colorSpace = NULL;
    //    desiredFormat.bitmapInfo = (CGBitmapInfo)(kCGImageAlphaFirst | kCGImageAlphaPremultipliedFirst| kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    //    desiredFormat.version = 0;
    //    desiredFormat.decode = NULL;
    //    desiredFormat.renderingIntent = kCGRenderingIntentDefault;
    
    vImage_Buffer transformed = {transformBytes, CVPixelBufferGetHeight(transformedBuffer), CVPixelBufferGetWidth(transformedBuffer), CVPixelBufferGetBytesPerRow(transformedBuffer)};
    vImage_Error err;
    //    err = vImageBuffer_InitWithCVPixelBuffer(&transformed, &desiredFormat, transformedBuffer, NULL, backColorF, kvImageNoFlags);
    //    if (err != kvImageNoError)
    //        NSLog(@" error %ld", err);
    
    err = vImageAffineWarpCG_ARGB8888(&inBuff, &transformed, NULL, &finalAffineTransform, backColorU, kvImageLeaveAlphaUnchanged | kvImageBackgroundColorFill | SynopsisvImageTileFlag);
    if (err != kvImageNoError)
        NSLog(@" error %ld", err);
    
    // Free / unlock
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    inBuff.data = NULL; // explicit
    
    CVPixelBufferUnlockBaseAddress(transformedBuffer, 0);

    return transformedBuffer;
}

- (CVPixelBufferRef) createRotatedPixelBuffer:(CVPixelBufferRef)pixelBuffer withRotation:(CGAffineTransform)transform flip:(BOOL)flip
{
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    CGRect originalRect = {0, 0, width, height};
    
    CVPixelBufferLockBaseAddress(pixelBuffer,kCVPixelBufferLock_ReadOnly);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    vImage_Buffer inBuff;
    inBuff.height = CVPixelBufferGetHeight(pixelBuffer);
    inBuff.width = CVPixelBufferGetWidth(pixelBuffer);
    inBuff.rowBytes = bytesPerRow;
    inBuff.data = baseAddress;
    
    // Transform
    CGAffineTransform finalTransform = transform;
    if(flip)
    {
        CGRect flippedRect = CGRectApplyAffineTransform(originalRect, finalTransform);
        flippedRect = CGRectIntegral(flippedRect);
        
        CGAffineTransform flip = CGAffineTransformMakeTranslation(flippedRect.size.width * 0.5, flippedRect.size.height * 0.5);
        flip = CGAffineTransformScale(flip, 1, -1);
        flip = CGAffineTransformTranslate(flip, -flippedRect.size.width * 0.5, -flippedRect.size.height * 0.5);
        
        finalTransform = CGAffineTransformConcat(finalTransform, flip);
    }
    
    CGRect transformedRect = CGRectApplyAffineTransform(originalRect, finalTransform);
    
    vImage_CGAffineTransform finalAffineTransform;
    finalAffineTransform.a = finalTransform.a;
    finalAffineTransform.b = finalTransform.b;
    finalAffineTransform.c = finalTransform.c;
    finalAffineTransform.d = finalTransform.d;
    finalAffineTransform.tx = finalTransform.tx;
    finalAffineTransform.ty = finalTransform.ty;
    
    // Create our pixel buffer pool for our transformed size
    // TODO: Our pixel buffer pool wont re-init if for some reason pixel buffer sizes change
    if(transformPixelBufferPool == NULL)
    {
        NSDictionary* poolAttributes = @{ (NSString*)kCVPixelBufferWidthKey : @(transformedRect.size.width),
                                          (NSString*)kCVPixelBufferHeightKey : @(transformedRect.size.height),
                                          (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                          };
        CVReturn err = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef _Nullable)(poolAttributes), &transformPixelBufferPool);
        if(err != kCVReturnSuccess)
        {
            NSLog(@"Error : %i", err);
        }
    }
    
    CVPixelBufferRef transformedBuffer;
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, transformPixelBufferPool, &transformedBuffer);
    
    CVPixelBufferLockBaseAddress(transformedBuffer, 0);
    unsigned char *transformBytes = CVPixelBufferGetBaseAddress(transformedBuffer);
    
    const uint8_t backColorU[4] = {0};
    
    //    vImage_CGImageFormat desiredFormat;
    //    desiredFormat.bitsPerComponent = 8;
    //    desiredFormat.bitsPerPixel = 32;
    //    desiredFormat.colorSpace = NULL;
    //    desiredFormat.bitmapInfo = (CGBitmapInfo)(kCGImageAlphaFirst | kCGImageAlphaPremultipliedFirst| kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    //    desiredFormat.version = 0;
    //    desiredFormat.decode = NULL;
    //    desiredFormat.renderingIntent = kCGRenderingIntentDefault;
    
    vImage_Buffer transformed = {transformBytes, CVPixelBufferGetHeight(transformedBuffer), CVPixelBufferGetWidth(transformedBuffer), CVPixelBufferGetBytesPerRow(transformedBuffer)};
    vImage_Error err;
    //    err = vImageBuffer_InitWithCVPixelBuffer(&transformed, &desiredFormat, transformedBuffer, NULL, backColorF, kvImageNoFlags);
    //    if (err != kvImageNoError)
    //        NSLog(@" error %ld", err);
    
   // err = vImageRotate90_ARGB8888(&inBuff, <#const vImage_Buffer *dest#>, <#uint8_t rotationConstant#>, <#const uint8_t *backColor#>, <#vImage_Flags flags#>)
    
    err = vImageAffineWarpCG_ARGB8888(&inBuff, &transformed, NULL, &finalAffineTransform, backColorU, kvImageLeaveAlphaUnchanged | kvImageBackgroundColorFill | SynopsisvImageTileFlag);
    if (err != kvImageNoError)
        NSLog(@" error %ld", err);
    
    // Free / unlock
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    inBuff.data = NULL; // explicit
    
    CVPixelBufferUnlockBaseAddress(transformedBuffer, 0);
    
    return transformedBuffer;
}

- (CVPixelBufferRef) createPixelBuffer:(CVPixelBufferRef)pixelBuffer withTransform:(CGAffineTransform)transform forQuality:(SynopsisAnalysisQualityHint)quality
{
    BOOL inputIsFlipped = CVImageBufferIsFlipped(pixelBuffer);
    
    CVPixelBufferRef scaledPixelBuffer = [self createScaledPixelBuffer:pixelBuffer forQuality:quality];

    // Is our transform equal to any 90 º rotations?
    if(!CGAffineTransformEqualToTransform(CGAffineTransformIdentity, transform))
    {
        CGAffineTransform ninety = CGAffineTransformMakeRotation(90);
        CGAffineTransform oneeighty = CGAffineTransformMakeRotation(180);
        CGAffineTransform twoseventy = CGAffineTransformMakeRotation(270);
        CGAffineTransform three360 = CGAffineTransformMakeRotation(360);

        unsigned int rotation = -1;
        if(CGAffineTransformEqualToTransform(ninety, transform))
            rotation = 1;
        else if(CGAffineTransformEqualToTransform(oneeighty, transform))
            rotation = 2;
        else if(CGAffineTransformEqualToTransform(twoseventy, transform))
            rotation = 2;
        else if(CGAffineTransformEqualToTransform(three360, transform))
            rotation = 2;

        // If our input affine transform is not a simple rotation (not sure, maybe a translate too?), use vImageAffineWarpCG_ARGB8888
        if(rotation == -1)
        {
            CVPixelBufferRef transformedPixelBuffer = [self createTransformedPixelBuffer:scaledPixelBuffer withTransform:transform flip:inputIsFlipped];
            
            CVPixelBufferRelease(scaledPixelBuffer);
        
            return transformedPixelBuffer;
        }
        else
        {
            CVPixelBufferRef rotatedPixelBuffer = [self createTransformedPixelBuffer:scaledPixelBuffer withTransform:transform flip:inputIsFlipped];
            
            CVPixelBufferRelease(scaledPixelBuffer);
            
            return rotatedPixelBuffer;
            
        }
    }
    
    return scaledPixelBuffer;
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
