//
//  AppDelegate.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DropFilesView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, DropFileHelper>

- (void) analysisSessionForFiles:(NSArray *)fileURLArray sessionCompletionBlock:(void (^)(void))completionBlock;

@end


