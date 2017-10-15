//
//  OperationStateWrapper.h
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Constants.h"
extern NSString* const kSynopsisSessionProgressUpdate;

@interface OperationStateWrapper : NSObject

@property (readonly, assign) OperationState operationState;
@property (readonly, assign) NSUUID* operationID;
@property (readonly, assign) CGFloat operationProgress;

@end
