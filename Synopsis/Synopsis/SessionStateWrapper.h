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

@property (readwrite, copy) NSString* _Nonnull sessionName;
@property (readonly, copy) NSUUID* _Nonnull sessionID;
@property (readwrite, assign) SessionState sessionState;
@property (readwrite, assign) CGFloat sessionProgress;
@property (readwrite, copy) NSArray<OperationStateWrapper*>* _Nullable sessionOperationStates;
@property (readwrite, copy) NSArray<CopyOperationStateWrapper*>* _Nullable fileCopyOperationStates;
@property (readwrite, copy) NSArray<MoveOperationStateWrapper*>* _Nullable fileMoveOperationStates;
@property (readwrite, copy) NSArray<DeleteOperationStateWrapper*>* _Nullable fileDeleteOperationStates;

@property (nonatomic, copy, nullable) void (^sessionCompletionBlock)(void);

//@property (readwrite, copy) ((void (^)(void))) sessionCompletionBlock;

@end
