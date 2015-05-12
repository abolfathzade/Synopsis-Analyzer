//
//  ProgressTableViewCellRevealController.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ProgressTableViewCellRevealController : NSViewController
@property (atomic, readwrite, strong) NSURL* destinationURL;
- (IBAction)revealDestinationURL:(id)sender;

@end
