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

#import "AnalyzerPluginProtocol.h"

#import "NSDictionary+JSONString.h"
#import "BSON/BSONSerialization.h"
#import "GZIP/GZIP.h"

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
    
    CGAffineTransform preferredTransform = CGAffineTransformIdentity;
    
    // Video Reader -
    if(hasVideo)
    {
        // Passthrough Video Reader -
        AVAssetTrack* firstVideoTrack = [self.transcodeAsset tracksWithMediaCharacteristic:AVMediaCharacteristicVisual][0];
        self.transcodeAssetReaderVideoPassthrough = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:firstVideoTrack
                                                                                               outputSettings:nil];
        self.transcodeAssetReaderVideoPassthrough.alwaysCopiesSampleData = YES;
        preferredTransform = firstVideoTrack.preferredTransform;
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
        else
        {
            [[LogController sharedLogController] appendErrorLog:[@"Unable to add video output track to asset reader: " stringByAppendingString:self.transcodeAssetReader.error.debugDescription]];
        }

    }
    
    if(hasAudio)
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
    self.transcodeAssetWriterMetadata.expectsMediaDataInRealTime = NO;
    self.transcodeAssetWriterVideoPassthrough.expectsMediaDataInRealTime = NO;
    self.transcodeAssetWriterVideoPassthrough.transform = preferredTransform;
    self.transcodeAssetWriterAudioPassthrough.expectsMediaDataInRealTime = NO;
    
    // Assign all our specific inputs to our Writer
    if(hasVideo)
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
    if(hasAudio)
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
        // since we are using passthrough - we have to ensure we use DTS not PTS since buffers may be out of order.
        CMBufferQueueCreate(kCFAllocatorDefault, numBuffers, CMBufferQueueGetCallbacksForUnsortedSampleBuffers(), &passthroughVideoBufferQueue);
        
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
                 if(finishedReadingAllPassthroughVideo)
                 {
                     // if our video is done, were done. We dont care if we missed a single piece of metadata or not.
                     if(CMBufferQueueIsEmpty(passthroughVideoBufferQueue) )//&& !self.analyzedVideoSampleBufferMetadata.count)
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
                         
                         CMTime currentSamplePTS = CMSampleBufferGetPresentationTimeStamp(passthroughVideoSampleBuffer);
                         CMTime currentSampleOPTS = CMSampleBufferGetOutputPresentationTimeStamp(passthroughVideoSampleBuffer);
                         CMTime currentSampleDTS = CMSampleBufferGetDecodeTimeStamp(passthroughVideoSampleBuffer);
                         CMTime currentSampleODTS = CMSampleBufferGetOutputDecodeTimeStamp(passthroughVideoSampleBuffer);
                         
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
                             [[LogController sharedLogController] appendErrorLog:@"No Metadata Sample Buffer for Video Sample"];
                         }
                     }

                     CFRelease(passthroughVideoSampleBuffer);
                 }
             }
         }];
        
        // Wait until every queue is finished processing
        dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
        
        // Reset our queue to free anything we didnt already use.
        CMBufferQueueReset(passthroughVideoBufferQueue);
        
        dispatch_semaphore_t waitForWriting = dispatch_semaphore_create(0);
        
        [self.transcodeAssetWriter finishWritingWithCompletionHandler:^{

            // Lets get our global 'summary' metadata - we get this from our standard analyzer
            NSDictionary* standardAnalyzerOutputs = self.analyzedGlobalMetadata[@"info.v002.Synopsis.OpenCVAnalyzer"];
            
            NSArray* dominantColors = standardAnalyzerOutputs[@"DominantColors"];
            NSArray* matchedNamedColors = [self matchColorNamesToColors:dominantColors];

            // write out our XATTR's
            if(matchedNamedColors.count)
            {
                // make PList out of our array
                [self xattrsetPlist:matchedNamedColors forKey:@"info_v002_synopsis_dominant_color_name"];
            }
            
            if(dominantColors.count)
            {
                [self xattrsetPlist:dominantColors forKey:@"info_v002_synopsis_dominant_color_values"];
            }
            
            dispatch_semaphore_signal(waitForWriting);
        }];
        
        // Wait till our finish writing completion block is done to return
        dispatch_semaphore_wait(waitForWriting, DISPATCH_TIME_FOREVER);
    }
}

#pragma mark - XAttr helpers

- (NSString*) xAttrStringFromString:(NSString*)string
{
   return [@"com.apple.metadata:" stringByAppendingString:string];
}

