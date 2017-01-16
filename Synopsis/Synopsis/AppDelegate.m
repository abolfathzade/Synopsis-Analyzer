//
//  AppDelegate.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "AppDelegate.h"

#import <Synopsis/Synopsis.h>

#import "DropFilesView.h"
#import "LogController.h"

#import "AnalysisAndTranscodeOperation.h"
#import "MetadataWriterTranscodeOperation.h"

#import "PreferencesViewController.h"
#import "PresetObject.h"

static NSTimeInterval start;

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet DropFilesView* dropFilesView;

@property (atomic, readwrite, strong) NSOperationQueue* transcodeQueue;
@property (atomic, readwrite, strong) NSOperationQueue* metadataQueue;

@property (atomic, readwrite, strong) NSMutableArray* analyzerPlugins;
@property (atomic, readwrite, strong) NSMutableArray* analyzerPluginsInitializedForPrefs;

// Preferences
@property (weak) IBOutlet NSWindow* prefsWindow;
@property (weak) IBOutlet PreferencesViewController* prefsViewController;
@property (weak) IBOutlet NSArrayController* prefsAnalyzerArrayController;
// Log
@property (weak) IBOutlet NSWindow* logWindow;

// Toolbar
@property (weak) IBOutlet NSToolbarItem* startPauseToolbarItem;



@end

@implementation AppDelegate


//fix our giant memory leak which happened because we are probably holding on to Operations unecessarily now and not letting them go in our TableView's array of cached objects or some shit.


- (id) init
{
    self = [super init];
    if(self)
    {
        // Serial transcode queue
        self.transcodeQueue = [[NSOperationQueue alloc] init];
        self.transcodeQueue.maxConcurrentOperationCount = [[NSProcessInfo processInfo] activeProcessorCount] / 2; //NSOperationQueueDefaultMaxConcurrentOperationCount; //1, NSOperationQueueDefaultMaxConcurrentOperationCount
        self.transcodeQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        
        // Serial metadata / passthrough writing queue
        self.metadataQueue = [[NSOperationQueue alloc] init];
        self.metadataQueue.maxConcurrentOperationCount = [[NSProcessInfo processInfo] activeProcessorCount] / 2; //NSOperationQueueDefaultMaxConcurrentOperationCount; //1, NSOperationQueueDefaultMaxConcurrentOperationCount
        self.metadataQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        
        self.analyzerPlugins = [NSMutableArray new];
        self.analyzerPluginsInitializedForPrefs = [NSMutableArray new];
    }
    return self;
}

