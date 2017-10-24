//
//  OperationStateWrapper.h
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Constants.h"
#import "PresetObject.h"

extern NSString * const kSynopsisOperationStateUpdate;

@interface OperationStateWrapper : NSObject

- (instancetype) initWithSourceFileURL:(NSURL*)sourceFileURL operationType:(OperationType)type preset:(PresetObject*)preset tempDirectory:(NSURL*)tempURL destinationDirectory:(NSURL*)destinationDirectory;

@property (readonly, copy) NSURL* sourceFileURL;
@property (readonly, assign) OperationType type;
@property (readonly, copy) PresetObject* preset;
@property (readonly, copy) NSURL* tempDirectory;
@property (readonly, copy) NSURL* destinationDirectory;

// State Tracking so our views can reflect latest operation state without needing updates
@property (atomic, readonly, copy) NSUUID* operationID;
@property (atomic, readwrite, assign) OperationState operationState;
@property (atomic, readwrite, assign) CGFloat operationProgress;
@property (atomic, readwrite, assign) NSTimeInterval elapsedTime;
@property (atomic, readwrite, assign) NSTimeInterval remainingTime;

@end 