- (BOOL)xattrsetPlist:(id)plist forKey:(NSString*)key
{
//    if(![plist isKindOfClass:[NSArray class]] || ![plist isKindOfClass:[NSDictionary class]])
//    {
//        return NO;
//    }
//    
    NSError* error = nil;
    NSData* plistData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                                  options:0
                                                                    error:&error];
    if(!error && plistData)
    {
        NSString* destinationPath = [self.destinationURL path];
        
        const char *pathUTF8 = [destinationPath fileSystemRepresentation];
        const char *keyUTF8 = [[self xAttrStringFromString:key] fileSystemRepresentation];
        
        long returnVal = setxattr(pathUTF8, keyUTF8, [plistData bytes], [plistData length], 0, XATTR_NOFOLLOW);
        
        return YES;
    }

    return NO;
}

#pragma mark - Color Helpers

-(NSArray*) matchColorNamesToColors:(NSArray*)colorArray
{
    
    NSMutableArray* dominantNSColors = [NSMutableArray arrayWithCapacity:colorArray.count];

    for(NSArray* color in colorArray)
    {
        CGFloat alpha = 1.0;
        if(color.count > 3)
            alpha = [color[3] floatValue];
        
        NSColor* domColor = [NSColor colorWithRed:[color[0] floatValue]
                                            green:[color[1] floatValue]
                                             blue:[color[2] floatValue]
                                            alpha:alpha];
        
        [dominantNSColors addObject:domColor];
    }
    
    NSMutableArray* matchedNamedColors = [NSMutableArray arrayWithCapacity:dominantNSColors.count];
    
    for(NSColor* color in dominantNSColors)
    {
        NSString* namedColor = [self closestNamedColorForColor:color];
        NSLog(@"Found Color %@", namedColor);
        if(namedColor)
            [matchedNamedColors addObject:namedColor];
    }

    return matchedNamedColors;
}

- (NSString*) closestNamedColorForColor:(NSColor*)color
{
    NSColor* matchedColor = nil;

    // White, Grey, Black all are 'calibrated' white color spaces so you cant fetch color components from them
    // because no one at apple has seen a fucking prism.
    NSArray* knownColors = @[ [NSColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0], // White
                              [NSColor colorWithRed:0.0 green:0.0 blue:0 alpha:1.0], // Black
                              [NSColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0], // Gray
                              [NSColor redColor],
                              [NSColor greenColor],
                              [NSColor blueColor],
                              [NSColor magentaColor],
                              [NSColor orangeColor],
                              [NSColor yellowColor],
                              [NSColor cyanColor],
                              [NSColor brownColor],
                              ];


//    NSUInteger numberMatches = 0;
    
    // Longest distance from any float color component
    CGFloat distance = sqrt(1.0 + 1.0 + 1.0);
    
    for(NSColor* namedColor in knownColors)
    {
        CGFloat namedRed = [namedColor hueComponent];
        CGFloat namedGreen = [namedColor saturationComponent];
        CGFloat namedBlue = [namedColor brightnessComponent];
        
        CGFloat red = [color hueComponent];
        CGFloat green = [color saturationComponent];
        CGFloat blue = [color brightnessComponent];
        
        // Early bail
        if( red == namedRed && green == namedGreen && blue == namedBlue)
        {
            matchedColor = namedColor;
            break;
        }
        
        CGFloat newDistance = sqrt( pow(namedRed - red, 2.0) + pow(namedGreen - green, 2.0) + pow(namedBlue - blue, 2.0));
        
        if(newDistance < distance)
        {
            distance = newDistance;
            matchedColor = namedColor;
        }
    }
    
    return [self stringForKnownColor:matchedColor];
}

- (NSString*) stringForKnownColor:(NSColor*)knownColor
{
    if([knownColor isEqual:[NSColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0]])
    {
        return @"White";
    }
    else if ([knownColor isEqual:[NSColor colorWithRed:0.0 green:0.0 blue:0 alpha:1.0]])
    {
        return @"Black";
    }
    else if ([knownColor isEqual:[NSColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0]])
    {
        return @"Gray";
    }
    else if ([knownColor isEqual:[NSColor redColor]])
    {
        return @"Red";
    }
    else if ([knownColor isEqual:[NSColor greenColor]])
    {
        return @"Green";
    }
    else if ([knownColor isEqual:[NSColor blueColor]])
    {
        return @"Blue";
    }
    else if ([knownColor isEqual:[NSColor magentaColor]])
    {
        return @"Magenta";
    }
    else if ([knownColor isEqual:[NSColor orangeColor]])
    {
        return @"Organge";
    }
    else if ([knownColor isEqual:[NSColor yellowColor]])
    {
        return @"Yellow";
    }
    else if ([knownColor isEqual:[NSColor cyanColor]])
    {
        return @"Cyan";
    }
    else if ([knownColor isEqual:[NSColor brownColor]])
    {
        return @"Brown";
    }
    
    return nil;
}

@end
