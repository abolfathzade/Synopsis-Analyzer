//
//  AppDelegate.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "AppDelegate.h"

#import <Synopsis/Synopsis.h>
#import <VideoToolbox/VTProfessionalVideoWorkflow.h>
#import <MediaToolbox/MediaToolbox.h>

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
@property (atomic, readwrite, strong) NSOperationQueue* sessionComplectionQueue;

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

- (id) init
{
    self = [super init];
    if(self)
    {
        MTRegisterProfessionalVideoWorkflowFormatReaders();
        VTRegisterProfessionalVideoWorkflowVideoDecoders();
        VTRegisterProfessionalVideoWorkflowVideoEncoders();

        NSDictionary* standardDefaults = @{kSynopsisAnalyzerDefaultPresetPreferencesKey : @"DDCEA125-B93D-464B-B369-FB78A5E890B4",
                                           kSynopsisAnalyzerConcurrentJobAnalysisPreferencesKey : @(YES),
                                           kSynopsisAnalyzerConcurrentFrameAnalysisPreferencesKey : @(YES),
                                           kSynopsisAnalyzerUseOutputFolderKey : @(NO),
                                           kSynopsisAnalyzerUseWatchFolderKey : @(NO),
                                           kSynopsisAnalyzerUseTempFolderKey : @(NO),
                                           kSynopsisAnalyzerMirrorFolderStructureToOutputKey : (@NO),
                                           };
        
        [[NSUserDefaults standardUserDefaults] registerDefaults:standardDefaults];
        
        // Number of simultaneous Jobs:
        BOOL concurrentJobs = [[[NSUserDefaults standardUserDefaults] objectForKey:kSynopsisAnalyzerConcurrentJobAnalysisPreferencesKey] boolValue];
        
        // Serial transcode queue
        self.transcodeQueue = [[NSOperationQueue alloc] init];
        self.transcodeQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
        self.transcodeQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        
        // Serial metadata / passthrough writing queue
        self.metadataQueue = [[NSOperationQueue alloc] init];
        self.metadataQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
        self.metadataQueue.qualityOfService = NSQualityOfServiceUserInitiated;
       
        // Completion queue of group of encodes, be it a drag session, opening of a set folders with media, or a single encode operation
        self.sessionComplectionQueue = [[NSOperationQueue alloc] init];
        self.sessionComplectionQueue.maxConcurrentOperationCount = 1;
        self.sessionComplectionQueue.qualityOfService = NSQualityOfServiceUtility;
        
        self.analyzerPlugins = [NSMutableArray new];
        self.analyzerPluginsInitializedForPrefs = [NSMutableArray new];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(concurrentJobsDidChange:) name:kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification object:nil];
    }
    return self;
}

- (void) awakeFromNib
{
    self.dropFilesView.dragDelegate = self;
    
    self.prefsAnalyzerArrayController.content = self.analyzerPluginsInitializedForPrefs;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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
                        // See AnalysisAndTranscodeOperation
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
        NSDictionary* exampleValues = @{@"info_synopsis_version" : @(kSynopsisMetadataVersionValue),
                                         @"info_synopsis_descriptors" : @"Black",
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
    
    [openPanel setAllowedFileTypes:SynopsisSupportedFileTypes()];
    
    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result)
     {
         if (result == NSFileHandlingPanelOKButton)
         {
             [self analysisSessionForFiles:openPanel.URLs sessionCompletionBlock:^{
                 
             }];
         }
     }];
}

