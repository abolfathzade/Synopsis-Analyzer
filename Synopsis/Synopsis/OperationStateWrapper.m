//
//  OperationStateWrapper.m
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "OperationStateWrapper.h"

@interface OperationStateWrapper ()
@property (readwrite, assign) NSUUID* operationID;
@property (readwrite, assign) OperationState operationState;
@property (readwrite, assign) CGFloat operationProgress;
@end

@implementation OperationStateWrapper

- (instancetype) initWithOperationID:(NSUUID*)operationID
{
    self = [super init];
    if(self)
    {
        self.operationState = OperationStatePending;
        self.operationProgress = 0.0;
        self.operationID = [NSUUID UUID];
    }
    return self;
}



@end
