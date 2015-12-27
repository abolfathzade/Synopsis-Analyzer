//
//  PresetObject.h
//  Synopsis
//
//  Created by vade on 12/27/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PresetObject : NSObject

- (id) initWithTitle:(NSString*)title audioSettings:(NSDictionary*)audioSettings videoSettings:(NSDictionary*)videoSettings analyzerSettings:(NSDictionary*)analyzerSettings useAudio:(BOOL)useAudio useVideo:(BOOL)useVideo useAnalysis:(BOOL) useAnalysis NS_DESIGNATED_INITIALIZER;

@property (readonly) NSString* title;

@property (readonly) NSDictionary* audioSettings;
@property (readonly) NSDictionary* videoSettings;
@property (readonly) NSDictionary* analyzerSettings;

@property (readonly) BOOL useAudio;
@property (readonly) BOOL useVideo;
@property (readonly) BOOL useAnalysis;

@end

