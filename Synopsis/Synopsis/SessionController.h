//
//  SessionController.h
//  Synopsis Analyzer
//
//  Created by vade on 10/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SessionStateWrapper.h"

//extern NSString* const kSynopsisSessionAvailable;
extern NSString* const kSynopsisSessionProgressUpdate;

@interface SessionController : NSObject<NSOutlineViewDelegate,NSOutlineViewDataSource>

- (void) addNewSession:(SessionStateWrapper*)newSessionState;
- (NSArray<SessionStateWrapper*>*)sessions;
@end
