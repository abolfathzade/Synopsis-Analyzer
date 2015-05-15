//
//  AppDelegate.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DropFilesView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, DropFileHelper>

// Drop File Helper Protocol
- (void) handleDropedFiles:(NSArray *)fileURLArray;
@end

