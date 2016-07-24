//
//  DispatchQueueManager.m
//  Synopsis
//
//  Created by vade on 7/22/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#import "DispatchQueueManager.h"

@interface DispatchQueueManager ()
// Video
@property (readwrite) dispatch_queue_t videoPassthroughDecodeQueue;
@property (readwrite) dispatch_queue_t videoPassthroughEncodeQueue;
@property (readwrite) dispatch_queue_t videoUncompressedDecodeQueue;

// Audio
@property (readwrite) dispatch_queue_t audioPassthroughDecodeQueue;
@property (readwrite) dispatch_queue_t audioPassthroughEncodeQueue;
@property (readwrite) dispatch_queue_t audioUncompressedDecodeQueue;

// Analysis
@property (readwrite) dispatch_queue_t concurrentVideoAnalysisQueue;
@property (readwrite) dispatch_queue_t concurrentAudioAnalysisQueue;
@end

@implementation DispatchQueueManager

+ (DispatchQueueManager*) sharedManager
{
    static dispatch_once_t once;
    
    static DispatchQueueManager* sharedManager;

    dispatch_once(&once, ^{
        sharedManager = [[self alloc] init];
    });

    return sharedManager;
}

- (instancetype) init
{
    self = [super init];
    if( self )
    {
        // init dispatch queues
        self.videoPassthroughDecodeQueue =  dispatch_queue_create("videoPassthroughDecodeQueue", DISPATCH_QUEUE_CONCURRENT);
        self.videoPassthroughEncodeQueue = dispatch_queue_create("videoPassthroughEncodeQueue", DISPATCH_QUEUE_CONCURRENT);
        self.videoUncompressedDecodeQueue = dispatch_queue_create("videoUncompressedDecodeQueue", DISPATCH_QUEUE_CONCURRENT);

        self.audioPassthroughDecodeQueue = dispatch_queue_create("audioPassthroughDecodeQueue", DISPATCH_QUEUE_CONCURRENT);
        self.audioPassthroughEncodeQueue = dispatch_queue_create("audioPassthroughEncodeQueue", DISPATCH_QUEUE_CONCURRENT);
        self.audioUncompressedDecodeQueue = dispatch_queue_create("audioUncompressedDecodeQueue", DISPATCH_QUEUE_CONCURRENT);

        self.concurrentVideoAnalysisQueue = dispatch_queue_create("concurrentVideoAnalysisQueue", DISPATCH_QUEUE_CONCURRENT);
        self.concurrentAudioAnalysisQueue = dispatch_queue_create("concurrentAudioAnalysisQueue", DISPATCH_QUEUE_CONCURRENT);
    }

    return self;
}

@end
