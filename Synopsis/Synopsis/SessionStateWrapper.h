//
//  SessionStateWrapper.h
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Constants.h"

@interface SessionStateWrapper : NSObject
- (instancetype) initWithSessionID:(NSUUID*)sessionID sessionName:(NSString*)sessionName;
@property (readonly, copy) NSString* sessionName;
@property (readonly, assign) SessionState sessionState;
@property (readonly, assign) CGFloat sessionProgress;
@end
