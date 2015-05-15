//
//  DropFilesView.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/12/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "DropFilesView.h"
#import <AVFoundation/AVFoundation.h>

@interface DropFilesView ()
@property (atomic, readwrite, assign) BOOL highLight;

@end

@implementation DropFilesView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self)
    {
        NSLog(@"%@", NSStringFromSelector(_cmd));
        [self registerForDraggedTypes:@[NSFilenamesPboardType]];
    }
    return self;
}

- (void) awakeFromNib
{
    [super awakeFromNib];
    
    NSLog(@"%@", NSStringFromSelector(_cmd));
    [self registerForDraggedTypes:@[NSFilenamesPboardType]];
}

- (void)dealloc
{
    [self unregisterDraggedTypes];
}

#pragma mark - Drag

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    
    NSLog(@"%@", sender.draggingPasteboard);
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSLog(@"%@", NSStringFromSelector(_cmd));

    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates
{
    return NO;
}

- (NSDragOperation) draggingEntered:(id<NSDraggingInfo>)sender
{
    NSLog(@"%@", NSStringFromSelector(_cmd));


    self.highLight = YES;
    [self setNeedsDisplay:YES];
    
    if ((NSDragOperationGeneric & [sender draggingSourceOperationMask]) == NSDragOperationGeneric)
    {

//        NSDictionary* searchOptions = @{NSPasteboardURLReadingFileURLsOnlyKey : @YES,
//                                        NSPasteboardURLReadingContentsConformToTypesKey : [AVMovie movieTypes]};
//        
//        [sender enumerateDraggingItemsWithOptions:NSDraggingItemEnumerationClearNonenumeratedImages
//                                          forView:self
//                                          classes:@[[NSURL class]]
//                                    searchOptions:searchOptions
//                                       usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
//
//                                       }];
//

        
        return NSDragOperationGeneric;
    }
    else
    {
        //since they aren't offering the type of operation we want, we have
        //to tell them we aren't interested
        return NSDragOperationNone;
    }
}

- (void) draggingExited:(id<NSDraggingInfo>)sender
{
    self.highLight = NO;
    [self setNeedsDisplay:YES];
    
    NSLog(@"%@", NSStringFromSelector(_cmd));

}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{

    NSArray* classArray = @[[NSURL class]];
    NSDictionary* searchOptions = @{NSPasteboardURLReadingFileURLsOnlyKey : @YES,
                                    NSPasteboardURLReadingContentsConformToTypesKey : [AVMovie movieTypes]};

    NSArray* urls = [[sender draggingPasteboard] readObjectsForClasses:classArray options:searchOptions];
    NSURL* fileURL=[NSURL URLFromPasteboard: [sender draggingPasteboard]];

    NSLog(@"%@", fileURL);
    
    if(self.dragDelegate)
    {
        if([self.dragDelegate respondsToSelector:@selector(handleDropedFiles:)])
        {
            [self.dragDelegate handleDropedFiles:urls];
        }
    }

    //re-draw the view with our new data
    self.highLight = NO;
    [self setNeedsDisplay:YES];
}

#pragma mark -

- (void)drawRect:(NSRect)rect {

    [super drawRect:rect];
    
    // Following code courtesey of ImageOptim - thanks!
    
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(rect);
    
    NSColor *gray = [NSColor colorWithDeviceWhite:0 alpha:(self.highLight ? 1.0/4.0 : 1.0/8.0)];
    [gray set];
    [gray setFill];
    
    NSRect bounds = [self bounds];
    CGFloat size = MIN(bounds.size.width/2.0, bounds.size.height/1.5);
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
