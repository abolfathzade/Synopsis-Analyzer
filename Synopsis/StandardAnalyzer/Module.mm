//
//  Module.m
//  Synopsis
//
//  Created by vade on 11/10/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#import "Module.h"

@implementation Module

- (instancetype) initWithQualityHint:(SynopsisAnalysisQualityHint)qualityHint
{
    self = [super init];
    {
        
    }
    return self;
}

- (instancetype)init
{
    self = [self initWithQualityHint:SynopsisAnalysisQualityHintMedium];
    return self;
}

- (NSString*) moduleName
{
    [NSObject doesNotRecognizeSelector:_cmd];
    return nil;
}


- (FrameCacheFormat) currentFrameFormat
{
    [NSObject doesNotRecognizeSelector:_cmd];
    return FrameCacheFormatBGR8;
}

- (FrameCacheFormat) previousFrameFormat
{
    [NSObject doesNotRecognizeSelector:_cmd];
    return FrameCacheFormatBGR8;
}

- (NSDictionary*) analyzedMetadataForCurrentFrame:(matType)frame previousFrame:(matType)lastFrame
{
    [NSObject doesNotRecognizeSelector:_cmd];
    return nil;
}

- (NSDictionary*) finaledAnalysisMetadata;
{
    [NSObject doesNotRecognizeSelector:_cmd];
    return nil;
}

@end
