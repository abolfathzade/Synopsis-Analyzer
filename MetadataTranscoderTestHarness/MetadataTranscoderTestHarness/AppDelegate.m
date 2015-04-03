//
//  AppDelegate.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>

#import "SampleBufferAnalyzerPluginProtocol.h"

#import "TranscodeOperation.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (atomic, readwrite, strong) NSOperationQueue* transcodeQueue;

@property (atomic, readwrite, strong) NSMutableArray* analyzerPlugins;

@end

@implementation AppDelegate

- (id) init
{
    self = [super init];
    if(self)
    {
        // Serial transcode queue
        self.transcodeQueue = [[NSOperationQueue alloc] init];
        self.transcodeQueue.maxConcurrentOperationCount = 1;
        self.analyzerPlugins = [NSMutableArray new];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    // Load our plugins
    NSString* pluginsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    
    NSError* error = nil;
    
    NSArray* possiblePlugins = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:pluginsPath error:&error];
    
    if(!error)
    {
        for(NSString* possiblePlugin in possiblePlugins)
        {
            NSBundle* pluginBundle = [NSBundle bundleWithPath:possiblePlugin];
            
            NSError* loadError = nil;
            if([pluginBundle preflightAndReturnError:&loadError])
            {
                if([pluginBundle loadAndReturnError:&loadError])
                {
                    // Weve sucessfully loaded our bundle, time to make a plugin instance
                    Class pluginClass = pluginBundle.principalClass;
                    
                    id<SampleBufferAnalyzerPluginProtocol> pluginInstance = [[pluginClass alloc] init];
                
                    if(pluginInstance)
                    {
                        [self.analyzerPlugins addObject:pluginInstance];
                    }
                }
                else
                {
                    NSLog(@"Error Loading Plugin : %@ : %@", [pluginsPath lastPathComponent], loadError);
                }
            }
            else
            {
                NSLog(@"Error Preflighting Plugin : %@ : %@", [pluginsPath lastPathComponent], loadError);
            }
            
            //id<SampleBufferAnalyzerPluginProtocol> = [NSBundle ]
        }
    }
    
    // Open a movie or two    
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    
    [openPanel setAllowsMultipleSelection:YES];
    [openPanel setAllowedFileTypes:@[@"mov", @"mp4", @"m4v"]];
    
    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result)
    {
        if (result == NSFileHandlingPanelOKButton)
        {
            for(NSURL* fileurl in openPanel.URLs)
            {
                [self enqueueFileForTranscode:fileurl];
            }
        }
    }];
    
}

- (void) enqueueFileForTranscode:(NSURL*)fileURL
{
    NSString* lastPath = [fileURL lastPathComponent];
    NSString* lastPathExtention = [fileURL pathExtension];
    lastPath = [lastPath stringByAppendingString:@"_transcoded"];
    
    NSURL* destinationURL = [fileURL URLByDeletingLastPathComponent];
    destinationURL = [destinationURL URLByDeletingPathExtension];
    
    destinationURL = [[destinationURL URLByAppendingPathComponent:lastPath] URLByAppendingPathExtension:lastPathExtention];
                             
    TranscodeOperation* transcodeOp = [[TranscodeOperation alloc] initWithSourceURL:fileURL destinationURL:destinationURL transcodeOptions:nil availableAnalyzers:self.analyzerPlugins];
    
    [self.transcodeQueue addOperation:transcodeOp];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end
