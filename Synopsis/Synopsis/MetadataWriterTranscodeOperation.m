//
//  MetadataWriterTranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "MetadataWriterTranscodeOperation.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "SampleBufferAnalyzerPluginProtocol.h"
#import "NSDictionary+JSONString.h"


//
//  TranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

@interface MetadataWriterTranscodeOperation ()
{
}

// Prerequisites
@property (atomic, readwrite, strong) NSDictionary* metadataOptions;

// Metadata to write
@property (atomic, readwrite, strong) NSMutableArray* analyzedVideoSampleBufferMetadata;
@property (atomic, readwrite, strong) NSMutableArray* analyzedAudioSampleBufferMetadata;
@property (atomic, readwrite, strong) NSMutableArray* analyzedGlobalMetadata;

// Reading the original sample Data
@property (atomic, readwrite, strong) AVURLAsset* transcodeAsset;
@property (atomic, readwrite, strong) AVAssetReader* transcodeAssetReader;
@property (atomic, readwrite, strong) AVAssetReaderTrackOutput* transcodeAssetReaderVideoPassthrough;
@property (atomic, readwrite, strong) AVAssetReaderTrackOutput* transcodeAssetReaderAudioPassthrough;

// Writing passthrough sample data & metdata
@property (atomic, readwrite, strong) AVAssetWriter* transcodeAssetWriter;
@property (atomic, readwrite, strong) AVAssetWriterInput* transcodeAssetWriterVideoPassthrough;
@property (atomic, readwrite, strong) AVAssetWriterInput* transcodeAssetWriterAudioPassthrough;
@property (atomic, readwrite, strong) AVAssetWriterInput* transcodeAssetWriterMetadata;
@property (atomic, readwrite, strong) AVAssetWriterInputMetadataAdaptor* transcodeAssetWriterMetadataAdaptor;

@end

@implementation MetadataWriterTranscodeOperation

- (id) initWithSourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL metadataOptions:(NSDictionary*)metadataOptions 
{
    self = [super init];
    if(self)
    {
        if(metadataOptions == nil)
        {
            return nil;
        }

        self.sourceURL = sourceURL;
        self.destinationURL = destinationURL;
        self.metadataOptions = metadataOptions;
        
        if(self.metadataOptions[kSynopsisAnalyzedVideoSampleBufferMetadataKey])
        {
            self.analyzedVideoSampleBufferMetadata = [self.metadataOptions[kSynopsisAnalyzedVideoSampleBufferMetadataKey] mutableCopy];
        }
        
        if(self.metadataOptions[kSynopsisAnalyzedAudioSampleBufferMetadataKey])
        {
            self.analyzedAudioSampleBufferMetadata = [self.metadataOptions[kSynopsisAnalyzedAudioSampleBufferMetadataKey] mutableCopy];
        }
        
        if(self.metadataOptions[kSynopsisAnalyzedGlobalMetadataKey])
        {
            self.analyzedGlobalMetadata = [self.metadataOptions[kSynopsisAnalyzedGlobalMetadataKey] mutableCopy];
        }
        
        [self setupTranscodeShitSucessfullyOrDontWhatverMan];
    }
    return self;
}

- (NSString*) description
{
    return [NSString stringWithFormat:@"Transcode Operation: %p, Source: %@, Destination: %@", self, self.sourceURL, self.destinationURL];
}

- (void) main
{
    [self transcodeAndAnalyzeAsset];
    
    [super main];
}


