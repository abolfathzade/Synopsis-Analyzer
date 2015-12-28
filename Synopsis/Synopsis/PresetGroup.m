//
//  PresetGroup.m
//  Synopsis
//
//  Created by vade on 12/28/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "PresetGroup.h"

@implementation PresetGroup

- (id) initWithTitle:(NSString*)title
{
    self = [super init];
    if(self)
    {
        self.title = title;
        self.children = nil;
        return self;
    }
    return nil;
}
@end
