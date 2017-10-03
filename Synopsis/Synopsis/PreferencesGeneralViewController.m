//
//  PreferencesGeneralViewController.m
//  Synopsis
//
//  Created by vade on 12/26/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "PreferencesGeneralViewController.h"
#import "PresetObject.h"
#import <Synopsis/Synopsis.h>
#import "AppDelegate.h"

@interface PreferencesGeneralViewController ()
@property (weak) IBOutlet NSTextField* selectedDefaultPresetDescription;

@property (weak) IBOutlet NSButton* usingOutputFolderButton;
@property (weak) IBOutlet NSButton* selectOutputFolder;
@property (weak) IBOutlet NSTextField* outputFolderDescription;
@property (weak) IBOutlet NSButton* outputFolderStatus;

@property (weak) IBOutlet NSButton* usingWatchFolderButton;
@property (weak) IBOutlet NSButton* selectWatchFolder;
@property (weak) IBOutlet NSTextField* watchFolderDescription;
@property (weak) IBOutlet NSButton* watchFolderStatus;

@property (strong) SynopsisDirectoryWatcher* directoryWatcher;

@end

@implementation PreferencesGeneralViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (void) awakeFromNib
{
    [self validateOutputFolderUI];
    [self validateWatchFolderUI];
}

- (IBAction)setDefaultPresetAction:(NSMenuItem*)sender
{
    PresetObject* selectedPreset = [sender representedObject];
    
    self.selectedDefaultPresetDescription.stringValue = selectedPreset.description;
    
    self.defaultPreset = selectedPreset;
    
    [self.defaultPresetPopupButton setTitle:sender.title];
    
    [[NSUserDefaults standardUserDefaults] setObject:self.defaultPreset.uuid.UUIDString forKey:kSynopsisAnalyzerDefaultPresetPreferencesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Output Folder

- (IBAction)selectOutFolder:(id)sender
{
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.canChooseDirectories = YES;
    openPanel.canCreateDirectories = YES;
    openPanel.canChooseFiles = NO;
    openPanel.message = @"Select Output Folder";

    [openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
       if(result == NSModalResponseOK)
       {
           NSURL* outputFolderURL = [openPanel URL];
           dispatch_async(dispatch_get_main_queue(), ^{
               [self updateOutputFolder:outputFolderURL];
           });
       }
    }];
}

- (IBAction)useOutputFolder:(id)sender
{
    BOOL useFolder = ([sender state] == NSOnState);
    
    [[NSUserDefaults standardUserDefaults] setValue:@(useFolder) forKey:kSynopsisAnalyzerUseOutputFolderKey];

    [self validateOutputFolderUI];
}

- (void) updateOutputFolder:(NSURL*)outputURL
{
    [[NSUserDefaults standardUserDefaults] setValue:[outputURL path] forKey:kSynopsisAnalyzerOutputFolderURLKey];
    [self validateOutputFolderUI];
}

- (BOOL) usingOutputFolder
{
    return [[[NSUserDefaults standardUserDefaults] valueForKey:kSynopsisAnalyzerUseOutputFolderKey] boolValue];
}

- (NSURL*) outputFolderURL
{
    NSString* outputPath = [[NSUserDefaults standardUserDefaults] valueForKey:kSynopsisAnalyzerOutputFolderURLKey];
    if(outputPath)
    {
        NSURL* outputURL = [NSURL fileURLWithPath:outputPath];
        BOOL isDirectory = NO;
        if([[NSFileManager defaultManager] fileExistsAtPath:outputPath isDirectory:&isDirectory])
        {
            if(isDirectory)
                return outputURL;
        }
    }
    return nil;
}

- (void) validateOutputFolderUI
{
    NSURL* url = [self outputFolderURL];
    BOOL usingOutputFolder = [self usingOutputFolder];

    self.usingOutputFolderButton.state = ([self usingOutputFolder]) ? NSOnState : NSOffState;
    
    if(usingOutputFolder && url)
        self.outputFolderStatus.image = [NSImage imageNamed:NSImageNameStatusAvailable];
    else if (usingOutputFolder && !url)
        self.outputFolderStatus.image = [NSImage imageNamed:NSImageNameStatusUnavailable];
    else
        self.outputFolderStatus.image = [NSImage imageNamed:NSImageNameStatusNone];
    
    if(url)
        self.outputFolderDescription.stringValue = [[[url absoluteURL] path] stringByRemovingPercentEncoding];
    else
        self.outputFolderDescription.stringValue = @"";
}

- (IBAction)revealOutputFolder:(id)sender
{
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs: @[ [self outputFolderURL]] ];
}

