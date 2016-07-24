//
//  DispatchQueueManager.h
//  Synopsis
//
//  Created by vade on 7/22/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DispatchQueueManager : NSObject

// Video
@property (readonly) dispatch_queue_t videoPassthroughDecodeQueue;
@property (readonly) dispatch_queue_t videoPassthroughEncodeQueue;
@property (readonly) dispatch_queue_t videoUncompressedDecodeQueue;

// Audio
@property (readonly) dispatch_queue_t audioPassthroughDecodeQueue;
@property (readonly) dispatch_queue_t audioPassthroughEncodeQueue;
@property (readonly) dispatch_queue_t audioUncompressedDecodeQueue;

// Analysis
@property (readonly) dispatch_queue_t concurrentVideoAnalysisQueue;
@property (readonly) dispatch_queue_t concurrentAudioAnalysisQueue;

+ (DispatchQueueManager*) sharedManager;

@end
