//
//  OperationStateWrapper.m
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "OperationStateWrapper.h"

@interface OperationStateWrapper ()

@property (readwrite, copy) NSURL* sourceFileURL;
@property (readwrite, assign) OperationType type;
@property (readwrite, copy) PresetObject* preset;
@property (readwrite, copy) NSURL* tempDirectory;
@property (readwrite, copy) NSURL* destinationDirectory;

@property (readwrite, assign) NSUUID* operationID;
@property (readwrite, assign) OperationState operationState;
@property (readwrite, assign) CGFloat operationProgress;
@end

@implementation OperationStateWrapper

- (instancetype) initWithSourceFileURL:(NSURL*)sourceFileURL operationType:(OperationType)type preset:(PresetObject*)preset tempDirectory:(NSURL*)tempURL destinationDirectory:(NSURL*)destinationDirectory;
{
    self = [super init];
    if(self)
    {
        self.sourceFileURL = sourceFileURL;
        self.type = type;
        self.preset = preset;
        self.tempDirectory = tempURL;
        self.destinationDirectory = destinationDirectory;
        
        self.operationState = OperationStatePending;
        self.operationProgress = 0.0;
        self.operationID = [NSUUID UUID];
    }
    return self;
}



@end
