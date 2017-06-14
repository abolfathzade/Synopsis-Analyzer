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

#import <Synopsis/Constants.h>
#import <Synopsis/AnalyzerPluginProtocol.h>

#import "NSDictionary+JSONString.h"
#import "BSON/BSONSerialization.h"
#import "GZIP/GZIP.h"
#import "AtomicBoolean.h"
#include <sys/xattr.h>

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
@property (atomic, readwrite, strong) NSMutableDictionary* analyzedGlobalMetadata;

@property (atomic, readwrite, assign) BOOL transcodeAssetHasVideo;
@property (atomic, readwrite, assign) BOOL transcodeAssetHasAudio;

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

- (id) initWithUUID:(NSUUID*)uuid sourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL metadataOptions:(NSDictionary*)metadataOptions
{
    self = [super initWithUUID:uuid sourceURL:sourceURL destinationURL:destinationURL];
    if(self)
    {
        if(metadataOptions == nil)
        {
            return nil;
        }
        
        self.metadataOptions = metadataOptions;
        
        self.transcodeAssetHasVideo = NO;
        self.transcodeAssetHasAudio = NO;

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
    CMFormatDescriptionRef audioFormatDesc = NULL;
    CMFormatDescriptionRef videoFormatDesc = NULL;
    
    self.transcodeAsset = [AVURLAsset URLAssetWithURL:self.sourceURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @TRUE}];
    
    self.transcodeAssetHasVideo = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual].count ? YES : NO;
    self.transcodeAssetHasAudio = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicAudible].count ? YES : NO;
    
    // TODO: error checking / handling
    NSError* error = nil;
    
    // Readers
    self.transcodeAssetReader = [AVAssetReader assetReaderWithAsset:self.transcodeAsset error:&error];
    
    CGAffineTransform preferredTransform = CGAffineTransformIdentity;
    
    // Video Reader -
    if(self.transcodeAssetHasVideo)
    {
        // Passthrough Video Reader -
        AVAssetTrack* firstVideoTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual][0];
        
        //Check if we are self contained, (no references)
        // and if we have a single source format hint
        if(firstVideoTrack.formatDescriptions.count == 1 && firstVideoTrack.selfContained)
        {
            videoFormatDesc = (__bridge CMFormatDescriptionRef)(firstVideoTrack.formatDescriptions[0]);
        }
        
        self.transcodeAssetReaderVideoPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack
                                                                                               outputSettings:nil];
        self.transcodeAssetReaderVideoPassthrough.alwaysCopiesSampleData = NO;
        preferredTransform = firstVideoTrack.preferredTransform;
    }
    
    // Audio Reader -
    if(self.transcodeAssetHasAudio)
    {
        AVAssetTrack* firstAudioTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicAudible][0];
        
        //Check if we are self contained, (no references)
        // and if we have a single source format hint
        if(firstAudioTrack.formatDescriptions.count == 1 && firstAudioTrack.selfContained)
        {
            audioFormatDesc = (__bridge CMFormatDescriptionRef)(firstAudioTrack.formatDescriptions[0]);
        }
        
        // Passthrough Audio Reader -
        self.transcodeAssetReaderAudioPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstAudioTrack
                                                                                               outputSettings:nil];
        self.transcodeAssetReaderAudioPassthrough.alwaysCopiesSampleData = NO;
    }
    
    // Assign all our specific Outputs to our Reader
    if(self.transcodeAssetHasVideo)
    {
        if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderVideoPassthrough])
        {
            [self.transcodeAssetReader addOutput:self.transcodeAssetReaderVideoPassthrough];
        }
        else
        {
            [[LogController sharedLogController] appendErrorLog:[@"Unable to add video output track to asset reader: " stringByAppendingString:self.transcodeAssetReader.error.debugDescription]];
        }

    }
    
    if(self.transcodeAssetHasAudio)
    {
        if([self.transcodeAssetReader canAddOutput:self.transcodeAssetReaderAudioPassthrough])
        {
            [self.transcodeAssetReader addOutput:self.transcodeAssetReaderAudioPassthrough];
        }
        else
        {
            [[LogController sharedLogController] appendErrorLog:[@"Unable to add audio output track to asset reader: " stringByAppendingString:self.transcodeAssetReader.error.debugDescription]];
        }
    }
    
    // Writers
    self.transcodeAssetWriter = [AVAssetWriter assetWriterWithURL:self.destinationURL fileType:AVFileTypeQuickTimeMovie error:&error];
    
    // Passthrough Video and Audio
    // Use the format description for MPEG4 pass through compatibility as per asset writer docs
    if(videoFormatDesc != NULL)
        self.transcodeAssetWriterVideoPassthrough = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:videoFormatDesc];
    else
        self.transcodeAssetWriterVideoPassthrough = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil];
    
    if(audioFormatDesc != NULL)
        self.transcodeAssetWriterAudioPassthrough = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil sourceFormatHint:audioFormatDesc];
    else
        self.transcodeAssetWriterAudioPassthrough = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:nil];

    
