//
//  OperationView.h
//  Synopsis Analyzer
//
//  Created by vade on 10/16/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OperationStateWrapper.h"

@interface OperationRowView : NSView

@property (readwrite, strong) OperationStateWrapper* operationState;

- (void) beginOperationStateListening;
- (void) endOperationStateListening;

@end
