//
//  SessionStateWrapper.h
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OperationStateWrapper.h"
#import "Constants.h"

@interface SessionStateWrapper : NSObject

- (instancetype) initWithSessionOperations:(NSArray<OperationStateWrapper*>*)operations;

@property (readonly, copy) NSString* sessionName;
@property (readonly, copy) NSUUID* sessionID;
@property (readonly, assign) SessionState sessionState;
@property (readonly, assign) CGFloat sessionProgress;
@property (readonly, strong) NSArray<OperationStateWrapper*>* sessionOperationStates;

@end