//    // Our custom extensions for versioning and what not
//    CMFormatDescriptionRef metadataExtensionDescription = NULL;
//    
//    NSDictionary* metadataKeys = @{(NSString*)kCMMetadataFormatDescriptionKey_Namespace : @('v002'),
//                                   (NSString*)kCMMetadataFormatDescriptionKey_DataTypeNamespace : @(0),
////                                   (NSString*)kCMMetadataFormatDescriptionKey_DataType :
//                                   };
//    
//    NSDictionary *bufferExtensions = @{ (NSString*) kCMFormatDescriptionExtension_FormatName : @"Synopsis Metadata",
//                                        (NSString*) kCMFormatDescriptionExtension_Vendor : @"v002",
//                                        (NSString*) kCMFormatDescriptionExtension_Version : @1,
////                                        (NSString*) kCMFormatDescriptionExtensionKey_MetadataKeyTable : @[ metadataKeys],
//                                        
//                                        };
//    OSStatus err = CMFormatDescriptionCreate(kCFAllocatorDefault, 'meta', kCMMetadataFormatType_Boxed, (__bridge CFDictionaryRef _Nullable)(bufferExtensions), &metadataExtensionDescription);
//    
//    if(err)
//    {
//        NSLog(@"Error creating CMMetdataFormatDesc");
//    }
//    
    // Metadata valid
    CMFormatDescriptionRef metadataFormatDescriptionValid = NULL;
    NSArray *specs = @[@{(__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : kSynopsislMetadataIdentifier,
                         (__bridge NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (__bridge NSString *)kCMMetadataBaseDataType_RawData,
                         }];
    
    OSStatus err = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)specs, &metadataFormatDescriptionValid);
    if(err)
    {
        NSLog(@"Error creating CMMetdataFormatDesc");
    }

    
//    CMFormatDescriptionRef metadataFormatDescription = NULL;
    // combine them to hopefully get a valid format desc with extensions?
//    err = CMMetadataFormatDescriptionCreateByMergingMetadataFormatDescriptions(kCFAllocatorDefault, metadataFormatDescriptionValid, metadataExtensionDescription, &metadataFormatDescription);
    
