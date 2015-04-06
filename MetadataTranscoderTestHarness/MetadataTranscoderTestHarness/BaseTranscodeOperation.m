//
//  BaseTranscodeOperation.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/4/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "BaseTranscodeOperation.h"
#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTVideoEncoderList.h>
#import <VideoToolbox/VTProfessionalVideoWorkflow.h>

const NSString* kMetavisualMetadataIdentifier = @"mdta/org.metavisual.somethingsomething";


const NSString* kMetavisualVideoTranscodeSettingsKey = @"kMetavisualVideoTranscodeSettings";
const NSString* kMetavisualAudioTranscodeSettingsKey = @"kMetavisualAudioTranscodeSettings";
const NSString* kMetavisualAnalyzedVideoSampleBufferMetadataKey = @"kMetavisualAnalyzedVideoSampleBufferMetadata";
const NSString* kMetavisualAnalyzedAudioSampleBufferMetadataKey = @"kMetavisualAnalyzedAudioSampleBufferMetadata";
const NSString* kMetavisualAnalyzedGlobalMetadataKey = @"kMetavisualAnalyzedGlobalMetadata";

@implementation BaseTranscodeOperation

- (id) init
{
    self = [super init];
    if(self)
    {
        VTRegisterProfessionalVideoWorkflowVideoDecoders();
        VTRegisterProfessionalVideoWorkflowVideoEncoders();
        
        CFArrayRef videoEncoders;
        VTCopyVideoEncoderList(NULL, &videoEncoders);
        NSLog(@"Available Video Encoders: %@", videoEncoders);
    }
    
    return self;
}

- (void) main
{
    @synchronized(self)
    {
        if(self.completionBlock)
        {
            self.completionBlock();

            // Clear so we dont run twice, fucko
            self.completionBlock = nil;
        }
    }
}

@end
