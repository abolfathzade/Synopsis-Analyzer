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

extern NSString* const kSynopsisSessionProgressUpdate;

@interface OperationStateWrapper : NSObject

- (instancetype) initWithSourceFileURL:(NSURL*)sourceFileURL operationType:(OperationType)type preset:(PresetObject*)preset tempDirectory:(NSURL*)tempURL destinationDirectory:(NSURL*)destinationDirectory;

@property (readonly, copy) NSURL* sourceFileURL;
@property (readonly, assign) OperationType type;
@property (readonly, copy) PresetObject* preset;
@property (readonly, copy) NSURL* tempDirectory;
@property (readonly, copy) NSURL* destinationDirectory;

// Optional move source / dest for OperationTypeFolderToTempToOutput
@property (readwrite, copy) NSURL* moveSrc;
@property (readwrite, copy) NSURL* moveDst;

@property (readonly, assign) OperationState operationState;
@property (readonly, assign) NSUUID* operationID;
@property (readonly, assign) CGFloat operationProgress;

@end 
