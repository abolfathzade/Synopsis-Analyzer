//
//  ProgressTableViewController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "ProgressTableViewController.h"
#import "BaseTranscodeOperation.h"

#import "ProgressTableViewCellSourceController.h"
#import "ProgressTableViewCellProgressController.h"
#import "ProgressTableViewCellRevealController.h"
#import "ProgressTableViewCellPresetController.h"

@interface ProgressTableViewController ()
@property (weak) IBOutlet NSTableView* tableView;

// We dont want to hold on to our NSOperationQueues because we want to dealloc all the heavy media bullshit each one retains internally
@property (atomic, readwrite, strong) NSMutableArray* trackedOperationDescriptions;
@property (atomic, readwrite, strong) NSMutableArray* progressControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* presetControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* revealControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* sourceControllerArray;
@end

@implementation ProgressTableViewController

- (void) awakeFromNib
{
    [self commonSetup];
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kSynopsisNewTranscodeOperationAvailable object:nil];
}

// TODO: This is being run more than once from AwakeFrom Nib due to some BS in NSTableView shite
- (void) commonSetup
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        NSNib* sourceTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellSource" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:sourceTableViewCell forIdentifier:@"SourceFile"];

//        NSNib* timeRemainingTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellTimeRemaining" bundle:[NSBundle mainBundle]];
//        [self.tableView registerNib:timeRemainingTableViewCell forIdentifier:@"TimeRemaining"];
        
        NSNib* progressTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellProgress" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:progressTableViewCell forIdentifier:@"Progress"];

        NSNib* revealTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellReveal" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:revealTableViewCell forIdentifier:@"Reveal"];

        NSNib* presetTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellPreset" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:presetTableViewCell forIdentifier:@"Preset"];

        self.trackedOperationDescriptions = [NSMutableArray new];

        // Keep tabs on our controllers
        self.sourceControllerArray = [NSMutableArray new];
        self.progressControllerArray = [NSMutableArray new];
        self.revealControllerArray = [NSMutableArray new];
        self.presetControllerArray = [NSMutableArray new];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addTranscodeAndAnalysisOperation:) name:kSynopsisNewTranscodeOperationAvailable object:nil];
    });
}

- (void)addTranscodeAndAnalysisOperation:(NSNotification*)notification
{    
    @synchronized(_trackedOperationDescriptions)
    {
        [self.trackedOperationDescriptions addObject:[notification.object copy]];
    }
    
    [self.tableView beginUpdates];
    
    NSIndexSet* rowSet = [[NSIndexSet alloc] initWithIndex:[self.tableView numberOfRows]];

    [self.tableView insertRowsAtIndexes:rowSet withAnimation:NSTableViewAnimationEffectNone];
    
    [self.tableView endUpdates];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSDictionary* operationDescription = [self.trackedOperationDescriptions objectAtIndex:row];
    NSView* result = nil;
    
    if([tableColumn.identifier isEqualToString:@"SourceFile"])
    {
        ProgressTableViewCellSourceController* controller = nil;

        // find our cached controller if we have one
        if(self.sourceControllerArray.count > row)
        {
            controller = self.sourceControllerArray[row];
        }
        
        if(!controller)
        {
            // cache if we dont have...
            controller = [[ProgressTableViewCellSourceController alloc] init];
            self.sourceControllerArray[row] = controller;
        }
        
        result = [tableView makeViewWithIdentifier:@"SourceFile" owner:controller];
        
        if(operationDescription)
        {
            NSURL* sourceURL = [operationDescription valueForKey:kSynopsisTranscodeOperationSourceURLKey];
            [controller setSourceFileName:[sourceURL lastPathComponent]];
        }
    }
    
    else  if([tableColumn.identifier isEqualToString:@"Progress"])
    {
        // find our cached controller if we have one
        ProgressTableViewCellProgressController* controller = nil;
        
        if(self.progressControllerArray.count > row)
        {
            controller = self.progressControllerArray[row];
        }
        
        if(!controller)
        {
            // cache if we dont have...
            controller = [[ProgressTableViewCellProgressController alloc] init];
            controller.trackedOperationUUID = [operationDescription valueForKey:kSynopsisTranscodeOperationUUIDKey];
            self.progressControllerArray[row] = controller;
        }

         result = [tableView makeViewWithIdentifier:@"Progress" owner:controller];
    }
    
    else  if([tableColumn.identifier isEqualToString:@"Preset"])
    {
        // find our cached controller if we have one
        ProgressTableViewCellPresetController* controller = nil;
        if(self.presetControllerArray.count > row)
        {
            controller = self.presetControllerArray[row];
        }
        
        if(!controller)
        {
            // cache if we dont have...
            controller = [[ProgressTableViewCellPresetController alloc] init];
            self.revealControllerArray[row] = controller;
        }

        result = [tableView makeViewWithIdentifier:@"Preset" owner:controller];
        
//        if(operationForRow)
//        {
//            NSURL* destinationURL = operationForRow.destinationURL;
//            controller.destinationURL = destinationURL;
//        }
    }

    
    return result;
}

#pragma mark - NSTableViewDataSource

//- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
//{
//    NSUInteger count = 0;
//    @synchronized(_trackedOperationDescriptions)
//    {
//        count = self.trackedOperationDescriptions.count;
//    }
//    
//    return count;
//}
@end