#pragma mark - Watch Folder

- (IBAction)selectWatchFolder:(id)sender
{
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.canChooseDirectories = YES;
    openPanel.canCreateDirectories = YES;
    openPanel.canChooseFiles = NO;
    openPanel.message = @"Select Watch Folder";
    
    [openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if(result == NSModalResponseOK)
        {
            NSURL* outputFolderURL = [openPanel URL];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateWatchFolder:outputFolderURL];
            });
        }
    }];
}

- (IBAction)useWatchFolder:(id)sender
{
    BOOL useFolder = ([sender state] == NSOnState);
    
    [[NSUserDefaults standardUserDefaults] setValue:@(useFolder) forKey:kSynopsisAnalyzerUseWatchFolderKey];
    
    [self validateWatchFolderUI];
}

- (void) updateWatchFolder:(NSURL*)outputURL
{
    [[NSUserDefaults standardUserDefaults] setValue:[outputURL path] forKey:kSynopsisAnalyzerWatchFolderURLKey];
    
    [self validateWatchFolderUI];
}

- (BOOL) usingWatchFolder
{
    return [[[NSUserDefaults standardUserDefaults] valueForKey:kSynopsisAnalyzerUseWatchFolderKey] boolValue];
}

- (NSURL*) watchFolderURL
{
    NSString* outputPath = [[NSUserDefaults standardUserDefaults] valueForKey:kSynopsisAnalyzerWatchFolderURLKey];
    if(outputPath)
    {
        NSURL* outputURL = [NSURL fileURLWithPath:outputPath];
        BOOL isDirectory = NO;
        if([[NSFileManager defaultManager] fileExistsAtPath:outputPath isDirectory:&isDirectory])
        {
            if(isDirectory)
                return outputURL;
        }
    }

    return nil;
}

- (void) validateWatchFolderUI
{
    NSURL* watchURL = [self watchFolderURL];
    BOOL usingWatchFolder = [self usingWatchFolder];
    
    self.usingWatchFolderButton.state = ([self usingWatchFolder]) ? NSOnState : NSOffState;
    
    if(usingWatchFolder && watchURL)
        self.watchFolderStatus.image = [NSImage imageNamed:NSImageNameStatusAvailable];
    else if (usingWatchFolder && !watchURL)
        self.watchFolderStatus.image = [NSImage imageNamed:NSImageNameStatusUnavailable];
    else
        self.watchFolderStatus.image = [NSImage imageNamed:NSImageNameStatusNone];
    
    if(watchURL)
        self.watchFolderDescription.stringValue = [[[watchURL absoluteURL] path] stringByRemovingPercentEncoding];
    else
        self.watchFolderDescription.stringValue = @"";
    
    AppDelegate* appDelegate = (AppDelegate*) [[NSApplication sharedApplication] delegate];
    if(usingWatchFolder && watchURL)
    {
        self.directoryWatcher = [[SynopsisDirectoryWatcher alloc] initWithDirectoryAtURL:watchURL notificationBlock:^(NSArray<NSURL *> *changedURLS) {
            
            NSMutableArray<NSURL*>* changedValidURLs = [NSMutableArray array];
            
            for(NSURL* url in changedURLS)
            {
                NSString* uti = nil;
                NSError* error;
                if([url getResourceValue:&uti forKey:NSURLTypeIdentifierKey error:&error])
                {
                    if([[appDelegate supportedFileTypes] containsObject:uti])
                    {
                        [changedValidURLs addObject:url];
                    }
                }
            }
            
            // Kick off Analysis Session
            [appDelegate analysisSessionForFiles:changedValidURLs sessionCompletionBlock:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                   
                    NSLog(@"SESSION COMPLETE ALL SESSION MEDIA AND SUB FOLDERS TO OUTPUT FOLDER FROM TEMP WORKING FOLDER");
                    
                });
            }];
        }];
    }
    else
    {
        self.directoryWatcher = nil;
    }
}

- (IBAction) revealWatchFolder:(id)sender
{
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs: @[ [self watchFolderURL]] ];
}

#pragma mark - Actions



@end
