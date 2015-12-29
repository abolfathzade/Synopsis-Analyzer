//
//  PresetObject.h
//  Synopsis
//
//  Created by vade on 12/27/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PresetObject : NSObject<NSCopying>

- (id) initWithTitle:(NSString*)title audioSettings:(NSDictionary*)audioSettings videoSettings:(NSDictionary*)videoSettings analyzerSettings:(NSDictionary*)analyzerSettings useAudio:(BOOL)useAudio useVideo:(BOOL)useVideo useAnalysis:(BOOL) useAnalysis editable:(BOOL)editable NS_DESIGNATED_INITIALIZER;

@property (readwrite) NSString* title;
@property (readwrite) NSDictionary* audioSettings;
@property (readwrite) NSDictionary* videoSettings;
@property (readwrite) NSDictionary* analyzerSettings;

@property (readwrite) BOOL useAudio;
@property (readwrite) BOOL useVideo;
@property (readwrite) BOOL useAnalysis;

@property (readonly) BOOL editable;

@end

