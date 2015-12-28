//
//  PreferencesGeneralViewController.m
//  Synopsis
//
//  Created by vade on 12/26/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "PreferencesGeneralViewController.h"
#import "PresetObject.h"

@interface PreferencesGeneralViewController ()
@property (weak) IBOutlet NSTextField* selectedDefaultPresetDescription;
@end

@implementation PreferencesGeneralViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (IBAction)setDefaultPresetAction:(NSMenuItem*)sender
{
    PresetObject* selectedPreset = [sender representedObject];
    
    self.selectedDefaultPresetDescription.stringValue = selectedPreset.description;
    
    self.defaultPreset = selectedPreset;
}

@end
