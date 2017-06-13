//
//  AsycAnalysisAndTranscodeOperation.h
//  Synopsis
//
//  Created by vade on 6/12/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "BaseTranscodeOperation.h"

@interface AsycAnalysisAndTranscodeOperation : BaseTranscodeOperation

@property (copy) NSMutableArray* analyzedVideoSampleBufferMetadata;
@property (copy) NSMutableArray* analyzedAudioSampleBufferMetadata;
@property (copy) NSDictionary* analyzedGlobalMetadata;
@property (assign) BOOL succeeded;

- (instancetype) initWithUUID:(NSUUID*)uuid sourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL transcodeOptions:(NSDictionary*)transcodeOptions NS_DESIGNATED_INITIALIZER;


@end
