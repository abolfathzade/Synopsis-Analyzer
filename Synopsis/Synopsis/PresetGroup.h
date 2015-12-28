//
//  PresetGroup.h
//  Synopsis
//
//  Created by vade on 12/28/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PresetGroup : NSObject

@property (copy) NSString* title;

@property (copy) NSArray* children;

- (id) initWithTitle:(NSString*)title NS_DESIGNATED_INITIALIZER;

@end
