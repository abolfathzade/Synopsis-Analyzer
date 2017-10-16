//
//  SessionStateWrapper.h
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OperationStateWrapper.h"
#import "FileOperationStateWrapper.h"
#import "Constants.h"

@interface SessionStateWrapper : NSObject

//- (instancetype) initWithSessionOperations:(NSArray<OperationStateWrapper*>*)operations;

@property (readonly, copy) NSString* sessionName;
@property (readonly, copy) NSUUID* sessionID;
@property (readonly, assign) SessionState sessionState;
@property (readonly, assign) CGFloat sessionProgress;
@property (readwrite, copy) NSArray<OperationStateWrapper*>* sessionOperationStates;

@property (readwrite, copy) NSArray<CopyOperationStateWrapper*>* fileCopyOperationStates;
@property (readwrite, copy) NSArray<MoveOperationStateWrapper*>* fileMoveOperationStates;

@property (nonatomic, copy, nullable) void (^sessionCompletionBlock)(void);

//@property (readwrite, copy) ((void (^)(void))) sessionCompletionBlock;

@end