//    if(err)
//    {
//        NSLog(@"Error creating CMMetdataFormatDesc");
//    }
//
    
    self.transcodeAssetWriterMetadata = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:metadataFormatDescriptionValid];
    self.transcodeAssetWriterMetadataAdaptor = [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:self.transcodeAssetWriterMetadata];

    // Associate metadata to video
    [self.transcodeAssetWriterMetadata addTrackAssociationWithTrackOfInput:self.transcodeAssetWriterVideoPassthrough type:AVTrackAssociationTypeMetadataReferent];
    
    // Is this needed?
    self.transcodeAssetWriterMetadata.expectsMediaDataInRealTime = NO;
    self.transcodeAssetWriterVideoPassthrough.expectsMediaDataInRealTime = NO;
    self.transcodeAssetWriterVideoPassthrough.transform = preferredTransform;
    self.transcodeAssetWriterAudioPassthrough.expectsMediaDataInRealTime = NO;
    
    // Assign all our specific inputs to our Writer
    if(self.transcodeAssetHasVideo)
    {
        if([self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterVideoPassthrough])
        {
            [self.transcodeAssetWriter addInput:self.transcodeAssetWriterVideoPassthrough];
        }
        else
        {
            [[LogController sharedLogController] appendErrorLog:[@"Unable to add video output track to asset writer: " stringByAppendingString:self.transcodeAssetWriter.error.debugDescription]];
        }
        
        if(self.analyzedVideoSampleBufferMetadata)
        {
            if([self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterMetadata])
            {
                [self.transcodeAssetWriter addInput:self.transcodeAssetWriterMetadata];
            }
            else
            {
                [[LogController sharedLogController] appendErrorLog:[@"Unable to add metadata output track to asset writer: " stringByAppendingString:self.transcodeAssetWriter.error.debugDescription]];
            }
        }
    }
    if(self.transcodeAssetHasAudio)
    {
        if([self.transcodeAssetWriter canAddInput:self.transcodeAssetWriterAudioPassthrough])
        {
            [self.transcodeAssetWriter addInput:self.transcodeAssetWriterAudioPassthrough];
        }
        else
        {
            [[LogController sharedLogController] appendErrorLog:[@"Unable to add audio output track to asset writer: " stringByAppendingString:self.transcodeAssetWriter.error.debugDescription]];
        }
        
        // Todo : Audio metadata here?
        // or do we move all metadata to audio if we have an audio track for higher sampling rates?
    }
    
    return error;
}

- (void) transcodeAndAnalyzeAsset
{
    CGFloat assetDurationInSeconds = CMTimeGetSeconds(self.transcodeAsset.duration);
    
    // Convert our global metadata to a valid top level AVMetadata item
    if(self.analyzedGlobalMetadata)
    {
        if([NSJSONSerialization isValidJSONObject:self.analyzedGlobalMetadata])
        {
            // TODO: Probably want to mark to NO for shipping code:
            NSString* aggregateMetadataAsJSON = [self.analyzedGlobalMetadata jsonStringWithPrettyPrint:NO];
            NSData* jsonData = [aggregateMetadataAsJSON dataUsingEncoding:NSUTF8StringEncoding];
            
            NSData* gzipData = [jsonData gzippedData];
            
            // Annotation text item
            AVMutableMetadataItem *textItem = [AVMutableMetadataItem metadataItem];
            textItem.identifier = kSynopsislMetadataIdentifier;
            textItem.dataType = (__bridge NSString *)kCMMetadataBaseDataType_RawData;
            textItem.value = gzipData;
            
            self.transcodeAssetWriter.metadata = @[textItem];

        }
        else
        {
            NSString* warning = @"Unable To Convert Global Metadata to JSON Format, invalid object";
            [[LogController sharedLogController] appendErrorLog:warning];
        }
    }
    
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
        
        // Decode and Encode Queues - each pair writes or reads to a CMBufferQueue
        
#pragma mark - Video Requirements

        CMBufferQueueRef videoPassthroughBufferQueue;
        // since we are using passthrough - we have to ensure we use DTS not PTS since buffers may be out of order.
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &videoPassthroughBufferQueue);
        
        dispatch_queue_t videoPassthroughDecodeQueue = dispatch_queue_create("videoPassthroughDecodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        dispatch_queue_t videoPassthroughEncodeQueue = dispatch_queue_create("videoPassthroughEncodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasVideo)
            dispatch_group_enter(g);
        
        // Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
        dispatch_semaphore_t videoDequeueSemaphore = dispatch_semaphore_create(0);
        
