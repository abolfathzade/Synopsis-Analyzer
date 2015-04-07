//
//  MetadataWriterTranscodeOperation.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "BaseTranscodeOperation.h"

@interface MetadataWriterTranscodeOperation : BaseTranscodeOperation

- (id) initWithSourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL metadataOptions:(NSDictionary*)metadataOptions NS_DESIGNATED_INITIALIZER;

@end
