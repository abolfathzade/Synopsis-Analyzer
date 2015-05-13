//
//  DropFilesView.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/12/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "DropFilesView.h"

@implementation DropFilesView

- (void)drawRect:(NSRect)rect {

    // Following code courtesey of ImageOptim - thanks!
    
    BOOL highlight = NO;
    
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(rect);
    
    NSColor *gray = [NSColor colorWithDeviceWhite:0 alpha:highlight ? 1.0/4.0 : 1.0/8.0];
    [gray set];
    [gray setFill];
    
    NSRect bounds = [self bounds];
    CGFloat size = MIN(bounds.size.width/4.0, bounds.size.height/1.5);
    CGFloat width = MAX(2.0, size/32.0);
    NSRect frame = NSMakeRect((bounds.size.width-size)/2.0, (bounds.size.height-size)/2.0, size, size);
    
    BOOL smoothSizes = YES;
    if (!smoothSizes) {
        width = round(width);
        size = ceil(size);
        frame = NSMakeRect(round(frame.origin.x)+((int)width&1)/2.0, round(frame.origin.y)+((int)width&1)/2.0, round(frame.size.width), round(frame.size.height));
    }
    
    [NSBezierPath setDefaultLineWidth:width];
    
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:frame xRadius:size/14.0 yRadius:size/14.0];
    const CGFloat dash[2] = {size/10.0, size/16.0};
    [p setLineDash:dash count:2 phase:2];
    [p stroke];
    
    NSBezierPath *r = [NSBezierPath bezierPath];
    CGFloat baseWidth=size/8.0, baseHeight = size/8.0, arrowWidth=baseWidth*2, pointHeight=baseHeight*3.0, offset=-size/8.0;
    [r moveToPoint:NSMakePoint(bounds.size.width/2.0 - baseWidth, bounds.size.height/2.0 + baseHeight - offset)];
    [r lineToPoint:NSMakePoint(bounds.size.width/2.0 + baseWidth, bounds.size.height/2.0 + baseHeight - offset)];
    [r lineToPoint:NSMakePoint(bounds.size.width/2.0 + baseWidth, bounds.size.height/2.0 - baseHeight - offset)];
    [r lineToPoint:NSMakePoint(bounds.size.width/2.0 + arrowWidth, bounds.size.height/2.0 - baseHeight - offset)];
    [r lineToPoint:NSMakePoint(bounds.size.width/2.0, bounds.size.height/2.0 - pointHeight - offset)];
    [r lineToPoint:NSMakePoint(bounds.size.width/2.0 - arrowWidth, bounds.size.height/2.0 - baseHeight - offset)];
    [r lineToPoint:NSMakePoint(bounds.size.width/2.0 - baseWidth, bounds.size.height/2.0 - baseHeight - offset)];
    [r fill];
}

@end
