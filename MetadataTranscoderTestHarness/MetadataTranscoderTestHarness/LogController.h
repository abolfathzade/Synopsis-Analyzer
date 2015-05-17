//
//  LogViewController.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/12/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface LogController : NSViewController

+ (LogController*) sharedLogController;

- (void) appendVerboseLog:(NSString*)log;
- (void) appendWarningLog:(NSString*)log;
- (void) appendErrorLog:(NSString*)log;
- (void) appendSuccessLog:(NSString*)log;

@end