- (void) awakeFromNib
{
    self.dropFilesView.dragDelegate = self;
    
    self.prefsAnalyzerArrayController.content = self.analyzerPluginsInitializedForPrefs;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    // REVEAL THYSELF
    [[self window] makeKeyAndOrderFront:nil];
    
    // Touch a ".synopsis" file to trick out embedded spotlight importer that there is a .synopsis file
    // We mirror OpenMeta's approach to allowing generic spotlight support via xattr's
    // But Yea
    [self initSpotlight];
    
    // force Standard Analyzer to be a plugin
    [self.analyzerPlugins addObject:NSStringFromClass([StandardAnalyzerPlugin class])];

    
    // Load our plugins
    NSString* pluginsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    
    NSError* error = nil;
    
    NSArray* possiblePlugins = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:pluginsPath error:&error];
    
    
    if(!error)
    {
        for(NSString* possiblePlugin in possiblePlugins)
        {
            NSBundle* pluginBundle = [NSBundle bundleWithPath:[pluginsPath stringByAppendingPathComponent:possiblePlugin]];
            
            if(pluginBundle)
            {
                NSError* loadError = nil;
                if([pluginBundle preflightAndReturnError:&loadError])
                {
                    if([pluginBundle loadAndReturnError:&loadError])
                    {
                        // Weve sucessfully loaded our bundle, time to cache our class name so we can initialize a plugin per operation
                        // See (AnalysisAndTranscodeOperation
                        Class pluginClass = pluginBundle.principalClass;
                        NSString* classString = NSStringFromClass(pluginClass);
                        
                        if(classString)
                        {
                            [self.analyzerPlugins addObject:classString];
                            
                            [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Loaded Plugin: %@", classString, nil]];
                            
                            [self.prefsAnalyzerArrayController addObject:[[pluginClass alloc] init]];
                        }
                    }
                    else
                    {
                        [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Error Loading Plugin : %@ : %@ %@", possiblePlugin, pluginsPath, loadError.description, nil]];
                    }
                }
                else
                {
                    [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Error Preflighting Plugin : %@ : %@ %@ %@", possiblePlugin, pluginsPath,  pluginBundle, loadError.description, nil]];
                }
            }
            else
            {
                [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Error Creating Plugin : %@ : %@ %@", possiblePlugin, pluginsPath,  pluginBundle, nil]];

            }
        }
    }
    
//    [self initPrefs];
}

- (void) applicationWillTerminate:(NSNotification *)notification
{
    // Cancel all operations and wait for completion.
    
    for (NSOperation* op in [self.transcodeQueue operations])
    {
        [op cancel];
        op.completionBlock = nil;
    }
    
    for (NSOperation* op in [self.metadataQueue operations])
    {
        [op cancel];
        op.completionBlock = nil;
    }
    
    //clean bail.

    [self.transcodeQueue waitUntilAllOperationsAreFinished];
    [self.metadataQueue waitUntilAllOperationsAreFinished];
}

#pragma mark - Prefs

- (void) initSpotlight
{
    NSURL* spotlightFileURL = nil;
    NSURL* resourceURL = [[NSBundle mainBundle] resourceURL];
    
    spotlightFileURL = [resourceURL URLByAppendingPathComponent:@"spotlight.synopsis"];
    
    if([[NSFileManager defaultManager] fileExistsAtPath:[spotlightFileURL path]])
    {
        [[NSFileManager defaultManager] removeItemAtPath:[spotlightFileURL path] error:nil];
        
//        // touch the file, just to make sure
//        NSError* error = nil;
//        if(![[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate:[NSDate date]} ofItemAtPath:[spotlightFileURL path] error:&error])
//        {
//            NSLog(@"Error Initting Spotlight : %@", error);
//        }
    }
    
    {
        // See OpenMeta for details
        // Our spotlight trickery file will contain a set of keys we use

        // info_v002_synopsis_dominant_colors = rgb
        NSDictionary* exampleValues = @{ @"info_synopsis_dominant_colors" : @[@0.0, @0.0, @0.0], // Solid Black
                                         @"info_synopsis_descriptors" : @"Black",
                                         @"info_synopsis_perceptual_hash" : @(0xf4c0527068503428),
                                         @"info_synopsis_motion_vector_values" : @[@-1.0, @0.0]
                                        };
        
        [exampleValues writeToFile:[spotlightFileURL path] atomically:YES];
    }
}

#pragma mark -

- (IBAction)openMovies:(id)sender
{
    // Open a movie or two
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    
    [openPanel setAllowsMultipleSelection:YES];
    
    // TODO
    [openPanel setAllowedFileTypes:[AVMovie movieTypes]];
    //    [openPanel setAllowedFileTypes:@[@"mov", @"mp4", @"m4v"]];
    
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
    
    // Some file's may not have an extension but rely on mime type.
    if(lastPathExtention == nil || [lastPathExtention isEqualToString:@""])
    {
        NSError* error = nil;
        NSString* type = [[NSWorkspace sharedWorkspace] typeOfFile:[fileURL path] error:&error];
        if(error == nil)
        {
            lastPathExtention = [[NSWorkspace sharedWorkspace] preferredFilenameExtensionForType:type];
        }
        else
        {
            // Take a guess?
            lastPathExtention = @"mov";
        }
    }
    
    // delete our file extension
    lastPath = [lastPath stringByDeletingPathExtension];
    
    NSString* firstPassFilePath = [lastPath stringByAppendingString:@"_temp"];
    NSString* lastPassFilePath = [lastPath stringByAppendingString:@"_analyzed"];
    
    NSURL* destinationURL = [fileURL URLByDeletingLastPathComponent];
    destinationURL = [[destinationURL URLByAppendingPathComponent:firstPassFilePath] URLByAppendingPathExtension:lastPathExtention];
    
    NSURL* destinationURL2 = [fileURL URLByDeletingLastPathComponent];
    destinationURL2 = [[destinationURL2 URLByAppendingPathComponent:lastPassFilePath] URLByAppendingPathExtension:lastPathExtention];

    // check to see if our destination URLs already exist. If so - we re-number them for now.
    
    
    // Pass 1 is our analysis pass, and our decode pass

    // todo: get the selected preset and fill in the logic here
    PresetObject* currentPreset = [self.prefsViewController defaultPreset];
    PresetVideoSettings* videoSettings = currentPreset.videoSettings;
    PresetAudioSettings* audioSettings = currentPreset.audioSettings;
    PresetAnalysisSettings* analysisSettings = currentPreset.analyzerSettings;
    
    // TODO:
    NSDictionary* placeholderAnalysisSettings = @{kSynopsisAnalysisSettingsQualityHintKey : @(SynopsisAnalysisQualityHintMedium),
                                                  kSynopsisAnalysisSettingsEnabledPluginsKey : self.analyzerPlugins,
                                                  kSynopsisAnalysisSettingsEnableConcurrencyKey : @TRUE,
                                                  };
    
    NSDictionary* transcodeOptions = @{kSynopsisTranscodeVideoSettingsKey : (videoSettings.settingsDictionary) ? videoSettings.settingsDictionary : [NSNull null],
                                       kSynopsisTranscodeAudioSettingsKey : (audioSettings.settingsDictionary) ? audioSettings.settingsDictionary : [NSNull null],
                                       kSynopsisAnalysisSettingsKey : (analysisSettings.settingsDictionary) ? analysisSettings.settingsDictionary : placeholderAnalysisSettings,
                                       };
    
    // TODO: Just pass a copy of the current Preset directly.
    AnalysisAndTranscodeOperation* analysis = [[AnalysisAndTranscodeOperation alloc] initWithSourceURL:fileURL
                                                                                        destinationURL:destinationURL
                                                                                      transcodeOptions:transcodeOptions
                                                                                    ];
    
    assert(analysis);
    
    // pass2 is depended on pass one being complete, and on pass1's analyzed metadata
    __weak AnalysisAndTranscodeOperation* weakAnalysis = analysis;
    
    analysis.completionBlock = (^(void)
                                {
                                    // Retarded weak/strong pattern so we avoid retain loopl
                                    __strong AnalysisAndTranscodeOperation* strongAnalysis = weakAnalysis;
									
									if (strongAnalysis.succeeded) {
										NSDictionary* metadataOptions = @{kSynopsisAnalyzedVideoSampleBufferMetadataKey : strongAnalysis.analyzedVideoSampleBufferMetadata,
																		  kSynopsisAnalyzedAudioSampleBufferMetadataKey : strongAnalysis.analyzedAudioSampleBufferMetadata,
																		  kSynopsisAnalyzedGlobalMetadataKey : strongAnalysis.analyzedGlobalMetadata
																		  };
										
										MetadataWriterTranscodeOperation* pass2 = [[MetadataWriterTranscodeOperation alloc] initWithSourceURL:destinationURL destinationURL:destinationURL2 metadataOptions:metadataOptions];
										
										pass2.completionBlock = (^(void)
																 {
																	 [[LogController sharedLogController] appendSuccessLog:@"Finished Analysis"];
																	 
																	 // Clean up
																	 NSError* error;
																	 if(![[NSFileManager defaultManager] removeItemAtURL:destinationURL error:&error])
																	 {
																		 [[LogController sharedLogController] appendErrorLog:[@"Error deleting temporary file: " stringByAppendingString:error.description]];
																	 }
																	 
																	 
																 });
										
										[self.metadataQueue addOperation:pass2];
									}
									
                                });
	
    [[LogController sharedLogController] appendVerboseLog:@"Begin Transcode and Analysis"];
	
    [self.transcodeQueue addOperation:analysis];
}

#pragma mark - Drop File Helper

- (void) handleDropedFiles:(NSArray *)fileURLArray
{
    if(fileURLArray)
    {
        start = [NSDate timeIntervalSinceReferenceDate];
		
        for(NSURL* url in fileURLArray)
        {
            [self enqueueFileForTranscode:url];
        }
		
        NSBlockOperation* blockOp = [NSBlockOperation blockOperationWithBlock:^{
            NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - start;
			
            [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Batch Took : %f seconds", delta]];
			
        }];
		
        [blockOp addDependency:[self.transcodeQueue.operations lastObject]];
		
        [self.transcodeQueue addOperation:blockOp];
    }
}

#pragma mark - Toolbar

static BOOL isRunning = NO;
- (IBAction) runAnalysisAndTranscode:(id)sender
{
    isRunning = !isRunning;
    
    if(isRunning)
    {
        self.startPauseToolbarItem.image = [NSImage imageNamed:@"ic_pause_circle_filled"];
    }
    else
    {
        self.startPauseToolbarItem.image = [NSImage imageNamed:@"ic_play_circle_filled"];
    }
}

- (IBAction) revealLog:(id)sender
{
    [self revealHelper:self.logWindow sender:sender];
}

- (IBAction) revealPreferences:(id)sender
{
    [self revealHelper:self.prefsWindow sender:sender];
}

#pragma mark - Helpers

- (void) revealHelper:(NSWindow*)window sender:(id)sender
{
    if([window isVisible])
    {
        [window orderOut:sender];
    }
    else
    {
        [window makeKeyAndOrderFront:sender];
    }
}

@end
