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

+ (DispatchQueueManager*) analysisManager
{
    static dispatch_once_t once;
    
    static DispatchQueueManager* analysisManager;

    dispatch_once(&once, ^{
        analysisManager = [[self alloc] init];
    });

    return analysisManager;
}

+ (DispatchQueueManager*) metadataManager
{
    static dispatch_once_t once;
    
    static DispatchQueueManager* metadataManager;
    
    dispatch_once(&once, ^{
        metadataManager = [[self alloc] init];
    });
    
    return metadataManager;
}


- (instancetype) init
{
    self = [super init];
    if( self )
    {
        // init dispatch queues
        self.videoPassthroughDecodeQueue =  dispatch_queue_create("videoPassthroughDecodeQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        self.videoPassthroughEncodeQueue = dispatch_queue_create("videoPassthroughEncodeQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        self.videoUncompressedDecodeQueue = dispatch_queue_create("videoUncompressedDecodeQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);

        self.audioPassthroughDecodeQueue = dispatch_queue_create("audioPassthroughDecodeQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        self.audioPassthroughEncodeQueue = dispatch_queue_create("audioPassthroughEncodeQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        self.audioUncompressedDecodeQueue = dispatch_queue_create("audioUncompressedDecodeQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);

        self.concurrentVideoAnalysisQueue = dispatch_queue_create("concurrentVideoAnalysisQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        self.concurrentAudioAnalysisQueue = dispatch_queue_create("concurrentAudioAnalysisQueue", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
    }

    return self;
}

@end
