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
    self.name.stringValue = self.sessionState.sessionName;
    [self updateUIFromState];
    
    for(OperationStateWrapper* operationState in self.sessionState.sessionOperationStates)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionStateUpdate:) name:kSynopsisOperationStateUpdate object:operationState];
}

- (void) endSessionStateListening
{
    for(OperationStateWrapper* operationState in self.sessionState.sessionOperationStates)
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kSynopsisOperationStateUpdate object:operationState];

    self.sessionState = nil;
    self.progress.doubleValue = 0.0;
    self.name.stringValue = @"";
}

- (void) sessionStateUpdate:(NSNotification*)notification
{
//    OperationStateWrapper* updatedState = (OperationStateWrapper*)notification.object;
//
//    if(updatedState)
//    {
//        BOOL sessionContainsOperation = NO;
//
//        for(OperationStateWrapper* operationState in self.sessionState.sessionOperationStates)
//        {
//            if([updatedState isEqual:operationState])
//            {
//                sessionContainsOperation = YES;
//                break;
//            }
//        }
//
//        if(sessionContainsOperation)
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
//    }
}

- (void) updateUIFromState
{
    self.progress.doubleValue = self.sessionState.sessionProgress;
}

@end
