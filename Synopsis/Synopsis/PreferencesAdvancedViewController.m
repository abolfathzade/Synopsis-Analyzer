//
//  PreferencesAdvancedViewController.m
//  Synopsis
//
//  Created by vade on 12/26/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "PreferencesAdvancedViewController.h"
#import "Constants.h"

@interface PreferencesAdvancedViewController ()

@end

@implementation PreferencesAdvancedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
    [[NSUserDefaults standardUserDefaults] objectForKey:kSynopsisAnalyzerConcurrentJobAnalysisPreferencesKey];

    
}

- (IBAction)enableSimultaneousJobs:(NSButton*)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:@((BOOL)sender.state) forKey:kSynopsisAnalyzerConcurrentJobAnalysisPreferencesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification object:self];
//    kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification
}


- (IBAction)enableSimultaneousFrames:(NSButton*)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:@((BOOL)sender.state) forKey:kSynopsisAnalyzerConcurrentFrameAnalysisPreferencesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:kSynopsisAnalyzerConcurrentFrameAnalysisDidChangeNotification object:self];

}

@end
