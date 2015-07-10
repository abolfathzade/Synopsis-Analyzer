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
@property (weak) IBOutlet NSTextField* timeRemaining;

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

- (void) setTimeRemainingSeconds:(NSTimeInterval)timeRemaining
{
    NSString* timeString = @"";
    
    if(!isnan(timeRemaining))
    {
        NSInteger ti = (NSInteger)timeRemaining;
        NSInteger seconds = ti % 60;
        NSInteger minutes = (ti / 60) % 60;
        NSInteger hours = (ti / 3600);

        timeString = [NSString stringWithFormat:@"%02ld:%02ld:%02ld: Remaining", (long)hours, (long)minutes, (long)seconds];
    }
    else
    {
        timeString = @"Completed";
    }
    
    self.timeRemaining.stringValue = timeString;
}


@end
