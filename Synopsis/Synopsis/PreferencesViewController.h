//
//  PreferencesViewController.h
//  Synopsis
//
//  Created by vade on 12/25/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PreferencesViewController : NSViewController

- (NSDictionary*) audioSettingsDictionaryForPreset:(NSDictionary*)preset;
- (NSDictionary*) videoSettingsDictionaryForPreset:(NSDictionary*)preset;
- (NSDictionary*) analysisSettingsDictionaryForPreset:(NSDictionary*)preset;

@end
