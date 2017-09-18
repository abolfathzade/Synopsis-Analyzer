//
//  FileWatcher.m
//  Synopsis
//
//  Created by vade on 9/14/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "DirectoryWatcher.h"

@interface DirectoryWatcher (FSEventStreamCallbackSupport)
- (void) coalescedNotificationWithChangedURLArray:(NSArray<NSURL*>*)changedUrls;
@end

#pragma mark -

void mycallback(
                ConstFSEventStreamRef streamRef,
                void *clientCallBackInfo,
                size_t numEvents,
                void *eventPaths,
                const FSEventStreamEventFlags eventFlags[],
                const FSEventStreamEventId eventIds[])
{
    @autoreleasepool
    {
        if(clientCallBackInfo != NULL)
        {
            DirectoryWatcher* watcher = (__bridge DirectoryWatcher*)(clientCallBackInfo);

            int i;
            char **paths = eventPaths;
            
            NSMutableArray* changedURLS = [NSMutableArray new];
            
            for (i = 0; i < numEvents; i++)
            {
                NSString* filePath = [[NSString alloc] initWithCString:paths[i] encoding:NSUTF8StringEncoding];
                NSURL* fileURL = [NSURL fileURLWithPath:filePath];
                [changedURLS addObject:fileURL];
            }
            
            [watcher coalescedNotificationWithChangedURLArray:changedURLS];
        }
    }
}

#pragma mark -

@interface DirectoryWatcher ()
{
    FSEventStreamRef eventStream;
}
@property (readwrite, strong) NSURL* directoryURL;
@property (readwrite, copy) FileWatchNoticiationBlock notificationBlock;

@end

@implementation DirectoryWatcher

- (instancetype) initWithDirectoryAtURL:(NSURL*)url notificationBlock:(FileWatchNoticiationBlock)notificationBlock
{
    self = [super init];
    if(self)
    {
        eventStream = NULL;
        
        if([url isFileURL])
        {
            NSNumber* isDirValue;
            NSError* error;
            if([url getResourceValue:&isDirValue forKey:NSURLIsDirectoryKey error:&error])
            {
                if([isDirValue boolValue])
                {
                    self.directoryURL = url;
                    self.notificationBlock = notificationBlock;
                    
                    //[self initDispatch];
                    [self initFSEvents];
                }
            }
        }
        else
        {
            return nil;
        }
    }
    
    return self;
}

- (void) initFSEvents
{
    if(eventStream)
    {
        FSEventStreamStop(eventStream);
        FSEventStreamRelease(eventStream);
        eventStream = NULL;
    }
    
    NSArray* paths = @[ [self.directoryURL path]];
    
    FSEventStreamContext* context = (FSEventStreamContext*) malloc(sizeof(FSEventStreamContext));
    context->info = (__bridge void*) (self);
    context->release = NULL;
    context->retain = NULL;
    context->version = 0;
    context->copyDescription = NULL;
    
    eventStream = FSEventStreamCreate(kCFAllocatorDefault,
                                      mycallback,
                                      context,
                                      (CFArrayRef)CFBridgingRetain(paths),
                                      kFSEventStreamEventIdSinceNow,
                                      1.0,
                                      kFSEventStreamCreateFlagNone | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagIgnoreSelf);
    
    FSEventStreamScheduleWithRunLoop(eventStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    FSEventStreamStart(eventStream);
}

- (void) dealloc
{
    if(eventStream)
    {
        FSEventStreamStop(eventStream);
        FSEventStreamRelease(eventStream);
        FSEventStreamInvalidate(eventStream);
        eventStream = NULL;
    }
}

- (NSArray*) enumerateDirectoryContentsReturningChanges
{
    return nil;
}

- (void) coalescedNotificationWithChangedURLArray:(NSArray<NSURL*>*)changedUrls
{
    if(self.notificationBlock)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.notificationBlock(changedUrls);
        });
    }
}



@end
