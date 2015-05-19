//
//  ProgressTableViewCellRevealController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "ProgressTableViewCellRevealController.h"

@interface ProgressTableViewCellRevealController ()
@property (weak) IBOutlet NSImageView* revealButton;
@end

@implementation ProgressTableViewCellRevealController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}


- (IBAction)revealDestinationURL:(id)sender
{
    if(self.destinationURL)
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[self.destinationURL]];
}

@end
