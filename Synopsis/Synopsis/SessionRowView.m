//
//  SessionRowView.m
//  Synopsis Analyzer
//
//  Created by vade on 10/16/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "SessionRowView.h"

@interface SessionRowView ()
@property (readwrite, assign) IBOutlet NSProgressIndicator* progress;
@property (readwrite, assign) IBOutlet NSTextField* name;
@end

@implementation SessionRowView

- (void) beginSessionStateListening
{
    [self updateUIFromState];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionStateUpdate:) name:kSynopsisOperationStateUpdate object:nil];
}

- (void) endSessionStateListening
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kSynopsisOperationStateUpdate object:nil];

    self.sessionState = nil;
    self.progress.doubleValue = 0.0;
    self.name.stringValue = @"";
}

- (void) sessionStateUpdate:(NSNotification*)notification
{
    OperationStateWrapper* updatedState = (OperationStateWrapper*)notification.object;

    if(updatedState)
    {
        BOOL sessionContainsOperation = NO;
        
        for(OperationStateWrapper* operationState in self.sessionState.sessionOperationStates)
        {
            if([updatedState.operationID isEqual:operationState.operationID])
            {
                sessionContainsOperation = YES;
                break;
            }
        }
        
        if(sessionContainsOperation)
        {
            double progress = 0.0;
            for(OperationStateWrapper* operationState in self.sessionState.sessionOperationStates)
            {
                progress += operationState.operationProgress;
            }
            
            progress /= self.sessionState.sessionOperationStates.count;
            
            self.sessionState.sessionProgress = progress;
            [self updateUIFromState];
        }
    }
}

- (void) updateUIFromState
{
    self.name.stringValue = self.sessionState.sessionName;
    self.progress.doubleValue = self.sessionState.sessionProgress;
}

@end
