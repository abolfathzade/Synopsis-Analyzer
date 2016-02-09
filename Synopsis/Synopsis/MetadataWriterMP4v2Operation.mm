//
//  MetadataWriterMP4v2Operation.m
//  Synopsis
//
//  Created by vade on 2/9/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#import "mp4v2.h"
#import "MetadataWriterMP4v2Operation.h"
#import <AVFoundation/AVFoundation.h>

@interface MetadataWriterMP4v2Operation ()
// Prerequisites
@property (atomic, readwrite, strong) NSDictionary* metadataOptions;

// Metadata to write
@property (atomic, readwrite, strong) NSMutableArray* analyzedVideoSampleBufferMetadata;
@property (atomic, readwrite, strong) NSMutableArray* analyzedAudioSampleBufferMetadata;
@property (atomic, readwrite, strong) NSMutableDictionary* analyzedGlobalMetadata;

@property (atomic, readwrite, assign) BOOL transcodeAssetHasVideo;
@property (atomic, readwrite, assign) BOOL transcodeAssetHasAudio;
@end

@implementation MetadataWriterMP4v2Operation

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
        
        self.transcodeAssetHasVideo = NO;
        self.transcodeAssetHasAudio = NO;
        
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

    }
    
    return self;
}


- (NSString*) description
{
    return [NSString stringWithFormat:@"MP4V2 Metadata Operation: %p, Source: %@, Destination: %@", self, self.sourceURL, self.destinationURL];
}

- (void) main
{
    [self writeMetadataTrack];
    
    [super main];
}

- (void) writeMetadataTrack
{
    NSString* filePath = [self.sourceURL path];

    if(![[NSFileManager defaultManager] fileExistsAtPath:filePath])
        [self cancel];
            
    MP4FileHandle file = MP4Modify([filePath cStringUsingEncoding:NSUTF8StringEncoding], 0 );

    if(file)
    {
        if(self.analyzedVideoSampleBufferMetadata.count)
        {
            MP4TrackId synvTrackID = MP4AddTrack(file, "SYNV", 1000);
            MP4SetTrackName(file, synvTrackID, "Synopsis Metadata");
            
            MP4Duration renderingOffset = 0;
            for( unsigned int index = 0; index < self.analyzedVideoSampleBufferMetadata.count; index++)
            {
                AVTimedMetadataGroup *group = self.analyzedVideoSampleBufferMetadata[index];

                NSData* compressedJSONData = (NSData*)group.items[0].value;
                
                MP4Duration sampleDuration = 1;
                
                const uint8_t *bytes = (const uint8_t*)[compressedJSONData bytes];
//                if(!MP4WriteSample(file, synvTrackID, compressedJSONData.bytes, compressedJSONData.length, sampleDuration, renderingOffset, true))
                if(!MP4WriteSample(file, synvTrackID, bytes, compressedJSONData.length))
                {
                    NSLog(@"Error Writing Metadata Sample what!?");
                }
                
                renderingOffset += sampleDuration;
            }
        }
    }
    
    MP4Close(file, 0);
            
    MP4Optimize([filePath cStringUsingEncoding:NSUTF8StringEncoding]);
}

@end
