//
//  PreferencesViewController.h
//  Synopsis
//
//  Created by vade on 12/25/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PresetObject.h"

@interface PreferencesViewController : NSViewController

- (PresetObject*) defaultPreset;
- (NSArray*) availablePresets;

@end