- (NSError*) setupTranscodeShitSucessfullyOrDontWhatverMan
{
    self.transcodeAsset = [AVURLAsset URLAssetWithURL:self.sourceURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @TRUE}];
    
    BOOL hasVideo = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual].count ? YES : NO;
    BOOL hasAudio = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicAudible].count ? YES : NO;
    
    // TODO: error checking / handling
    NSError* error = nil;
    
    // Readers
    self.transcodeAssetReader = [AVAssetReader assetReaderWithAsset:self.transcodeAsset error:&error];
    
    // Video Reader -
    if(hasVideo)
    {
        // Passthrough Video Reader -
        AVAssetTrack* firstVideoTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual][0];
        self.transcodeAssetReaderVideoPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack
                                                                                               outputSettings:nil];
        self.transcodeAssetReaderVideoPassthrough.alwaysCopiesSampleData = YES;
    }
    
    // Audio Reader -
    if(hasAudio)
    {
        AVAssetTrack* firstAudioTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicAudible][0];
        
        // Passthrough Audio Reader -
        self.transcodeAssetReaderAudioPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstAudioTrack
                                                                                               outputSettings:nil];
        self.transcodeAssetReaderAudioPassthrough.alwaysCopiesSampleData = YES;
    }
    
    // Assign all our specific Outputs to our Reader
    if(hasVideo)
    {
        if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderVideoPassthrough])
        {
            [self.transcodeAssetReader addOutput:self.transcodeAssetReaderVideoPassthrough];
        }
    }
    
    if(hasAudio)
    {
        if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderAudioPassthrough])
        {
            [self.transcodeAssetReader addOutput:self.transcodeAssetReaderAudioPassthrough];
        }
    }
    
    // Writers
    self.transcodeAssetWriter = [AVAssetWriter assetWriterWithURL:self.destinationURL fileType:AVFileTypeQuickTimeMovie error:&error];
    
    // Passthrough Video and Audio
    self.transcodeAssetWriterVideoPassthrough = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil];
    self.transcodeAssetWriterAudioPassthrough = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil];
    
    // Metadata
    CMFormatDescriptionRef metadataFormatDescription = NULL;
    NSArray *specs = @[@{(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : kSynopsislMetadataIdentifier,
                         (__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (__bridge NSString *)kCMMetadataBaseDataType_RawData}];
    
    OSStatus err = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)specs, &metadataFormatDescription);
    self.transcodeAssetWriterMetadata = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:metadataFormatDescription];
    self.transcodeAssetWriterMetadataAdaptor = [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:self.transcodeAssetWriterMetadata];

    // Associate metadata to video
    [self.transcodeAssetWriterMetadata addTrackAssociationWithTrackOfInput:self.transcodeAssetWriterVideoPassthrough type:AVTrackAssociationTypeMetadataReferent];
    
    // Is this needed?
    self.transcodeAssetWriterMetadata.expectsMediaDataInRealTime = YES;
    
    // Assign all our specific inputs to our Writer
    if([self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterVideoPassthrough]
       && [self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterAudioPassthrough]
       && [self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterMetadata]
       )
    {
        [self.transcodeAssetWriter addInput:self.transcodeAssetWriterMetadata];
        
        if(hasVideo)
            [self.transcodeAssetWriter addInput:self.transcodeAssetWriterVideoPassthrough];
        
        if(hasAudio)
            [self.transcodeAssetWriter addInput:self.transcodeAssetWriterAudioPassthrough];
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
        
        //        CMBufferQueueRef decodeVideoBufferQueue;
        //        CMBufferQueueRef decodeAudioBufferQueue;
        //        CMBufferQueueRef metadataVideoAnalysisQueue;
        
        // Decode and Encode Queues - each pair writes or reads to a CMBufferQueue
        
        CMBufferQueueRef passthroughVideoBufferQueue;
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForSampleBuffersSortedByOutputPTS(), &passthroughVideoBufferQueue);
        
        dispatch_queue_t videoPassthroughDecodeQueue = dispatch_queue_create("videoPassthroughDecodeQueue", 0);
        dispatch_group_enter(g);
        
        dispatch_queue_t videoPassthroughEncodeQueue = dispatch_queue_create("videoPassthroughEncodeQueue", 0);
        dispatch_group_enter(g);
        
        //        CMBufferQueueRef passthroughAudioBufferQueue;
        //        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForSampleBuffersSortedByOutputPTS(), &passthroughAudioBufferQueue);
        //
        //        dispatch_queue_t audioPassthroughDecodeQueue = dispatch_queue_create("audioPassthroughDecodeQueue", 0);
        //        dispatch_group_enter(g);
        //
        //        dispatch_queue_t audioPassthroughEncodeQueue = dispatch_queue_create("audioPassthroughEncodeQueue", 0);
        //        dispatch_group_enter(g);
        
        
        __block BOOL finishedReadingAllPassthroughVideo = NO;
        
        // Passthrough Video Read into our Buffer Queue
        dispatch_async(videoPassthroughDecodeQueue, ^{
            
            // read sample buffers from our video reader - and append them to the queue.
            // only read while we have samples, and while our buffer queue isnt full
            
            while(self.transcodeAssetReader.status == AVAssetReaderStatusReading)
            {
                @autoreleasepool
                {
                    CMSampleBufferRef passthroughVideoSampleBuffer = [self.transcodeAssetReaderVideoPassthrough copyNextSampleBuffer];
                    if(passthroughVideoSampleBuffer)
                    {
                        //                            NSLog(@"Got Sample Buffer and Enqued it");
                        CMBufferQueueEnqueue(passthroughVideoBufferQueue, passthroughVideoSampleBuffer);
                        
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
            NSLog(@"Reading Done");
            
            dispatch_group_leave(g);
        });
        
        // TODO : look at SampleTimingInfo Struct to better get a handle on this shit.
        __block NSUInteger sampleCount = 0;
        __block CMTimeRange lastSampleTimeRange = kCMTimeRangeZero;
        
        // Passthrough Video Write from Buffer Queue
        [self.transcodeAssetWriterVideoPassthrough requestMediaDataWhenReadyOnQueue:videoPassthroughEncodeQueue usingBlock:^
         {
//           NSLog(@"Started Requesting Media");
             while([self.transcodeAssetWriterVideoPassthrough isReadyForMoreMediaData]
                   && [self.transcodeAssetWriterMetadata isReadyForMoreMediaData])
             {
                 // Are we done reading,
                 if(finishedReadingAllPassthroughVideo )
                 {
//                      NSLog(@"Finished Reading waiting to empty queue...");
                     if(CMBufferQueueIsEmpty(passthroughVideoBufferQueue) && !self.analyzedVideoSampleBufferMetadata.count)
                     {
                         [self.transcodeAssetWriterVideoPassthrough markAsFinished];
                         [self.transcodeAssetWriterMetadata markAsFinished];
//                          NSLog(@"Writing Done");
                         
                         dispatch_group_leave(g);
                         break;
                     }
                 }
                 
                 CMSampleBufferRef passthroughVideoSampleBuffer = (CMSampleBufferRef) CMBufferQueueDequeueAndRetain(passthroughVideoBufferQueue);
                 if(passthroughVideoSampleBuffer)
                 {
                     CMTime currentSamplePTS = CMSampleBufferGetOutputPresentationTimeStamp(passthroughVideoSampleBuffer);
                     CMTime currentSampleDuration = CMSampleBufferGetOutputDuration(passthroughVideoSampleBuffer);
                     CMTimeRange currentSampleTimeRange = CMTimeRangeMake(currentSamplePTS, currentSampleDuration);
                     
                     CGFloat currentPresetnationTimeInSeconds = CMTimeGetSeconds(currentSamplePTS);
                     
                     self.progress = currentPresetnationTimeInSeconds / assetDurationInSeconds;

                     
                     [self.transcodeAssetWriterVideoPassthrough appendSampleBuffer:passthroughVideoSampleBuffer];
                     
                     if(self.analyzedVideoSampleBufferMetadata.count)
                     {
                         AVTimedMetadataGroup *group = self.analyzedVideoSampleBufferMetadata[0];
                         if([self.transcodeAssetWriterMetadataAdaptor appendTimedMetadataGroup:group])
                         {
                             // Pop our metadata off...
                             [self.analyzedVideoSampleBufferMetadata removeObject:group];
                         }
                         else
                         {
                             NSLog(@"Unable to append metadata timed group to asset: %@, %@", self.transcodeAssetWriter.error, group);
                         }
                     
                     CFRelease(passthroughVideoSampleBuffer);
                     }
                 }
             }
             
             
         }];
        
        // Wait until every queue is finished processing
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        
        // Reset our queue to free anything we didnt already use.
        CMBufferQueueReset(passthroughVideoBufferQueue);
        
        [self.transcodeAssetWriter finishWritingWithCompletionHandler:^{
            //            NSLog(@"DONE WITH SHIT MAYBE");
        }];
    }
}


@end
