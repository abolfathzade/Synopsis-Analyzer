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
@interface ProgressTableViewController ()
@property (weak) IBOutlet NSTableView* tableView;

// We dont want to hold on to our NSOperationQueues because we want to dealloc all the heavy media bullshit each one retains internally
@property (atomic, readwrite, strong) NSPointerArray* transcodeAndAnalysisOperationsWeak;
@property (atomic, readwrite, strong) NSMutableArray* sourceControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* progressControllerArray;
@property (atomic, readwrite, strong) NSMutableArray* revealControllerArray;
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

        NSNib* timeRemainingTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellTimeRemaining" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:timeRemainingTableViewCell forIdentifier:@"TimeRemaining"];
        
        NSNib* progressTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellProgress" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:progressTableViewCell forIdentifier:@"Progress"];

        NSNib* revealTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellReveal" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:revealTableViewCell forIdentifier:@"Reveal"];

        // We dont want to hold on to our NSOperationQueues because we want to dealloc all the heavy media bullshit each one retains internally
        self.transcodeAndAnalysisOperationsWeak = [[NSPointerArray alloc] initWithOptions:NSPointerFunctionsWeakMemory];

        // Keep tabs on our controllers
        self.sourceControllerArray = [NSMutableArray new];
        self.progressControllerArray = [NSMutableArray new];
        self.revealControllerArray = [NSMutableArray new];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addTranscodeAndAnalysisOperation:) name:kSynopsisNewTranscodeOperationAvailable object:nil];
    });
    
}

- (void)addTranscodeAndAnalysisOperation:(NSNotification*)notification
{    
    @synchronized(_transcodeAndAnalysisOperationsWeak)
    {
        [self.transcodeAndAnalysisOperationsWeak addPointer:(__bridge void *)(notification.object)];
    }
    
    [self.tableView beginUpdates];
    
    NSIndexSet* rowSet = [[NSIndexSet alloc] initWithIndex:[self numberOfRowsInTableView:self.tableView]];

    [self.tableView insertRowsAtIndexes:rowSet withAnimation:NSTableViewAnimationEffectFade];
    
    [self.tableView endUpdates];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    BaseTranscodeOperation* operationForRow = [self.transcodeAndAnalysisOperationsWeak pointerAtIndex:row];
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
        
        if(operationForRow)
        {
            NSURL* sourceURL = operationForRow.sourceURL;
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
            self.progressControllerArray[row] = controller;
        }

         result = [tableView makeViewWithIdentifier:@"Progress" owner:controller];
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
        
        if(operationForRow)
        {
            NSURL* destinationURL = operationForRow.destinationURL;
            controller.destinationURL = destinationURL;
        }
    }

    // Set up our callbacks if we need to.
    if(operationForRow)
    {
        // set up our callback
        operationForRow.progressBlock = ^void(CGFloat progress)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                ProgressTableViewCellProgressController* progressController = self.progressControllerArray[row];
                
                if(progressController)
                {
                    [progressController setProgress:progress];
                    [progressController setTimeRemainingSeconds:operationForRow.remainingTime];
                }
            });
        };
    }

    
    return result;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    NSUInteger count = 0;
    @synchronized(_transcodeAndAnalysisOperationsWeak)
    {
        count = self.transcodeAndAnalysisOperationsWeak.count;
    }
    
    return count;
}
@end
