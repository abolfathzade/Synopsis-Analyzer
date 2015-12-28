//
//  PresetObject.m
//  Synopsis
//
//  Created by vade on 12/27/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "PresetObject.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTVideoEncoderList.h>
#import <VideoToolbox/VTProfessionalVideoWorkflow.h>

@interface PresetObject ()
{
    
}
@property (readwrite) NSString* title;
@property (readwrite) NSDictionary* audioSettings;
@property (readwrite) NSDictionary* videoSettings;
@property (readwrite) NSDictionary* analyzerSettings;

@property (readwrite) BOOL useAudio;
@property (readwrite) BOOL useVideo;
@property (readwrite) BOOL useAnalysis;

@end

@implementation PresetObject

- (id) initWithTitle:(NSString*)title audioSettings:(NSDictionary*)audioSettings videoSettings:(NSDictionary*)videoSettings analyzerSettings:(NSDictionary*)analyzerSettings useAudio:(BOOL)useAudio useVideo:(BOOL)useVideo useAnalysis:(BOOL) useAnalysis
{
    self = [super init];
    if(self)
    {
        self.title = title;
        self.audioSettings = audioSettings;
        self.videoSettings = videoSettings;
        self.analyzerSettings = analyzerSettings;
        
        self.useAudio = useAudio;
        self.useVideo = useVideo;
        self.useAnalysis = useAnalysis;
        
        return self;
    }
    return nil;
}

- (NSString*) description
{
    NSString* description = [self.title stringByAppendingString:@"\n\r"];
    
    NSString* audioSettingsString = [@"• Audio Settings:\n\r" stringByAppendingString:[self audioFormatString]];
    
    description = [description stringByAppendingString:audioSettingsString];
    
    description = [description stringByAppendingString:@"\n\r"];
    description = [description stringByAppendingString:@"\n\r"];

    NSString* videoSettingsString = [@"• Video Settings:\n\r" stringByAppendingString:[self videoFormatString]];
    
    description = [description stringByAppendingString:videoSettingsString];

    
    return description;
}

- (NSString*) audioFormatString
{
    NSString* audioFormat = @"\tAudio Format: ";
    
    if(self.useAudio == NO)
        return [audioFormat stringByAppendingString:@"None"];
    
    if(self.audioSettings == nil)
        return [audioFormat stringByAppendingString:@"Passthrough"];
    
    if(self.audioSettings[AVFormatIDKey] == [NSNull null])
        return [audioFormat stringByAppendingString:@"Passthrough"];

    else if([self.audioSettings[AVFormatIDKey]  isEqual: @(kAudioFormatLinearPCM)])
        audioFormat = [audioFormat stringByAppendingString:@"Linear PCM"];
    
    else if([self.audioSettings[AVFormatIDKey]  isEqual: @(kAudioFormatAppleLossless)])
        audioFormat = [audioFormat stringByAppendingString:@"Apple Lossless"];
    
    else if([self.audioSettings[AVFormatIDKey]  isEqual: @(kAudioFormatMPEG4AAC)])
        audioFormat = [audioFormat stringByAppendingString:@"AAC"];
    
    audioFormat = [audioFormat stringByAppendingString:@"\n\r"];
    audioFormat = [audioFormat stringByAppendingString:@"\tSampling Rate: "];
    audioFormat = [audioFormat stringByAppendingString:self.audioSettings[AVSampleRateKey]];

    audioFormat = [audioFormat stringByAppendingString:@"\n\r"];
    audioFormat = [audioFormat stringByAppendingString:@"\tNumber of Channels: "];
    audioFormat = [audioFormat stringByAppendingString:self.audioSettings[AVNumberOfChannelsKey]];

    return audioFormat;
}

- (NSString*) videoFormatString
{
    NSString* videoFormat = @"\tVideo Format: ";
    
    if(self.useVideo == NO)
        return [videoFormat stringByAppendingString:@"None"];

    if(self.videoSettings == nil)
        return [videoFormat stringByAppendingString:@"Passthrough"];

    if(self.videoSettings[AVVideoCodecKey] == [NSNull null])
        return [videoFormat stringByAppendingString:@"Passthrough"];

    CFArrayRef videoEncoders;
    VTCopyVideoEncoderList(NULL, &videoEncoders);
    NSArray* videoEncodersArray = (__bridge NSArray*)videoEncoders;
    
    // fourcc requires 'icod' (need to add the 's)
    OSType fourcc = NSHFSTypeCodeFromFileType([@"'" stringByAppendingString:[self.videoSettings[AVVideoCodecKey] stringByAppendingString:@"'"]]);
    NSNumber* fourccNum = [NSNumber numberWithInt:fourcc];
    
    for(NSDictionary* encoder in videoEncodersArray)
    {
        NSNumber* codecType = (NSNumber*)encoder[(NSString*)kVTVideoEncoderList_CodecType];
        if([codecType isEqual:fourccNum])
        {
            videoFormat = [videoFormat stringByAppendingString:encoder[(NSString*)kVTVideoEncoderList_DisplayName]];
            break;
        }
    }
    
    if(self.videoSettings[AVVideoWidthKey] && self.videoSettings[AVVideoHeightKey])
    {
        videoFormat = [videoFormat stringByAppendingString:@"\n\r"];
        videoFormat = [videoFormat stringByAppendingString:@"\tDimensions: "];
        videoFormat = [videoFormat stringByAppendingString:self.videoSettings[AVVideoWidthKey]];
        videoFormat = [videoFormat stringByAppendingString:@" x "];
        videoFormat = [videoFormat stringByAppendingString:self.videoSettings[AVVideoHeightKey]];
    }
    else
    {
        videoFormat = [videoFormat stringByAppendingString:@"\n\r"];
        videoFormat = [videoFormat stringByAppendingString:@"\tDimensions: Native"];
    }
    
    return videoFormat;
}

@end

