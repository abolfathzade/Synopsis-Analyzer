//
//  ProgressTableViewCellProgressController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/11/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "ProgressTableViewCellProgressController.h"
#import "BaseTranscodeOperation.h"

@interface ProgressTableViewCellProgressController ()
@property (weak) IBOutlet NSProgressIndicator* progressIndicator;
@property (weak) IBOutlet NSTextField* timeRemaining;

@end

@implementation ProgressTableViewCellProgressController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void) viewDidAppear
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateProgress:) name:kSynopsisTranscodeOperationProgressUpdate object:nil];
}

- (void) viewDidDisappear
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kSynopsisTranscodeOperationProgressUpdate object:nil];
}

- (void) updateProgress:(NSNotification*)notification
{
    NSDictionary* possibleUpdate = [notification object];
    NSUUID* possibleUUID = [possibleUpdate valueForKey:kSynopsisTranscodeOperationUUIDKey];
    
    if([possibleUUID isEqual:self.trackedOperationUUID])
    {
        NSNumber* currentProgress = [possibleUpdate valueForKey:kSynopsisTranscodeOperationProgressKey];
        NSNumber* currentTimeRemaining = [possibleUpdate valueForKey:kSynopsisTranscodeOperationTimeRemainingKey];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setProgress:currentProgress.floatValue];
            [self setTimeRemainingSeconds:currentTimeRemaining.doubleValue];
        });
    }
    
}

- (void) setProgress:(CGFloat)progress
{
    self.progressIndicator.doubleValue = progress;
}

- (void) setTimeRemainingSeconds:(NSTimeInterval)timeRemaining
{
    NSString* timeString = @"";
    
    if(timeRemaining == DBL_MIN)
    {
        timeString = @"Unknown";
    }

    else if(isnormal(timeRemaining))
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
