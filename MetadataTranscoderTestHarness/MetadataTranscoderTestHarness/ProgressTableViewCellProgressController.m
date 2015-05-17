//
//  ProgressTableViewCellProgressController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "ProgressTableViewCellProgressController.h"

@interface ProgressTableViewCellProgressController ()
@property (weak) IBOutlet NSProgressIndicator* progressIndicator;

@end

@implementation ProgressTableViewCellProgressController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (void) setProgress:(CGFloat)progress
{
    self.progressIndicator.doubleValue = progress;
}


@end
