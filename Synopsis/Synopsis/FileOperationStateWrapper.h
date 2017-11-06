//
//  CopyOperationStateWrapper.h
//  Synopsis Analyzer
//
//  Created by vade on 10/16/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface CopyOperationStateWrapper : NSObject
@property (readwrite, strong) NSURL* srcURL;
@property (readwrite, strong) NSURL* dstURL;
@end

@interface MoveOperationStateWrapper : NSObject
@property (readwrite, strong) NSURL* srcURL;
@property (readwrite, strong) NSURL* dstURL;
@end

@interface DeleteOperationStateWrapper : NSObject
@property (readwrite, strong) NSURL* URL;
@end
