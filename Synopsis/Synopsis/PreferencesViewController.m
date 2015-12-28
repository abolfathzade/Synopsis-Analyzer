//
//  PreferencesViewController.m
//  Synopsis
//
//  Created by vade on 12/25/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "PreferencesViewController.h"
#import "PreferencesGeneralViewController.h"
#import "PreferencesPresetViewController.h"
#import "PreferencesAdvancedViewController.h"

@interface PreferencesViewController ()

@property (readwrite, nonatomic, strong) PreferencesGeneralViewController* preferencesGeneralViewController;
@property (readwrite, nonatomic, strong) PreferencesPresetViewController* preferencesPresetViewController;
@property (readwrite, nonatomic, strong) PreferencesAdvancedViewController* preferencesAdvancedViewController;


@property (weak) NSViewController* currentViewController;

@end

@implementation PreferencesViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    self.preferencesGeneralViewController = [[PreferencesGeneralViewController alloc] initWithNibName:@"PreferencesGeneralViewController" bundle:[NSBundle mainBundle]];
    self.preferencesPresetViewController = [[PreferencesPresetViewController alloc] initWithNibName:@"PreferencesPresetViewController" bundle:[NSBundle mainBundle]];
    self.preferencesAdvancedViewController = [[PreferencesAdvancedViewController alloc] initWithNibName:@"PreferencesAdvancedViewController" bundle:[NSBundle mainBundle]];
    
    [self addChildViewController:self.preferencesGeneralViewController];

    [self.view addSubview:self.preferencesGeneralViewController.view];
    [self.preferencesGeneralViewController.view setFrame:self.view.bounds];
    
    self.currentViewController = self.preferencesGeneralViewController;
    

    // populate our general prefs default preset button with all available presets
    [self.preferencesGeneralViewController.defaultPresetPopupButton.menu removeAllItems];

    for(PresetObject* preset in [self.preferencesPresetViewController allPresets])
    {
        NSMenuItem* presetMenuItem = [[NSMenuItem alloc] initWithTitle:preset.title action:@selector(setDefaultPresetAction:) keyEquivalent:@""];
        
        presetMenuItem.representedObject = preset;
        presetMenuItem.target = self.preferencesGeneralViewController;
        
        [self.preferencesGeneralViewController.defaultPresetPopupButton.menu addItem:presetMenuItem];
    }
    
    // set our default for now - since we arent loading for NSUserDefaults
    [[self.preferencesGeneralViewController.defaultPresetPopupButton menu] performActionForItemAtIndex:0];
}

#pragma mark -

- (PresetObject*) defaultPreset
{
    return self.preferencesGeneralViewController.defaultPreset;
}

#pragma mark -

- (IBAction)transitionToGeneral:(id)sender
{
    [self transitionToViewController:self.preferencesGeneralViewController];
}


- (IBAction)transitionToPreset:(id)sender
{
    [self transitionToViewController:self.preferencesPresetViewController];
}


- (IBAction)transitionToAdvanced:(id)sender
{
    [self transitionToViewController:self.preferencesAdvancedViewController];
}

- (void) transitionToViewController:(NSViewController*)viewController
{
    // early bail if equality
    if(self.currentViewController == viewController)
        return;
    
    [self addChildViewController:viewController];
    
    // update frame to match source / dest
    [viewController.view setFrame:self.currentViewController.view.bounds];

    [self transitionFromViewController:self.currentViewController
                      toViewController:viewController
                               options:NSViewControllerTransitionCrossfade
                     completionHandler:^{

                         [self.currentViewController removeFromParentViewController];
                         
                         self.currentViewController = viewController;
                     }];
}

@end
