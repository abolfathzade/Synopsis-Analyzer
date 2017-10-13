//
//  BaseTranscodeOperation.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Synopsis/Synopsis.h>
#import <Foundation/Foundation.h>
#import "LogController.h"

// Notification Key, used when our enqueing fires off a new operation

extern NSString* const kSynopsisNewTranscodeOperationAvailable;

// Above Notifications sends a user info object that is our operations
// "descriptionDictionary"

// keys for descriptionDictionary
extern NSString* const kSynopsisTranscodeOperationUUIDKey; // NSUUID
extern NSString* const kSynopsisTranscodeOperationSourceURLKey; // NSURL
extern NSString* const kSynopsisTranscodeOperationDestinationURLKey; // NSURL

// Notification used when an transcode operation updates
extern NSString* const kSynopsisTranscodeOperationProgressUpdate;

// contains UUID key from above
extern NSString* const kSynopsisTranscodeOperationProgressKey; // NSNumber current progress
extern NSString* const kSynopsisTranscodeOperationTimeElapsedKey; // NSNumber as NSTimeInterval
extern NSString* const kSynopsisTranscodeOperationTimeRemainingKey; // NSNumber as NSTimeInterval
extern NSString* const kSynopsisTranscodeOperationMetadataKey; // NSDictionary of available analyzed metadata - may be nil


// We have a 2 pass analysis and decode (and possibly encode) system:

// Pass 1:
// Decodes and analysises data, and if necessary uses the same decoded sample buffers and sends them to an encoder.
// Opon completion of pass one, we now have per frame and summary metadata.

// Pass 2:
// We then write a second pass which is "pass through" of either the original samples, or the new encoded samples to a new movie
// With the appropriate metadata tracks written from pass 1.

#pragma mark - Pass 1 Settings:

// Key whose value is a dictionary appropriate for use with AVAssetWriterInput output settings. See AVVideoSettings.h
// If this key is [NSNull null] it implies passthrough video encoding - sample buffers will not be re-encoded;
// Required
extern NSString* const kSynopsisTranscodeVideoSettingsKey;

// Key whose value is a dictionary appropriate for use with AVAssetWriterInput output settings. See AVAudioSettings.h
// If this key is [NSNull null] it implies passthrough video encoding - sample buffers will not be re-encoded;
// Required
extern NSString* const kSynopsisTranscodeAudioSettingsKey;

// Key whose value is an NSDictionary with the following keys and values (see below)
// Required
extern NSString * const kSynopsisAnalysisSettingsKey;

// Key whose value is an NSNumber wrapping a SynopsisAnalysisQualityHint to use for the analysis session.
extern NSString * const kSynopsisAnalysisSettingsQualityHintKey;

// Key whose value is an NSNumber wrapping a boolean to enable threaded / concurrent analysis for modules and plugins.
extern NSString * const kSynopsisAnalysisSettingsEnableConcurrencyKey;

// Key whose value is an NSArray of NSStrings which are classnames of enabled pluggins used for the analysis session
extern NSString * const kSynopsisAnalysisSettingsEnabledPluginsKey;

// Key whose value is an NSDictionary of key value pairs of Encoder class names and an array of NSStrings modules enabled.
extern NSString * const kSynopsisAnalysisSettingsEnabledPluginModulesKey;

#pragma mark - Pass 2 Settings:

// Key whose value is an NSArray of AVMetadataItem (format TBD, we need to include time, maybe CMTimeRangeValues ?)
// The existence of this key implies we will write a metadata track associated with our video track
// Optional
extern NSString* const kSynopsisAnalyzedVideoSampleBufferMetadataKey;

// TODO: Implement this and think about audio metadata.
// Key whose value is an NSArray of metadata dictionaries (format TBD, we need to include time, maybe CMTimeRangeValues ?)
// The existence of this key implies we will write a metadata track associated with our video track.
// Optional
extern NSString* const kSynopsisAnalyzedAudioSampleBufferMetadataKey;

// Key whose value is a AVMetadataItem containing aggregate overall metadata used to write a summary metadata entry.
// The existence of this key implies we will write a metadata track with no association
// Optional
extern NSString* const kSynopsisAnalyzedGlobalMetadataKey;

// Optional - export JSON ?
extern NSString * const kSynopsisAnalyzedMetadataExportOptionKey;

// Base Transcode Operation ensures that its completion block runs WITHIN MAIN
// So that you know that depended operations have the previous compltion block called.
// Otherwise, you have a race condition.
// And thats fucking stupid.


@interface BaseTranscodeOperation : NSOperation
@property (atomic, readonly, strong) NSUUID* uuid;
@property (atomic, readonly, strong) NSDictionary* descriptionDictionary;
@property (atomic, readonly, strong) NSURL* sourceURL;
@property (atomic, readonly, strong) NSURL* destinationURL;
@property (atomic, readonly) CGFloat progress;
@property (atomic, readonly) NSTimeInterval elapsedTime;
@property (atomic, readonly) NSTimeInterval remainingTime;

// internal use - exposed for subclasses
@property (atomic, readwrite) CGFloat videoProgress;
@property (atomic, readwrite) CGFloat audioProgress;

@property (readonly, assign) BOOL succeeded;

@property (readonly, strong) NSError* error;

//// Every progress update tick this block is fired - update your ui on the main queue here.
//@property (copy) void (^progressBlock)(CGFloat progress);

- (instancetype) initWithUUID:(NSUUID*)uuid sourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL;
- (void) start NS_REQUIRES_SUPER;
- (void) main NS_REQUIRES_SUPER;


@end
