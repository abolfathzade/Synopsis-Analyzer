//
//  OperationStateWrapper.m
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "OperationStateWrapper.h"
#import "BaseTranscodeOperation.h"

NSString * const kSynopsisOperationStateUpdate = @"kSynopsisOperationStateUpdate";


@interface OperationStateWrapper ()

@property (readwrite, copy) NSURL* sourceFileURL;
@property (readwrite, assign) OperationType type;
@property (readwrite, copy) PresetObject* preset;
@property (readwrite, copy) NSURL* tempDirectory;
@property (readwrite, copy) NSURL* destinationDirectory;

@property (atomic, readwrite, copy) NSUUID* operationID;
//@property (atomic, readwrite, assign) OperationState operationState;
//@property (atomic, readwrite, assign) CGFloat operationProgress;
//@property (atomic, readwrite, assign) NSTimeInterval elapsedTime;
//@property (atomic, readwrite, assign) NSTimeInterval remainingTime;
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
        self.operationProgress = DBL_MIN;
        self.operationID = [NSUUID UUID];
        
        // Subscribe to notifications from our NSOperation - filter to match UUID
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(operationStateUpdate:) name:kSynopsisTranscodeOperationProgressUpdate object:nil];

    }
    return self;
}

- (void) operationStateUpdate:(NSNotification*)notification
{
    NSDictionary* updateOperationDict = (NSDictionary*)notification.object;
    
    if(updateOperationDict)
    {
        NSUUID* updateOperationUUID = updateOperationDict[kSynopsisTranscodeOperationUUIDKey];
        
        if(updateOperationUUID && [self.operationID isEqualTo:updateOperationUUID])
        {
            self.operationProgress = [updateOperationDict[kSynopsisTranscodeOperationProgressKey] doubleValue];;
            self.remainingTime = [updateOperationDict[kSynopsisTranscodeOperationTimeRemainingKey] doubleValue];
        }
    }
    
    // Post our own update
    [[NSNotificationCenter defaultCenter] postNotificationName:kSynopsisOperationStateUpdate object:self];
}


@end