#pragma mark - Audio Requirements

        CMBufferQueueRef audioPassthroughBufferQueue;
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForSampleBuffersSortedByOutputPTS(), &audioPassthroughBufferQueue);
        
        dispatch_queue_t audioPassthroughDecodeQueue = dispatch_queue_create("audioPassthroughDecodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasAudio)
            dispatch_group_enter(g);
        
        dispatch_queue_t audioPassthroughEncodeQueue = dispatch_queue_create("audioPassthroughEncodeQueue", DISPATCH_QUEUE_SERIAL);
        if(self.transcodeAssetHasAudio)
            dispatch_group_enter(g);
        
        // Make a semaphor to control when our reads happen, we wait to write once we have a signal that weve read.
        dispatch_semaphore_t audioDequeueSemaphore = dispatch_semaphore_create(0);
        
#pragma mark - Read Video pass through
        
        __block AtomicBoolean* finishedReadingAllPassthroughVideo = [[AtomicBoolean alloc] init];

        if(self.transcodeAssetHasVideo)
        {
            dispatch_async(videoPassthroughDecodeQueue, ^{
                
                // read sample buffers from our video reader - and append them to the queue.
                // only read while we have samples, and while our buffer queue isnt full
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading && !self.isCancelled)
                {
                    @autoreleasepool
                    {
                        CMSampleBufferRef passthroughVideoSampleBuffer = [self.transcodeAssetReaderVideoPassthrough copyNextSampleBuffer];
                        if(passthroughVideoSampleBuffer)
                        {
                            //                            NSLog(@"Got Sample Buffer and Enqued it");
                            CMBufferQueueEnqueue(videoPassthroughBufferQueue, passthroughVideoSampleBuffer);
                            
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
                [[LogController sharedLogController] appendSuccessLog:@"Finished Passthrough Video Buffers"];
                
                // Fire final semaphore signal to hit finalization
                dispatch_semaphore_signal(videoDequeueSemaphore);
                
                dispatch_group_leave(g);
            });
        }

#pragma mark - Read Audio pass through
        
        __block AtomicBoolean* finishedReadingAllPassthroughAudio = [[AtomicBoolean alloc] init];
        
        if(self.transcodeAssetHasAudio)
        {
            dispatch_async(audioPassthroughDecodeQueue, ^{
                
                // read sample buffers from our video reader - and append them to the queue.
                // only read while we have samples, and while our buffer queue isnt full
                
                while(self.transcodeAssetReader.status == AVAssetReaderStatusReading && !self.isCancelled)
                {
                    @autoreleasepool
                    {
                        CMSampleBufferRef passthroughAudioSampleBuffer = [self.transcodeAssetReaderAudioPassthrough copyNextSampleBuffer];
                        if(passthroughAudioSampleBuffer)
                        {
                            //                            NSLog(@"Got Sample Buffer and Enqued it");
                            CMBufferQueueEnqueue(audioPassthroughBufferQueue, passthroughAudioSampleBuffer);
                            
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

#pragma mark - Video and Metadata Write
        
        if(self.transcodeAssetHasVideo)
        {
            // Passthrough Video Write from Buffer Queue
            [self.transcodeAssetWriterVideoPassthrough requestMediaDataWhenReadyOnQueue:videoPassthroughEncodeQueue usingBlock:^
             {
    //           NSLog(@"Started Requesting Media");
                 while([self.transcodeAssetWriterVideoPassthrough isReadyForMoreMediaData]
                       && [self.transcodeAssetWriterMetadata isReadyForMoreMediaData])
                 {
                     // Are we done reading,
                     if([finishedReadingAllPassthroughVideo getValue] || self.isCancelled)
                     {
//                         NSLog(@"Finished Reading waiting to empty queue...");
                         dispatch_semaphore_signal(videoDequeueSemaphore);

                         // if our video is done, were done. We dont care if we missed a single piece of metadata or not.
                         if(CMBufferQueueIsEmpty(videoPassthroughBufferQueue) )//&& !self.analyzedVideoSampleBufferMetadata.count)
                         {
                             [self.transcodeAssetWriterVideoPassthrough markAsFinished];
                             [self.transcodeAssetWriterMetadata markAsFinished];
    //                          NSLog(@"Writing Done");
                             
                             dispatch_group_leave(g);
                             break;
                         }
                     }
                     
                     // wait to dequeue until we have an enqueued buffer / signal from our enqueue thread.
                     dispatch_semaphore_wait(videoDequeueSemaphore, DISPATCH_TIME_FOREVER);
                     
                     CMSampleBufferRef passthroughVideoSampleBuffer = (CMSampleBufferRef) CMBufferQueueDequeueAndRetain(videoPassthroughBufferQueue);
                     if(passthroughVideoSampleBuffer)
                     {
                         CMTime currentSamplePTS = CMSampleBufferGetOutputPresentationTimeStamp(passthroughVideoSampleBuffer);
//                         CMTime currentSampleDuration = CMSampleBufferGetOutputDuration(passthroughVideoSampleBuffer);
//                         CMTimeRange currentSampleTimeRange = CMTimeRangeMake(currentSamplePTS, currentSampleDuration);
                         
                         CGFloat currentPresetnationTimeInSeconds = CMTimeGetSeconds(currentSamplePTS);
                         
                         self.videoProgress = currentPresetnationTimeInSeconds / assetDurationInSeconds;
                         
                         if(![self.transcodeAssetWriterVideoPassthrough appendSampleBuffer:passthroughVideoSampleBuffer])
                         {
                             [[LogController sharedLogController] appendErrorLog:[@"Unable to append video sample to asset at time: " stringByAppendingString:CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, currentSamplePTS))]];
                         }
                         
                         if(self.analyzedVideoSampleBufferMetadata.count)
                         {
                             unsigned int index = 0;
                             AVTimedMetadataGroup *group = self.analyzedVideoSampleBufferMetadata[index];
                             
                             // So this is tricky
                             // Our video is passthrough - which means for some video codecs we get samples in decode not presentation order
                             // since our metadata was analyzed by decoding (by definition), its in presentation timestamp order.
                             // So we need to search every passthrough sample for a metadata sample of the nearest timestamp
                             // If we find a match, we remove it from the dictionary to at least try to speed shit up...
                             // Theoretically DTS and PTS should be at least 'near' one another, so we dont need to iterate the entire dictionary.
                             
//                             CMTime currentSamplePTS = CMSampleBufferGetPresentationTimeStamp(passthroughVideoSampleBuffer);
//                             CMTime currentSampleOPTS = CMSampleBufferGetOutputPresentationTimeStamp(passthroughVideoSampleBuffer);
                             CMTime currentSampleDTS = CMSampleBufferGetDecodeTimeStamp(passthroughVideoSampleBuffer);
//                             CMTime currentSampleODTS = CMSampleBufferGetOutputDecodeTimeStamp(passthroughVideoSampleBuffer);
                             
                             int32_t compareResult =  CMTimeCompare(currentSampleDTS, group.timeRange.start);
                             
                             if(compareResult < 0 )
                             {
                                 while(CMTIME_COMPARE_INLINE(currentSampleDTS, <, group.timeRange.start))
                                 {
                                     index++;
                                     
                                     if(index < self.analyzedVideoSampleBufferMetadata.count)
                                         group = self.analyzedVideoSampleBufferMetadata[index];
                                     else
                                     {
                                         group = nil;
                                         break;
                                     }
                                 }

                             }
                             else if(compareResult > 0)
                             {
                                 while(CMTIME_COMPARE_INLINE(currentSampleDTS, >, group.timeRange.start))
                                 {
                                     index++;
                                     
                                     if(index < self.analyzedVideoSampleBufferMetadata.count)
                                         group = self.analyzedVideoSampleBufferMetadata[index];
                                     else
                                     {
                                         group = nil;
                                         break;
                                     }
                                 }
                             }
                             
                             if(group)
                             {
                                 if([self.transcodeAssetWriterMetadataAdaptor appendTimedMetadataGroup:group])
                                 {
                                     // Pop our metadata off...
                                     [self.analyzedVideoSampleBufferMetadata removeObject:group];
                                 }
                                 else
                                 {
                                     // Pop our metadata off...
                                     [self.analyzedVideoSampleBufferMetadata removeObject:group];

                                     [[LogController sharedLogController] appendErrorLog:[@"Unable to append metadata timed group to asset: " stringByAppendingString:self.transcodeAssetWriter.error.localizedDescription]];
                                 }
                             }
                             else
                             {
                                 [[LogController sharedLogController] appendWarningLog:@"No Metadata Sample Buffer for Video Sample"];
                             }
                         }

                         CFRelease(passthroughVideoSampleBuffer);
                     }
                 }
             }];
        }
        
#pragma mark - Audio and Metadata Write (Metadata Disabled for now until we have Audio Analysis API / Plugins)
        
        // TODO:: AUDIO METADATA (SEE VIDEO ABOVE FOR PATTERN)
        if(self.transcodeAssetHasAudio)
        {
            // Passthrough Video Write from Buffer Queue
            [self.transcodeAssetWriterAudioPassthrough requestMediaDataWhenReadyOnQueue:audioPassthroughEncodeQueue usingBlock:^
             {
                 while([self.transcodeAssetWriterAudioPassthrough isReadyForMoreMediaData])
                     // && audioMetadataWriter isReadyForMoreMediaData])
                     
                 {
                     // Are we done reading,
                     if([finishedReadingAllPassthroughAudio getValue] || self.isCancelled)
                     {
//                         NSLog(@"Finished Reading waiting to empty queue...");
                         dispatch_semaphore_signal(audioDequeueSemaphore);
                         
                         // if our audio is done, were done. We dont care if we missed a single piece of metadata or not.
                         if(CMBufferQueueIsEmpty(audioPassthroughBufferQueue) )//&& !self.analyzedVideoSampleBufferMetadata.count)
                         {
                             [self.transcodeAssetWriterAudioPassthrough markAsFinished];
//                             [self.transcodeAssetWriterMetadata markAsFinished];
                             //                          NSLog(@"Writing Done");
                             
                             dispatch_group_leave(g);
                             break;
                         }
                     }
                     
                     // wait to dequeue until we have an enqueued buffer / signal from our enqueue thread.
                     dispatch_semaphore_wait(audioDequeueSemaphore, DISPATCH_TIME_FOREVER);
                     
                     CMSampleBufferRef passthroughAudioSampleBuffer = (CMSampleBufferRef) CMBufferQueueDequeueAndRetain(audioPassthroughBufferQueue);
                     if(passthroughAudioSampleBuffer)
                     {
                         CMTime currentSamplePTS = CMSampleBufferGetOutputPresentationTimeStamp(passthroughAudioSampleBuffer);
//                         CMTime currentSampleDuration = CMSampleBufferGetOutputDuration(passthroughAudioSampleBuffer);
//                         CMTimeRange currentSampleTimeRange = CMTimeRangeMake(currentSamplePTS, currentSampleDuration);
                         
                         CGFloat currentPresetnationTimeInSeconds = CMTimeGetSeconds(currentSamplePTS);
                         
                         self.audioProgress = currentPresetnationTimeInSeconds / assetDurationInSeconds;
                         
                         if(![self.transcodeAssetWriterAudioPassthrough appendSampleBuffer:passthroughAudioSampleBuffer])
                         {
                             [[LogController sharedLogController] appendErrorLog:[@"Unable to append audio sample to asset at time: " stringByAppendingString:CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, currentSamplePTS))]];
                         }
                         
                         // Todo:: Audio Metadata
//                         if(self.analyzedVideoSampleBufferMetadata.count)
//                         {
//                             unsigned int index = 0;
//                             AVTimedMetadataGroup *group = self.analyzedVideoSampleBufferMetadata[index];
//                             
//                             // So this is tricky
//                             // Our video is passthrough - which means for some video codecs we get samples in decode not presentation order
//                             // since our metadata was analyzed by decoding (by definition), its in presentation timestamp order.
//                             // So we need to search every passthrough sample for a metadata sample of the nearest timestamp
//                             // If we find a match, we remove it from the dictionary to at least try to speed shit up...
//                             // Theoretically DTS and PTS should be at least 'near' one another, so we dont need to iterate the entire dictionary.
//                             
//                             CMTime currentSamplePTS = CMSampleBufferGetPresentationTimeStamp(passthroughVideoSampleBuffer);
//                             CMTime currentSampleOPTS = CMSampleBufferGetOutputPresentationTimeStamp(passthroughVideoSampleBuffer);
//                             CMTime currentSampleDTS = CMSampleBufferGetDecodeTimeStamp(passthroughVideoSampleBuffer);
//                             CMTime currentSampleODTS = CMSampleBufferGetOutputDecodeTimeStamp(passthroughVideoSampleBuffer);
//                             
//                             int32_t compareResult =  CMTimeCompare(currentSampleDTS, group.timeRange.start);
//                             
//                             if(compareResult < 0 )
//                             {
//                                 while(CMTIME_COMPARE_INLINE(currentSampleDTS, <, group.timeRange.start))
//                                 {
//                                     index++;
//                                     
//                                     if(index < self.analyzedVideoSampleBufferMetadata.count)
//                                         group = self.analyzedVideoSampleBufferMetadata[index];
//                                     else
//                                     {
//                                         group = nil;
//                                         break;
//                                     }
//                                 }
//                                 
//                             }
//                             else if(compareResult > 0)
//                             {
//                                 while(CMTIME_COMPARE_INLINE(currentSampleDTS, >, group.timeRange.start))
//                                 {
//                                     index++;
//                                     
//                                     if(index < self.analyzedVideoSampleBufferMetadata.count)
//                                         group = self.analyzedVideoSampleBufferMetadata[index];
//                                     else
//                                     {
//                                         group = nil;
//                                         break;
//                                     }
//                                 }
//                             }
//                             
//                             if(group)
//                             {
//                                 if([self.transcodeAssetWriterMetadataAdaptor appendTimedMetadataGroup:group])
//                                 {
//                                     // Pop our metadata off...
//                                     [self.analyzedVideoSampleBufferMetadata removeObject:group];
//                                 }
//                                 else
//                                 {
//                                     // Pop our metadata off...
//                                     [self.analyzedVideoSampleBufferMetadata removeObject:group];
//                                     
//                                     [[LogController sharedLogController] appendErrorLog:[@"Unable to append metadata timed group to asset: " stringByAppendingString:self.transcodeAssetWriter.error.localizedDescription]];
//                                 }
//                             }
//                             else
//                             {
//                                 [[LogController sharedLogController] appendErrorLog:@"No Metadata Sample Buffer for Video Sample"];
//                             }
//                         }
                         
                         CFRelease(passthroughAudioSampleBuffer);
                     }
                 }
             }];
        }
        
#pragma mark - Cleanup
        
        // Wait until every queue is finished processing
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        
        // Reset our queue to free anything we didnt already use.
        CMBufferQueueReset(videoPassthroughBufferQueue);
        
        dispatch_semaphore_t waitForWriting = dispatch_semaphore_create(0);
        
        [self.transcodeAssetWriter finishWritingWithCompletionHandler:^{

            // Lets get our global 'summary' metadata - we get this from our standard analyzer
            NSDictionary* standardAnalyzerOutputs = self.analyzedGlobalMetadata[kSynopsisStandardMetadataDictKey];
            
//            NSString* dHash = standardAnalyzerOutputs[@"Hash"];
//            NSArray* histogram = standardAnalyzerOutputs[@"Histogram"];
//            NSArray* dominantColors = standardAnalyzerOutputs[@"DominantColors"];
            NSArray* matchedNamedColors = standardAnalyzerOutputs[kSynopsisStandardMetadataDescriptionDictKey];

            NSMutableArray* allHumanSearchableDescriptors = [NSMutableArray new];
                        
            // Append all decriptors to our descriptor array
            [allHumanSearchableDescriptors addObjectsFromArray:matchedNamedColors];
            
            // write out our XATTR's
            if(allHumanSearchableDescriptors.count)
            {
                // make PList out of our array
                [self xattrsetPlist:allHumanSearchableDescriptors forKey:kSynopsisMetadataHFSAttributeTag];
            }
            
//            if(dominantColors.count)
//            {
//                // Because xattr's cannot hold array's of arrays, we are forced to 'unroll' our colors
//                NSMutableArray* unrolledDominantColors = [NSMutableArray new];
//                
//                for(NSArray* color in dominantColors)
//                {
//                    for(NSNumber* channel in color)
//                    {
//                        [unrolledDominantColors addObject:channel];
//                    }
//                }
//
//                [self xattrsetPlist:unrolledDominantColors forKey:@"info_v002_synopsis_dominant_colors"];
//            }
//
//            if(histogram.count)
//            {
//                // Because xattr's cannot hold array's of arrays, we are forced to 'unroll' our histogram
//                NSMutableArray* unrolledHistogram = [NSMutableArray new];
//                
//                for(NSArray* binTuplet in histogram)
//                {
//                    for(NSNumber* channel in binTuplet)
//                    {
//                        [unrolledHistogram addObject:channel];
//                    }
//                }
//
//                [self xattrsetPlist:unrolledHistogram forKey:@"info_v002_synopsis_histogram"];
//            }
//
//            if(dHash)
//            {
//                [self xattrsetPlist:dHash forKey:@"info_v002_synopsis_perceptual_hash"];
//            }
            
            dispatch_semaphore_signal(waitForWriting);
        }];
        
        // Wait till our finish writing completion block is done to return
        dispatch_semaphore_wait(waitForWriting, DISPATCH_TIME_FOREVER);
    }
    else
    {
		[[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Unable to start transcode from %@ to %@:", self.sourceURL, self.destinationURL]];
        [[LogController sharedLogController] appendErrorLog:[@"Read Error" stringByAppendingString:self.transcodeAssetReader.error.debugDescription]];
        [[LogController sharedLogController] appendErrorLog:[@"Write Error" stringByAppendingString:self.transcodeAssetWriter.error.debugDescription]];
    }
}

#pragma mark - XAttr helpers

- (NSString*) xAttrStringFromString:(NSString*)string
{
   return [@"com.apple.metadata:" stringByAppendingString:string];
}

- (BOOL) setResource:(id)plist forKey:(NSString*)key
{

    NSError* error = nil;

    if(![self.destinationURL setResourceValue:plist forKey:[self xAttrStringFromString:key] error:&error])
    {
        NSLog(@"Unable to set resource %@", error);
        return NO;
    }
    
    return YES;
}

- (BOOL)xattrsetPlist:(id)plist forKey:(NSString*)key
{
    BOOL valid = [NSPropertyListSerialization propertyList:plist isValidForFormat:NSPropertyListBinaryFormat_v1_0];
    
    if(valid)
    {
        NSError* error = nil;
        NSData* plistData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                                      options:0
                                                                        error:&error];
        if(!error && plistData)
        {
            int returnVal = setxattr([self.destinationURL fileSystemRepresentation], [[self xAttrStringFromString:key] UTF8String], [plistData bytes], [plistData length], 0, XATTR_NOFOLLOW);
            
            if(returnVal != 0)
            {
                NSLog(@"Unable to setxattr: %i", returnVal);
                return NO;
            }
            
            return YES;
        }
    }
    
    return NO;
}

- (void) notifyProgress
{
    dispatch_async(dispatch_get_main_queue(), ^(){
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kSynopsisTranscodeOperationProgressUpdate object:@{kSynopsisTranscodeOperationUUIDKey : self.uuid,
                                                                                                                           kSynopsisTranscodeOperationSourceURLKey : self.sourceURL,
                                                                                                                           kSynopsisTranscodeOperationDestinationURLKey : self.destinationURL,
                                                                                                                           kSynopsisTranscodeOperationProgressKey : @(self.progress),
                                                                                                                           kSynopsisTranscodeOperationTimeElapsedKey: @(self.elapsedTime),
                                                                                                                           kSynopsisTranscodeOperationTimeRemainingKey : @( self.remainingTime )}];
    });
    
}


@end
