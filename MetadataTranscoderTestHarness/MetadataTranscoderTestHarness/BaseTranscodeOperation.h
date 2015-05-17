//
//  BaseTranscodeOperation.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LogController.h"


extern const NSString* kSynopsislMetadataIdentifier;

// We have a 2 pass analysis and decode (and possibly encode) system:

// Pass 1:
// Decodes and analysises data, and if necessary uses the same decoded sample buffers and sends them to an encoder.
// Opon completion of pass one, we now have per frame and summary metadata.

// Pass 2:
// We then write a second pass which is "pass through" of either the original samples, or the new encoded samples to a new movie
// With the appropriate metadata tracks written from pass 1.


// Key whose value is a dictionary appropriate for use with AVAssetWriterInput output settings. See AVVideoSettings.h
// If this key is [NSNull null] it implies passthrough video encoding - sample buffers will not be re-encoded;
// Required
extern const NSString* kSynopsisTranscodeVideoSettingsKey;

// Key whose value is a dictionary appropriate for use with AVAssetWriterInput output settings. See AVAudioSettings.h
// If this key is [NSNull null] it implies passthrough video encoding - sample buffers will not be re-encoded;
// Required
extern const NSString* kSynopsisTranscodeAudioSettingsKey;

// Key whose value is an NSArray of metadata dictionaries (format TBD, we need to include time, maybe CMTimeRangeValues ?)
// The existence of this key implies we will write a metadata track associated with our video track
// Optional
extern const NSString* kSynopsisAnalyzedVideoSampleBufferMetadataKey;

// TODO: Implement this and think about audio metadata.
// Key whose value is an NSArray of metadata dictionaries (format TBD, we need to include time, maybe CMTimeRangeValues ?)
// The existence of this key implies we will write a metadata track associated with our video track.
// Optional
extern const NSString* kSynopsisAnalyzedAudioSampleBufferMetadataKey;

// Key whose value is a dictionary containing aggregate overall metadata used to write a summary metadata entry.
// The existence of this key implies we will write a metadata track with no association
// Optional
extern const NSString* kSynopsisAnalyzedGlobalMetadataKey;

// Base Transcode Operation ensures that its completion block runs WITHIN MAIN
// So that you know that depended operations have the previous compltion block called.
// Otherwise, you have a race condition.
// And thats fucking stupid.

// Progress Block


@interface BaseTranscodeOperation : NSOperation
@property (atomic, readwrite, strong) NSURL* sourceURL;
@property (atomic, readwrite, strong) NSURL* destinationURL;
@property (atomic, readwrite) CGFloat progress;

@property (copy) void (^progressBlock)(CGFloat progress);

- (void) start __attribute__((objc_requires_super));
- (void) main __attribute__((objc_requires_super));

@end
