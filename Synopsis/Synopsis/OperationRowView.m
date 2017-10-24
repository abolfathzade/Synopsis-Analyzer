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
    self.name.stringValue = [self.operationState.sourceFileURL lastPathComponent];
    [self updateUIFromState];

    [self setTimeRemainingSeconds:self.operationState.remainingTime];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(operationStateUpdate:) name:kSynopsisOperationStateUpdate object:self.operationState];
}

- (void) endOperationStateListening
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kSynopsisOperationStateUpdate object:self.operationState];
    
    self.operationState = nil;
    self.timeRemaining.stringValue = @"Pending";
    self.progress.doubleValue = 0.0;
    self.name.stringValue = @"";
}

- (void) operationStateUpdate:(NSNotification*)notification
{
    [self updateUIFromState];
}

- (void) updateUIFromState
{
    self.progress.doubleValue = self.operationState.operationProgress;
    [self setTimeRemainingSeconds: self.operationState.remainingTime];
}

- (void) setTimeRemainingSeconds:(NSTimeInterval)timeRemaining
{
    NSString* timeString = @"";
    switch(self.operationState.operationState)
    {
        case OperationStateUnknown:
            timeString = @"Unknown";
            break;
        case OperationStatePending:
            timeString = @"Pending";
            break;
        case OperationStateSuccess:
            timeString = @"Completed";
            break;
        case OperationStateRunning:
            timeString = [self calculateTimeStringFromProgress:timeRemaining];
            break;
        case OperationStateCancelled:
            timeString = @"Cancelled";
            break;
        case OperationStateFailed:
            timeString = @"Failed";
            break;
    }
    
    self.timeRemaining.stringValue = timeString;
}

- (NSString*) calculateTimeStringFromProgress:(NSTimeInterval)timeRemaining
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
        
        timeString = [NSString stringWithFormat:@"Remaining: %02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
    else
    {
        timeString = @"Completed";
    }
    
    return timeString;
}

- (IBAction)revealDestination:(id)sender
{
    
}

@end
