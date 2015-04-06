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

#import "AnalysisAndTranscodeOperation.h"

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
                        
                        NSLog(@"Loaded Plugin: %@", pluginInstance.pluginName);
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
    
    // Pass 1 is our analysis pass, and our decode pass
    NSDictionary* transcodeOptions = @{
                                             // Passthrough Video for now
                                             kMetavisualVideoTranscodeSettingsKey : [NSNull null],
                                             // Passthrough Audio for now
                                             kMetavisualAudioTranscodeSettingsKey : [NSNull null],
                                             };
    
    AnalysisAndTranscodeOperation* analysis = [[AnalysisAndTranscodeOperation alloc] initWithSourceURL:fileURL
                                                               destinationURL:destinationURL
                                                             transcodeOptions:transcodeOptions
                                                           availableAnalyzers:self.analyzerPlugins];
    
    // pass2 is depended on pass one being complete, and on pass1's analyzed metadata
    analysis.completionBlock = (^(void)
    {
        // Log our metadata
        NSLog(@"Video Sample Buffer Metadata : %@", analysis.analyzedVideoSampleBufferMetadata);
        
//        NSDictionary* pass2TranscodeOptions = @{
//                                                kMetavisualVideoTranscodeSettingsKey : [NSNull null],
//                                                 // Passthrough Audio
//                                                 kMetavisualAudioTranscodeSettingsKey : [NSNull null],
//                                                 // Video Metadata
//                                                 kMetavisualAnalyzedVideoSampleBufferMetadataKey : pass1.analyzedVideoSampleBufferMetadata,
//                                                 // Audio Metadata
//                                                 kMetavisualAnalyzedAudioSampleBufferMetadataKey : pass1.analyzedAudioSampleBufferMetadata,
//                                                 // Global / Summary Metadata
//                                                 kMetavisualAnalyzedGlobalMetadataKey : pass1.analyzedGlobalMetadata
//                                                 };
//
//        AnalysisAndTranscodeOperation* pass2 = [[AnalysisAndTranscodeOperation alloc] initWithSourceURL:fileURL destinationURL:destinationURL transcodeOptions:nil availableAnalyzers:self.analyzerPlugins];
//        
//        [self.transcodeQueue addOperation:pass2];

    });
    
    [self.transcodeQueue addOperation:analysis];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end
