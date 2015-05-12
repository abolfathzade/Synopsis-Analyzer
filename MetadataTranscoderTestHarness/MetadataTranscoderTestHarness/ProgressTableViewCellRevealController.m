//
//  ProgressTableViewCellRevealController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "ProgressTableViewCellRevealController.h"

@interface ProgressTableViewCellRevealController ()
@property (weak) IBOutlet NSButton* revealButton;
@end

@implementation ProgressTableViewCellRevealController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (void) dealloc
{
    NSLog(@"DEALLOCED");
}

- (IBAction)revealDestinationURL:(id)sender
{
    NSLog(@"Reveal");
    if(self.destinationURL)
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[self.destinationURL]];
}

@end
