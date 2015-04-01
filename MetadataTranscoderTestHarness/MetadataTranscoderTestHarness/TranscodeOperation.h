//
//  TranscodeOperation.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TranscodeOperation : NSOperation

extern const NSString* kMetavisualVideoTranscodeSettion;
extern const NSString* kMetavisualAudioTranscodeSettion;

// Transcode Options may be nil - indicating passthrough

- (id) initWithSourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL transcodeOptions:(NSDictionary*)transcodeOptions NS_DESIGNATED_INITIALIZER;

@end