- (BaseTranscodeOperation*) enqueueFileForTranscode:(NSURL*)fileURL tempDirectory:(NSURL*)tempDirectory outputDirectory:(NSURL*)outputDirectory
{
    NSUUID* encodeUUID = [NSUUID UUID];
    
    NSString* sourceFileName = [fileURL lastPathComponent];
    sourceFileName = [sourceFileName stringByDeletingPathExtension];

    NSString* sourceFileExtension = [fileURL pathExtension];
    NSString* destinationFileExtension = @"mov";
    
    // Some file's may not have an extension but rely on mime type.
    if(sourceFileExtension == nil || [sourceFileExtension isEqualToString:@""])
    {
        NSError* error = nil;
        NSString* type = [[NSWorkspace sharedWorkspace] typeOfFile:[fileURL path] error:&error];
        if(error == nil)
        {
            sourceFileExtension = [[NSWorkspace sharedWorkspace] preferredFilenameExtensionForType:type];
        }
        else
        {
            sourceFileExtension = @"mov";
        }
    }
    
    NSString* analysisPassFileName = [[sourceFileName stringByAppendingString:@"_temp_"] stringByAppendingString:encodeUUID.UUIDString];
    NSString* metadataPassFileName = [sourceFileName stringByAppendingString:@"_analyzed"];

    NSURL* analysisFileURL = [tempDirectory URLByAppendingPathComponent:analysisPassFileName];
    analysisFileURL = [analysisFileURL URLByAppendingPathExtension:destinationFileExtension];

    NSURL* metadataFileURL = [outputDirectory URLByAppendingPathComponent:metadataPassFileName];
    metadataFileURL = [metadataFileURL URLByAppendingPathExtension:destinationFileExtension];

    // check to see if our final pass destination URLs already exist - if so, append our sesion UUI.
    if([[NSFileManager defaultManager] fileExistsAtPath:metadataFileURL.path])
    {
        metadataFileURL = [metadataFileURL URLByDeletingLastPathComponent];
        metadataFileURL = [[metadataFileURL URLByAppendingPathComponent:[metadataPassFileName stringByAppendingString:[@"_" stringByAppendingString:encodeUUID.UUIDString]]] URLByAppendingPathExtension:destinationFileExtension];
    }
    
    // TODO: Just pass a copy of the current Preset directly, and figure out what we need for analysis settings
    PresetObject* currentPreset = [self.prefsViewController defaultPreset];
    PresetVideoSettings* videoSettings = currentPreset.videoSettings;
    PresetAudioSettings* audioSettings = currentPreset.audioSettings;
    PresetAnalysisSettings* analysisSettings = currentPreset.analyzerSettings;

    SynopsisMetadataEncoderExportOption exportOption = currentPreset.metadataExportOption;
    
    NSDictionary* placeholderAnalysisSettings = @{kSynopsisAnalysisSettingsQualityHintKey : @(SynopsisAnalysisQualityHintMedium),
                                                  kSynopsisAnalysisSettingsEnabledPluginsKey : self.analyzerPlugins,
                                                  kSynopsisAnalysisSettingsEnableConcurrencyKey : @TRUE,
                                                  };
    
    NSDictionary* transcodeOptions = @{kSynopsisTranscodeVideoSettingsKey : (videoSettings.settingsDictionary) ? videoSettings.settingsDictionary : [NSNull null],
                                       kSynopsisTranscodeAudioSettingsKey : (audioSettings.settingsDictionary) ? audioSettings.settingsDictionary : [NSNull null],
                                       kSynopsisAnalysisSettingsKey : placeholderAnalysisSettings,
                                       };
    
    AnalysisAndTranscodeOperation* analysis = [[AnalysisAndTranscodeOperation alloc] initWithUUID:encodeUUID sourceURL:fileURL destinationURL:analysisFileURL transcodeOptions:transcodeOptions];
    MetadataWriterTranscodeOperation* metadata = [[MetadataWriterTranscodeOperation alloc] initWithUUID:encodeUUID sourceURL:analysisFileURL destinationURL:metadataFileURL];

    assert(analysis);
    assert(metadata);

    // metadata is depended on pass one being complete, and on analysies's analyzed metadata
    __weak AnalysisAndTranscodeOperation* weakAnalysis = analysis;

    analysis.completionBlock = (^(void)
                                {
                                    __strong AnalysisAndTranscodeOperation* strongAnalysis = weakAnalysis;
                                    
                                    if (strongAnalysis.succeeded)
                                    {
                                        NSDictionary* metadataOptions = @{kSynopsisAnalyzedVideoSampleBufferMetadataKey : strongAnalysis.analyzedVideoSampleBufferMetadata,
                                                                          kSynopsisAnalyzedAudioSampleBufferMetadataKey : strongAnalysis.analyzedAudioSampleBufferMetadata,
                                                                          kSynopsisAnalyzedGlobalMetadataKey : strongAnalysis.analyzedGlobalMetadata,
                                                                          kSynopsisAnalyzedMetadataExportOptionKey : @(exportOption),
                                                                          };
                                        
                                        // Set our metadata pass'es metadata options to the result of our analysis operation
                                        // The dependency structure as well as our custom NSOperation subclass should
                                        // Ensure that this completion block fires before main on our metadata operation does
                                        // Ensuring that metadata operation has the info it needs...
                                        metadata.metadataOptions = metadataOptions;
                                    }
                                });
		
    metadata.completionBlock = (^(void)
                                {
                                    [[LogController sharedLogController] appendSuccessLog:@"Finished Analysis"];
                                    
                                 
                                    
//                                    NSURL* destinationURL = nil;
                                    
                                    // If we are mirroring our folder structure, lets copy all sub-directories and ensure we output to the correct paths.
//                                    if([self.prefsViewController.preferencesFileViewController usingOutputFolder] && [self.prefsViewController.preferencesFileViewController usingMirroredFolders])
//                                    {
//
//
//                                        NSURL* outputParentFolder = [self.prefsViewController.preferencesFileViewController outputFolderURL];
//
//                                    }
//                                    else if([self.prefsViewController.preferencesFileViewController usingOutputFolder])
//                                    {
//                                        destinationURL =
//                                    }
                                    
                                    // Move the result of metadata operation to the final destination
                                    
                                    // Clean up
                                    NSError* error;
                                    if(![[NSFileManager defaultManager] removeItemAtURL:analysisFileURL error:&error])
                                    {
                                        [[LogController sharedLogController] appendErrorLog:[@"Error deleting temporary file: " stringByAppendingString:error.description]];
                                    }
                                });
    
    // Ensure we fire only once analysis completes, and its completion block is fired off
    [metadata addDependency:analysis];

    [[LogController sharedLogController] appendVerboseLog:@"Begin Transcode and Analysis"];

    [self.transcodeQueue addOperation:analysis];
    [self.metadataQueue addOperation:metadata];

    return metadata;
}

