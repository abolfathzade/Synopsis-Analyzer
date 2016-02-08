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
@property (readwrite) BOOL editable;
//@property (readwrite) NSString* zero;
//@property (readwrite) NSString* one;
//@property (readwrite) NSString* two;
@end

@implementation PresetObject

- (id) initWithTitle:(NSString*)title audioSettings:(PresetAudioSettings*)audioSettings videoSettings:(PresetVideoSettings*)videoSettings analyzerSettings:(PresetAnalysisSettings*)analyzerSettings useAudio:(BOOL)useAudio useVideo:(BOOL)useVideo useAnalysis:(BOOL) useAnalysis editable:(BOOL)editable
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
        
        self.editable = editable;
                
        return self;
    }
    return nil;
}

- (id) copyWithZone:(NSZone *)zone
{
    return [[PresetObject allocWithZone:zone] initWithTitle:self.title
                                              audioSettings:self.audioSettings
                                              videoSettings:self.videoSettings
                                           analyzerSettings:self.analyzerSettings
                                                   useAudio:self.useAudio
                                                   useVideo:self.useVideo
                                                useAnalysis:self.useAnalysis
                                                   editable:self.editable];
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
    
    if(self.audioSettings.settingsDictionary)
    {
        if(self.audioSettings.settingsDictionary[AVFormatIDKey] == [NSNull null])
            return [audioFormat stringByAppendingString:@"Passthrough"];
        
        else if([self.audioSettings.settingsDictionary[AVFormatIDKey]  isEqual: @(kAudioFormatLinearPCM)])
            audioFormat = [audioFormat stringByAppendingString:@"Linear PCM"];
        
        else if([self.audioSettings.settingsDictionary[AVFormatIDKey]  isEqual: @(kAudioFormatAppleLossless)])
            audioFormat = [audioFormat stringByAppendingString:@"Apple Lossless"];
        
        else if([self.audioSettings.settingsDictionary[AVFormatIDKey]  isEqual: @(kAudioFormatMPEG4AAC)])
            audioFormat = [audioFormat stringByAppendingString:@"AAC"];
        
        audioFormat = [audioFormat stringByAppendingString:@"\n\r"];
        audioFormat = [audioFormat stringByAppendingString:@"\tSampling Rate: "];
        if(self.audioSettings.settingsDictionary[AVSampleRateKey] != [NSNull null] && self.audioSettings.settingsDictionary[AVSampleRateKey] != nil)
            audioFormat = [audioFormat stringByAppendingString:[self.audioSettings.settingsDictionary[AVSampleRateKey] stringValue]];
        else
            audioFormat = [audioFormat stringByAppendingString:@"Match"];
        
        audioFormat = [audioFormat stringByAppendingString:@"\n\r"];
        audioFormat = [audioFormat stringByAppendingString:@"\tNumber of Channels: "];
        if(self.audioSettings.settingsDictionary[AVNumberOfChannelsKey] != [NSNull null] && self.audioSettings.settingsDictionary[AVNumberOfChannelsKey] != nil)
            audioFormat = [audioFormat stringByAppendingString:[self.audioSettings.settingsDictionary[AVNumberOfChannelsKey] stringValue]];
        else
            audioFormat = [audioFormat stringByAppendingString:@"Match"];
    }

    return audioFormat;
}

- (NSString*) videoFormatString
{
    NSString* videoFormat = @"\tVideo Format: ";
    
    if(self.useVideo == NO)
        return [videoFormat stringByAppendingString:@"None"];

    if(self.videoSettings == nil)
        return [videoFormat stringByAppendingString:@"Passthrough"];

    if(self.videoSettings.settingsDictionary)
    {
        if(self.videoSettings.settingsDictionary[AVVideoCodecKey] == [NSNull null])
            return [videoFormat stringByAppendingString:@"Passthrough"];
        
        CFArrayRef videoEncoders;
        VTCopyVideoEncoderList(NULL, &videoEncoders);
        NSArray* videoEncodersArray = (__bridge NSArray*)videoEncoders;
    
        // fourcc requires 'icod' (need to add the 's)
        OSType fourcc = NSHFSTypeCodeFromFileType([@"'" stringByAppendingString:[self.videoSettings.settingsDictionary[AVVideoCodecKey] stringByAppendingString:@"'"]]);
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
        
        if(self.videoSettings.settingsDictionary[AVVideoWidthKey] && self.videoSettings.settingsDictionary[AVVideoHeightKey])
        {
            videoFormat = [videoFormat stringByAppendingString:@"\n\r"];
            videoFormat = [videoFormat stringByAppendingString:@"\tDimensions: "];
            videoFormat = [videoFormat stringByAppendingString:[self.videoSettings.settingsDictionary[AVVideoWidthKey] stringValue]];
            videoFormat = [videoFormat stringByAppendingString:@" x "];
            videoFormat = [videoFormat stringByAppendingString:[self.videoSettings.settingsDictionary[AVVideoHeightKey] stringValue]];
        }
        else
        {
            videoFormat = [videoFormat stringByAppendingString:@"\n\r"];
            videoFormat = [videoFormat stringByAppendingString:@"\tDimensions: Native"];
        }
    }
    return videoFormat;
}

@end

@implementation PresetSettings;
+ (instancetype) settingsWithDict:(NSDictionary*)dictionary
{
    PresetSettings* preset =  [[[self class] alloc] init];
    
    if(preset)
        preset.settingsDictionary = dictionary;
    
    return preset;
}

+ (instancetype) none;
{
    return [[[self class] alloc] init];
}

@end


@implementation PresetAudioSettings
@end

@implementation PresetVideoSettings
@end

@implementation PresetAnalysisSettings;
@end



