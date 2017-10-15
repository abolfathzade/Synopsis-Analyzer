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
@property (atomic, readwrite, strong) NSMutableArray* trackedOperationUUIDs;
@property (atomic, readwrite, strong) NSMutableArray* progressControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* presetControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* revealControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* sourceControllerArray;

//NEED a way to handle state from notifications so when cells are created they are udpated with the appropriate state
@end

@implementation ProgressTableViewController

- (void) awakeFromNib
{
//    [self commonSetup];
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
        self.trackedOperationUUIDs = [NSMutableArray new];

        // Keep tabs on our controllers
        self.sourceControllerArray = [NSMutableArray new];
        self.progressControllerArray = [NSMutableArray new];
        self.revealControllerArray = [NSMutableArray new];
        self.presetControllerArray = [NSMutableArray new];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addTranscodeAndAnalysisOperation:) name:kSynopsisNewTranscodeOperationAvailable object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTrackedOperationState:) name:kSynopsisTranscodeOperationProgressUpdate object:nil];
    });
}

- (void)addTranscodeAndAnalysisOperation:(NSNotification*)notification
{
    NSDictionary* operationDescription = [notification object];
    
    NSUUID* opID = [operationDescription valueForKey:kSynopsisTranscodeOperationUUIDKey];
    
    NSInteger index = [self.trackedOperationUUIDs indexOfObject:opID];
    if(index == NSNotFound)
    {
        [self.trackedOperationDescriptions addObject:operationDescription];
        [self.trackedOperationUUIDs addObject:opID];
        
        [self.tableView beginUpdates];
        
        NSIndexSet* rowSet = [[NSIndexSet alloc] initWithIndex:[self.tableView numberOfRows]];
        
        [self.tableView.animator insertRowsAtIndexes:rowSet withAnimation:NSTableViewAnimationEffectGap | NSTableViewAnimationSlideDown ];
        
        [self.tableView endUpdates];
    }
    else
    {
        [self updateTrackedOperationState:notification];
    }
}

- (void) updateTrackedOperationState:(NSNotification*)notification
{
    NSDictionary* operationDescription = [notification object];
    
    NSUUID* opID = [operationDescription valueForKey:kSynopsisTranscodeOperationUUIDKey];
    
    // if we have have an operation, update it
    NSInteger index = [self.trackedOperationUUIDs indexOfObject:opID];
    if(index != NSNotFound)
    {
        [self.trackedOperationDescriptions replaceObjectAtIndex:index withObject:operationDescription];
    }
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSDictionary* operationDescription = [self.trackedOperationDescriptions  objectAtIndex:row];
    NSView* result = nil;
    
    if(operationDescription == nil)
        return nil;
    
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
        
        NSURL* sourceURL = [operationDescription valueForKey:kSynopsisTranscodeOperationSourceURLKey];
        [controller setSourceFileName:[sourceURL lastPathComponent]];
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
            self.progressControllerArray[row] = controller;
        }

        result = [tableView makeViewWithIdentifier:@"Progress" owner:controller];

        // update controller state regardless if we just made it or not
        controller.trackedOperationUUID = [operationDescription valueForKey:kSynopsisTranscodeOperationUUIDKey];
        [controller setProgress:[[operationDescription valueForKey:kSynopsisTranscodeOperationProgressKey] floatValue] ];
        [controller setTimeRemainingSeconds:[[operationDescription valueForKey:kSynopsisTranscodeOperationTimeRemainingKey] doubleValue] ];
        
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
            self.presetControllerArray[row] = controller;
        }

        result = [tableView makeViewWithIdentifier:@"Preset" owner:controller];
        
    }
    else  if([tableColumn.identifier isEqualToString:@"Reveal"])
    {
        // find our cached controller if we have one
        ProgressTableViewCellRevealController* controller = nil;
        if(self.revealControllerArray.count > row)
        {
            controller = self.revealControllerArray[row];
        }
        
        if(!controller)
        {
            // cache if we dont have...
            controller = [[ProgressTableViewCellRevealController alloc] init];
            self.revealControllerArray[row] = controller;
        }
        
        result = [tableView makeViewWithIdentifier:@"Reveal" owner:controller];

        NSURL* destinationURL = operationDescription[kSynopsisTranscodeOperationDestinationURLKey];
        controller.destinationURL = destinationURL;
    }
    
    return result;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
//    NSUInteger count = 0;
//    @synchronized(_trackedOperationDescriptions)
//    {
//        count = self.trackedOperationDescriptions.count;
//    }
//    
//    return count;
    
    return self.trackedOperationDescriptions.count;
}
@end
