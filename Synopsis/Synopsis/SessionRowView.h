//
//  SessionRowView.h
//  Synopsis Analyzer
//
//  Created by vade on 10/16/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SessionStateWrapper.h"
@interface SessionRowView : NSView

@property (readwrite, strong) SessionStateWrapper* sessionState;
- (void) beginSessionStateListening;
- (void) endSessionStateListening;

@end