- (void) analysisSessionForFiles:(NSArray *)fileURLArray sessionCompletionBlock:(void (^)(void))completionBlock
{
    // File Handling logic:
    
    // source: file (file to be analyzed / encoded)
    // output folder: (destination for resulting files that have been analyzed and encoded)
    // temp folder: (folder where intermediate files are created)
    // watch folder: (folder where any file system changes are noticed and files are enqueued for auto-encode).
    
    // If we have an input file and no output, temp or watch folder specified.
    // (output folder = temp folder = source folder)
    // in:		/path/to/source.mov
    // pass1:	/path/to/source_UUID_temp.mov
    // pass2:	/path/to/source_analyzed.mov
    // move: (none)
    
    // If we have an input file and an output folder
    // (temp folder = output folder, output folder is manually specified)
    // in:		/path/to/source.mov
    // pass1:	/path/to/output/folder/source_UUID_temp.mov
    // pass2:	/path/to/output/folder/source_analyzed.mov
    // move: (none)
    
    // If we have an input file and an temp folder
    // (output folder = source folder, temp folder manually specified)
    // in:		/path/to/source.mov
    // pass1:	/path/to/temp/folder/source_UUID_temp.mov
    // pass2:	/path/to/temp/folder/source_analyzed.mov
    // move:	/path/to/source_analyzed.mov
    
    // If we have an input file and an temp folder and an output folder:
    // in:        /path/to/source.mov
    // pass1:    /path/to/temp/folder/source_UUID_temp.mov
    // pass2:    /path/to/temp/folder/source_analyzed.mov
    // move:    /path/to/output/folder/source_analyzed.mov

    
    NSURL* moveDirectory = nil;

    NSUUID* sessionUUID = [NSUUID UUID];
    [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Begin Session %@", sessionUUID.UUIDString]];

    if(fileURLArray && fileURLArray.count)
    {
        start = [NSDate timeIntervalSinceReferenceDate];
        
        NSURL* tempDirectory = nil;
        NSURL* outputDirectory = nil;
        NSMutableArray<NSURL*>* filesToMove = [NSMutableArray new];
        
        if([self.prefsViewController.preferencesFileViewController usingTempFolder])
        {
            tempDirectory = [self.prefsViewController.preferencesFileViewController tempFolderURL];
        }
        
        if([self.prefsViewController.preferencesFileViewController usingOutputFolder])
        {
            if(tempDirectory == nil)
            {
                outputDirectory = [self.prefsViewController.preferencesFileViewController outputFolderURL];
                tempDirectory = outputDirectory;
            }
            else
            {
                outputDirectory = tempDirectory;
                moveDirectory = [self.prefsViewController.preferencesFileViewController outputFolderURL];
            }
        }
        
        NSBlockOperation* blockOp = [NSBlockOperation blockOperationWithBlock:^{
            
            // Do our File Move logic if we need it here:
            if(filesToMove.count && moveDirectory != nil)
            {
                for(NSURL* fileToMove in filesToMove)
                {
                    NSString* itemName = [fileToMove lastPathComponent];
                    NSURL* moveDestination = [moveDirectory URLByAppendingPathComponent:itemName];

                    NSError* error = nil;
                    if(![[NSFileManager defaultManager] moveItemAtURL:fileToMove toURL:moveDestination error:&error])
                    {
                        [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Error Moving File To Output:%@", error.localizedDescription]];
                    }
                    else
                    {
                        [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Moving File To Final Destination"]];
                    }
                }
            }
            
            NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - start;
            
            [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"End Session %@, Duration: %f seconds", sessionUUID.UUIDString, delta]];
            
            if(completionBlock != NULL)
            {
                completionBlock();
            }
        }];
        
        // Any sub-directories in our folder structure and any
        for(NSURL* url in fileURLArray)
        {
            NSURL* sourceDirectory = [url URLByDeletingLastPathComponent];
            if(tempDirectory == nil)
            {
                tempDirectory = sourceDirectory;
            }
            
            if(outputDirectory == nil)
            {
                outputDirectory = sourceDirectory;
            }

            BaseTranscodeOperation* operation = [self enqueueFileForTranscode:url tempDirectory:tempDirectory outputDirectory:outputDirectory];
            
            // Accrue our potential output files to move
            [filesToMove addObject:operation.destinationURL];
            
            [blockOp addDependency:operation];
        }
				
        [self.sessionComplectionQueue addOperation:blockOp];
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

#pragma mark - Notifications

- (void) concurrentJobsDidChange:(NSNotification*)notification
{
    // Number of simultaneous Jobs:
    BOOL concurrentJobs = [[[NSUserDefaults standardUserDefaults] objectForKey:kSynopsisAnalyzerConcurrentJobAnalysisPreferencesKey] boolValue];
    
    // Serial transcode queue
    self.transcodeQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
    
    // Serial metadata / passthrough writing queue
    self.metadataQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
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
