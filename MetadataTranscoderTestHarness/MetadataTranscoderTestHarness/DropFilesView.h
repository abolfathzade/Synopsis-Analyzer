//
//  DropFilesView.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/12/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//
#import <Cocoa/Cocoa.h>

@protocol DropFileHelper <NSObject>

@required
- (void) handleDropedFiles:(NSArray*)fileURLArray;
@end


@interface DropFilesView : NSView<NSDraggingDestination>
@property (weak) id<DropFileHelper> dragDelegate;
@end
