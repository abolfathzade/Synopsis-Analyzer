//
//  SessionStateWrapper.m
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "SessionStateWrapper.h"

@interface SessionStateWrapper ()
@property (readwrite, copy) NSUUID* sessionID;
@property (readwrite, copy) NSString* sessionName;
@property (readwrite, assign) SessionState sessionState;
@property (readwrite, assign) CGFloat sessionProgress;
@end

@implementation SessionStateWrapper

//- (instancetype) initWithSessionOperations:(NSArray<OperationStateWrapper*>*)operations
- (instancetype) init
{
    self = [super init];
    if(self)
    {
        self.sessionState = SessionStateUnknown;
        self.sessionID = [NSUUID UUID];
        self.sessionProgress = 0.0;
        // register for
    }
    return self;
}

@end
