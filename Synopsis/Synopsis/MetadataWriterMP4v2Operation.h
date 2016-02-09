//
//  MetadataWriterMP4v2Operation.h
//  Synopsis
//
//  Created by vade on 2/9/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#import "BaseTranscodeOperation.h"

@interface MetadataWriterMP4v2Operation : BaseTranscodeOperation

- (id) initWithSourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL metadataOptions:(NSDictionary*)metadataOptions NS_DESIGNATED_INITIALIZER;

@end
