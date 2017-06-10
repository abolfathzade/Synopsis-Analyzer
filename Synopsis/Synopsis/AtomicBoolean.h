//
//  AtomicBoolean.h
//  Synopsis
//
//  Created by vade on 3/21/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AtomicBoolean : NSObject
- (instancetype)initWithValue:(BOOL)value;
- (BOOL)getValue;
- (void)setValue:(BOOL)value;
- (BOOL)compareTo:(BOOL)expected andSetValue:(BOOL)value;
- (BOOL)getAndSetValue:(BOOL)value;
@end
