//
//  ProgressTableViewCellController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "ProgressTableViewCellSourceController.h"

@interface ProgressTableViewCellSourceController ()
@property (weak) IBOutlet NSTextField* sourceFileLabel;
@end

@implementation ProgressTableViewCellSourceController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (void) setSourceFileName:(NSString*)name
{
    self.sourceFileLabel.stringValue = name;
}


@end
