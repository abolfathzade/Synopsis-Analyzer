//
//  PresetObject.h
//  Synopsis
//
//  Created by vade on 12/27/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>
@class PresetVideoSettings;
@class PresetAudioSettings;
@class PresetAnalysisSettings;

#define kSynopsisDefaultPresetKey @"kSynopsisDefaultPreset"

@interface PresetObject : NSObject<NSCopying>

- (id) initWithTitle:(NSString*)title audioSettings:(PresetAudioSettings*)audioSettings videoSettings:(PresetVideoSettings*)videoSettings analyzerSettings:(PresetAnalysisSettings*)analyzerSettings useAudio:(BOOL)useAudio useVideo:(BOOL)useVideo useAnalysis:(BOOL) useAnalysis editable:(BOOL)editable uuid:(NSString*)UUIDString;

- (id) initWithTitle:(NSString*)title audioSettings:(PresetAudioSettings*)audioSettings videoSettings:(PresetVideoSettings*)videoSettings analyzerSettings:(PresetAnalysisSettings*)analyzerSettings useAudio:(BOOL)useAudio useVideo:(BOOL)useVideo useAnalysis:(BOOL) useAnalysis editable:(BOOL)editable;

- (instancetype) initWithData:(NSData *)data;
- (instancetype) init NS_UNAVAILABLE;
- (NSData *)copyPresetDataWithError:(NSError **)outError;

@property (readwrite) NSString* title;
@property (readwrite) PresetAudioSettings* audioSettings;
@property (readwrite) PresetVideoSettings* videoSettings;
@property (readwrite) PresetAnalysisSettings* analyzerSettings;

@property (readwrite) BOOL useAudio;
@property (readwrite) BOOL useVideo;
@property (readwrite) BOOL useAnalysis;
@property (readonly) BOOL editable;
@property (readonly) NSUUID* uuid;

@end

// We had / use unique types for NSOutlineView so we could determine the type of a preset
// this could probably go away  or be simplified into an NSDictionary category that
// returns a dictionary with a type key prepopulated...
// whatever man
// at some point this needs to be removed or made serializable

@interface PresetSettings : NSObject;
@property (copy) NSDictionary* settingsDictionary;
+ (instancetype) settingsWithDict:(NSDictionary*)dictionary;
+ (instancetype) none;
@end

@interface PresetAudioSettings : PresetSettings
@end

@interface PresetVideoSettings : PresetSettings
@end

@interface PresetAnalysisSettings : PresetSettings
@end

