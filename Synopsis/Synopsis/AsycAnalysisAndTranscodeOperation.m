//
//  AsycAnalysisAndTranscodeOperation.m
//  Synopsis
//
//  Created by vade on 6/12/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "AsycAnalysisAndTranscodeOperation.h"

@implementation AsycAnalysisAndTranscodeOperation

- (instancetype) initWithUUID:(NSUUID*)uuid sourceURL:(NSURL*)sourceURL destinationURL:(NSURL*)destinationURL transcodeOptions:(NSDictionary*)transcodeOptions NS_DESIGNATED_INITIALIZER
{
    self = [super initWithUUID:uuid sourceURL:sourceURL destinationURL:destinationURL];
}

@end
