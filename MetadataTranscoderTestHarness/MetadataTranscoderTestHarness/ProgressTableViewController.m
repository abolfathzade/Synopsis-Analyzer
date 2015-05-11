//
//  ProgressTableViewController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "ProgressTableViewController.h"
#import "ProgressTableViewCellSourceController.h"

@interface ProgressTableViewController ()
@property (weak) IBOutlet NSTableView* tableView;

@property (atomic, readwrite, strong) NSMutableArray* transcodeAndAnalysisOperations;
@end

@implementation ProgressTableViewController

- (void) awakeFromNib
{
    NSLog(@"AwakeFromNib");
    [self commonSetup];
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"MVNewTranscodeOperationAvailable" object:nil];
}

// TODO: This is being run more than once from AwakeFrom Nib due to some BS in NSTableView shite
- (void) commonSetup
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        NSLog(@"Common Setup");
        
        NSNib* sourceTableViewCell = [[NSNib alloc] initWithNibNamed:@"ProgressTableViewCellSource" bundle:[NSBundle mainBundle]];
        [self.tableView registerNib:sourceTableViewCell forIdentifier:@"SourceFile"];
        
        
        
        self.transcodeAndAnalysisOperations = [NSMutableArray new];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addTranscodeAndAnalysisOperation:) name:@"MVNewTranscodeOperationAvailable" object:nil];
    });
    
}

- (void)addTranscodeAndAnalysisOperation:(NSNotification*)notification
{
    NSLog(@"Recieve NOTIFICATION %@", notification);
    
    @synchronized(_transcodeAndAnalysisOperations)
    {
        [self.transcodeAndAnalysisOperations addObject:notification.object];
    }
    
    [self.tableView beginUpdates];
    
    NSIndexSet* rowSet = [[NSIndexSet alloc] initWithIndex:[self numberOfRowsInTableView:self.tableView]];

    [self.tableView insertRowsAtIndexes:rowSet withAnimation:NSTableViewAnimationEffectFade];
    
    [self.tableView endUpdates];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if([tableColumn.identifier isEqualToString:@"SourceFile"])
    {
        ProgressTableViewCellSourceController* controller = [[ProgressTableViewCellSourceController alloc] init];
        NSView* result = [tableView makeViewWithIdentifier:@"SourceFile" owner:controller];
        
        [controller setSourceFileName:@"Some Source File !@#@"];
        
        // Return the result
        return result;
    }
    
    return nil;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    NSUInteger count = 0;
    @synchronized(_transcodeAndAnalysisOperations)
    {
        count = self.transcodeAndAnalysisOperations.count;
    }
    
    return count;
}
@end
