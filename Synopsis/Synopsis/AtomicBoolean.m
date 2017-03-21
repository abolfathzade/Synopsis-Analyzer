//
//  AtomicBoolean.m
//  Synopsis
//
//  Created by vade on 3/21/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "AtomicBoolean.h"
#import <libkern/OSAtomic.h>

@implementation AtomicBoolean {
    volatile int32_t _underlying;
}

- (instancetype) init
{
    return [self initWithValue:NO];
}

- (instancetype)initWithValue:(BOOL)value
{
    self = [super init];
    if (self != nil)
    {
        _underlying = value ? 1 : 0;
    }
    return self;
}

- (BOOL)getValue {
    @synchronized (self) {
        return _underlying != 0;
    }
}

- (void)setValue:(BOOL)value
{
    @synchronized (self) {
        // Same atomic guarantees as getValue.
        _underlying = value ? 1 : 0;
    }
}

- (BOOL)compareTo:(BOOL)expected andSetValue:(BOOL)value
{
    return OSAtomicCompareAndSwap32((expected ? 1 : 0),
                                    (value ? 1 : 0),
                                    &_underlying);
}

- (BOOL)getAndSetValue:(BOOL)value {
    while (true) {
        // We could do 'current = _underlying ? 1 : 0' to save a
        // method call but it'll most likely end up being inlined
        // anyway.
        BOOL current = [self getValue];
        if ([self compareTo:current andSetValue:value]) return current;
    }
}

@end
