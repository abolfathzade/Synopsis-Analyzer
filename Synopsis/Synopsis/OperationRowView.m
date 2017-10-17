//
//  OperationView.m
//  Synopsis Analyzer
//
//  Created by vade on 10/16/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "OperationRowView.h"

@interface OperationRowView ()
@property (readwrite, assign) IBOutlet NSProgressIndicator* progress;
@property (readwrite, assign) IBOutlet NSTextField* name;
@property (readwrite, assign) IBOutlet NSTextField* timeRemaining;
@end

@implementation OperationRowView

- (void) beginOperationStateListening
{
    [self updateUIFromState];

    [self setTimeRemainingSeconds:self.operationState.remainingTime];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(operationStateUpdate:) name:kSynopsisOperationStateUpdate object:nil];
}

- (void) endOperationStateListening
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kSynopsisOperationStateUpdate object:nil];
    
    self.operationState = nil;
    self.timeRemaining.stringValue = @"Pending";
    self.progress.doubleValue = 0.0;
    self.name.stringValue = @"";
}

- (void) operationStateUpdate:(NSNotification*)notification
{
    OperationStateWrapper* updatedState = (OperationStateWrapper*)notification.object;
    
    if(updatedState && [self.operationState.operationID isEqualTo:updatedState.operationID])
    {
        self.operationState = updatedState;
        [self updateUIFromState];
    }
}

- (void) updateUIFromState
{
    self.name.stringValue = [self.operationState.sourceFileURL lastPathComponent];
    self.progress.doubleValue = self.operationState.operationProgress;
    [self setTimeRemainingSeconds: self.operationState.remainingTime];
}

- (void) setTimeRemainingSeconds:(NSTimeInterval)timeRemaining
{
    NSString* timeString = @"";
    
    if(timeRemaining == DBL_MIN)
    {
        timeString = @"Pending";
    }
    
    else if(isnormal(timeRemaining))
    {
        self.operationState.operationState = OperationStateRunning;
        
        NSInteger ti = (NSInteger)timeRemaining;
        NSInteger seconds = ti % 60;
        NSInteger minutes = (ti / 60) % 60;
        NSInteger hours = (ti / 3600);
        
        timeString = [NSString stringWithFormat:@"%02ld:%02ld:%02ld: Remaining", (long)hours, (long)minutes, (long)seconds];
    }
    else
    {
        self.operationState.operationState = OperationStateSuccess;

        timeString = @"Completed";
    }
    
    self.timeRemaining.stringValue = timeString;
}

- (IBAction)revealDestination:(id)sender
{
    
}

@end
