//
//  ProgressTableViewCellProgressController.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ProgressTableViewCellProgressController : NSViewController
@property (readwrite, atomic) NSUUID* trackedOperationUUID;
- (void) setProgress:(CGFloat)progress;
- (void) setTimeRemainingSeconds:(NSTimeInterval)timeRemaining;
@end
