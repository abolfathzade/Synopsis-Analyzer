//
//  AppDelegate.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "AppDelegate.h"
#import <copyfile.h>
#import <dirent.h>

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

@interface AppDelegate () <NSFileManagerDelegate>

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

@property (readwrite, strong) NSFileManager* fileManager;


// State management for File Manager Delegate shit.
//@property (readwrite, assign) BOOL analysisDuplicatesAllFilesToOutputFolder;
//@property (readwrite, assign) BOOL analysisDuplicatesFolderStructureOnly;

@end

@implementation AppDelegate

- (id) init
{
    self = [super init];
    if(self)
    {
        self.fileManager = [[NSFileManager alloc] init];
        [self.fileManager setDelegate:self];
        
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

    // ping our view controller to load prefs UI and directory watcher etc.
    [self.prefsViewController view];
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
    
    NSArray* possiblePlugins = [self.fileManager contentsOfDirectoryAtPath:pluginsPath error:&error];
    
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
    
    if([self.fileManager fileExistsAtPath:[spotlightFileURL path]])
    {
        [self.fileManager removeItemAtPath:[spotlightFileURL path] error:nil];
        
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

#pragma mark - Analysis

// Support various types of Analysis file handling
// This might seem verbose, but its helpful for edge cases...
// TODO: Move to flags ?
typedef enum : NSUInteger {
    // Bail case
    AnalysisTypeUnknown = 0,

    // temp file and output file adjacent to input file
    AnalysisTypeFileInPlace,
    // temp file and output file within output folder
    AnalysisTypeFileToOutput,
    // temp file in temp folder, output file adjacent to input file
    AnalysisTypeFileToTempToInPlace,
    // temp file in temp folder, output file in output folder
    AnalysisTypeFileToTempToOutput,
    
    // temp file and output file adjacent to input file, in any subfolder of source URL
    AnalysisTypeFolderInPlace,
    // temp file flat within temp folder, output file adjacent to input file, in any subfolder of source URL
    AnalysisTypeFolderToTempToInPlace,
    
    AnalysisTypeFolderToTempToOutput,
    
} AnalysisType;

- (AnalysisType) analysisTypeForURL:(NSURL*)url
{
    BOOL useTmpFolder = [self.prefsViewController.preferencesFileViewController usingTempFolder];
    NSURL* tmpFolderURL = [self.prefsViewController.preferencesFileViewController tempFolderURL];

    BOOL useOutFolder = [self.prefsViewController.preferencesFileViewController usingOutputFolder];
    NSURL* outFolderURL = [self.prefsViewController.preferencesFileViewController outputFolderURL];

    useTmpFolder = (useTmpFolder && (tmpFolderURL != nil));
    useOutFolder = (useOutFolder && (outFolderURL != nil));

    AnalysisType analysisType = AnalysisTypeUnknown;
    if(!url.hasDirectoryPath)
    {
        if(useOutFolder && !useTmpFolder)
        {
            analysisType = AnalysisTypeFileToOutput;
        }
        else if(useTmpFolder && !useOutFolder)
        {
            analysisType = AnalysisTypeFileToTempToInPlace;
        }
        else if(useTmpFolder && useOutFolder)
        {
            analysisType = AnalysisTypeFileToTempToOutput;
        }
        else
        {
            analysisType = AnalysisTypeFileInPlace;
        }
    }
    else
    {
        analysisType = AnalysisTypeFolderInPlace;
//        if(useOutFolder && !useTmpFolder)
//        {
//            analysisType = AnalysisTypeFolderToOutput;
//        }
        if(useTmpFolder && !useOutFolder)
        {
            analysisType = AnalysisTypeFolderToTempToInPlace;
        }
        else if(useTmpFolder && useOutFolder)
        {
            analysisType = AnalysisTypeFolderToTempToOutput;
        }
    }
    
    return analysisType;
}

- (void) analysisSessionForFiles:(NSArray *)URLArray sessionCompletionBlock:(void (^)(void))completionBlock
{
//    NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
//
//    NSMutableArray<NSFileAccessIntent*>* fileAccessIntentArray = [NSMutableArray arrayWithCapacity:URLArray.count];
//
//    for(NSURL* url in URLArray)
//    {
//        [fileAccessIntentArray addObject:[NSFileAccessIntent readingIntentWithURL:url options:NSFileCoordinatorReadingWithoutChanges]];
//    }
//
//    [coordinator coordinateAccessWithIntents:fileAccessIntentArray
//                                       queue:self.sessionComplectionQueue
//                                  byAccessor:^(NSError * _Nullable error) {

    NSUUID* sessionUUID = [NSUUID UUID];
    
    // TODO: this isnt explicitely correct - this *should* be run when right before our first op actually runs
    [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Begin Session %@", sessionUUID.UUIDString]];
    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Got URLS: %@", [URLArray description]]];
    
    start = [NSDate timeIntervalSinceReferenceDate];
    
    // Standard Completion Handler
    NSBlockOperation* sessionCompletionOperation = [NSBlockOperation blockOperationWithBlock:^{
        
        NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - start;
        
        [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"End Session %@, Duration: %f seconds", sessionUUID.UUIDString, delta]];
        
        if(completionBlock != NULL)
        {
            completionBlock();
        }
    }];
    
    NSURL* tmpFolderURL = [self.prefsViewController.preferencesFileViewController tempFolderURL];
    NSURL* outFolderURL = [self.prefsViewController.preferencesFileViewController outputFolderURL];
    
    NSError* error = nil;
    BOOL makeTemp = NO;
    
    // TODO: Add test to check for existence of output and temp folder here - otherwise we throw a warning in the log and continue as if the option is not set?
    
    // If we have a specified temp folder, and pref is enabled, set it
    if(tmpFolderURL != nil && [self.prefsViewController.preferencesFileViewController usingTempFolder])
    {
        tmpFolderURL = [tmpFolderURL URLByAppendingPathComponent:sessionUUID.UUIDString isDirectory:YES];
        makeTemp = [self.fileManager createDirectoryAtURL:tmpFolderURL withIntermediateDirectories:YES attributes:nil error:&error];
    }
    else
    {
        // Otherwise we specify the local directory as temp, and carry on.
        makeTemp = YES;
    }
    
    if(URLArray && URLArray.count && makeTemp)
    {
        for(NSURL* url in URLArray)
        {
            // Attempts to fix #84
            [url removeAllCachedResourceValues];
            NSURL* sourceDirectory = [url URLByDeletingLastPathComponent];

//            NSLog(@"analysisSessionForFiles: %@", url);
            
            if(tmpFolderURL == nil)
            {
                tmpFolderURL = sourceDirectory;
            }

            if(outFolderURL == nil)
            {
                outFolderURL = sourceDirectory;
            }

            // Attempts to fix #84
            [tmpFolderURL removeAllCachedResourceValues];
            [outFolderURL removeAllCachedResourceValues];
            [sourceDirectory removeAllCachedResourceValues];
            
            switch ([self analysisTypeForURL:url])
            {
                case AnalysisTypeUnknown:
                    [[LogController sharedLogController] appendWarningLog:[NSString stringWithFormat:@"Could Not Deduce Analysis Type For %@", url]];
                    break;
                    
                case AnalysisTypeFileInPlace:
                {
                    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Starting AnalysisTypeFileInPlace"]];
                    [self analysisTypeFileToTempToOutput:url tempFolder:sourceDirectory outputFolder:sourceDirectory completionOperation:sessionCompletionOperation];
                }
                    break;
                    
                case AnalysisTypeFileToTempToInPlace:
                {
                    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Starting AnalysisTypeFileToTempToInPlace"]];
                    [self analysisTypeFileToTempToOutput:url tempFolder:tmpFolderURL outputFolder:sourceDirectory completionOperation:sessionCompletionOperation];
                }
                    break;
                    
                case AnalysisTypeFileToOutput:
                {
                    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Starting AnalysisTypeFileToOutput"]];
                    [self analysisTypeFileToTempToOutput:url tempFolder:sourceDirectory outputFolder:outFolderURL completionOperation:sessionCompletionOperation];
                }
                    break;
                    
                case AnalysisTypeFileToTempToOutput:
                {
                    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Starting AnalysisTypeFileToTempToOutput"]];
                    [self analysisTypeFileToTempToOutput:url tempFolder:tmpFolderURL outputFolder:outFolderURL completionOperation:sessionCompletionOperation];
                }
                    break;
                    
                    // Folders:
                case AnalysisTypeFolderInPlace:
                {
                    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Starting AnalysisTypeFolderInPlace"]];
                    [self analysisSessionTypeFolderInPlace:url completionOperation:sessionCompletionOperation];
                }
                    break;
                    
                case AnalysisTypeFolderToTempToInPlace:
                {
                    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Starting AnalysisTypeFolderToTempToInPlace"]];
                    [self analysisSessionTypeFolderToTempToPlace:url tempFolder:tmpFolderURL completionOperation:sessionCompletionOperation];
                }
                    break;
                    
                case AnalysisTypeFolderToTempToOutput:
                {
                    [[LogController sharedLogController] appendVerboseLog:[NSString stringWithFormat:@"Starting AnalysisTypeFolderToTempToOutput"]];
                    // We add a 'move' operation to every 'top level folder that we encode. We
                    // If we have folders which arrive / are updated within a from a watch folder
                    NSBlockOperation* moveOperation = [NSBlockOperation blockOperationWithBlock:^{
                        
                        // if a folder was already analyzed, and resides in the destination output folder, we should rename it
                        // TODO: Rename output folder URL with session ID
                        // TODO: DONT move if we fail!
                        NSString* folderName = [url lastPathComponent];
                        
                        NSError* error = nil;
                        if([self.fileManager moveItemAtURL:[tmpFolderURL URLByAppendingPathComponent:folderName]
                                                     toURL:[outFolderURL URLByAppendingPathComponent:folderName] error:&error])
                        {
                            [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Moved %@ to Output Directory", folderName]];
                        }
                    }];
                    
                    [self analysisTypeFolderToTempToOutput:url tempFolder:tmpFolderURL completionOperation:moveOperation];
                    
                    // completion isnt complete till our move finishes
                    [sessionCompletionOperation addDependency:moveOperation];
                    
                    [self.sessionComplectionQueue addOperation:moveOperation];
                    
                    //
                }
                    break;
            }
        }
        
        // Enqueue our session completion operation now that it has dependencies on every encode operation
        [self.sessionComplectionQueue addOperation:sessionCompletionOperation];
    }
    
//    }];
}

#pragma mark - Analysis Type Handling Files

- (void) analysisTypeFileToTempToOutput:(NSURL*)fileToTranscode tempFolder:(NSURL*)tempFolder outputFolder:(NSURL*)outputFolder completionOperation:(NSOperation*)completionOp
{
    BaseTranscodeOperation* operation = [self enqueueFileForTranscode:fileToTranscode tempDirectory:tempFolder outputDirectory:outputFolder];
    
    [completionOp addDependency:operation];
}

#pragma mark - Analysis Type Handling Folders

- (void) analysisSessionTypeFolderInPlace:(NSURL*)directoryToEncode completionOperation:(NSOperation*)completionOp
{
    // Attempts to fix #84
    [directoryToEncode removeAllCachedResourceValues];
    NSDirectoryEnumerator* directoryEnumerator = [self.fileManager enumeratorAtURL:directoryToEncode
                                                                      includingPropertiesForKeys:[NSArray array]
                                                                                         options:NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
        return YES;
    }];
    
    for(NSURL* url in directoryEnumerator)
    {
        // Attempts to fix #84
        [url removeAllCachedResourceValues];
        
        NSNumber* isDirectory;
        NSString* fileType;
        NSError* error;
        
        if(![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error])
        {
            // Cant get NSURLIsDirectoryKey seems shady, silently continue
            continue;
        }
        
        if(![url getResourceValue:&fileType forKey:NSURLTypeIdentifierKey error:&error])
        {
            // Cant get NSURLTypeIdentifierKey seems shady too, silently continue
            continue;
        }

        if([SynopsisSupportedFileTypes() containsObject:fileType] && (isDirectory.boolValue == FALSE))
        {
            NSURL* sourceDirectory = [url URLByDeletingLastPathComponent];
          
            BaseTranscodeOperation* operation = [self enqueueFileForTranscode:url tempDirectory:sourceDirectory outputDirectory:sourceDirectory];
            [completionOp addDependency:operation];
        }
    }
}

- (void) analysisSessionTypeFolderToTempToPlace:(NSURL*)directoryToEncode tempFolder:(NSURL*)tempFolder completionOperation:(NSOperation*)completionOp
{
    // Attempts to fix #84
    [directoryToEncode removeAllCachedResourceValues];
    
    NSDirectoryEnumerator* directoryEnumerator = [self.fileManager enumeratorAtURL:directoryToEncode
                                                                      includingPropertiesForKeys:[NSArray array]
                                                                                         options:NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
        return YES;
    }];
    
    for(NSURL* url in directoryEnumerator)
    {
        // Attempts to fix #84
        [url removeAllCachedResourceValues];
        NSNumber* isDirectory;
        NSString* fileType;
        NSError* error;
        
        if(![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error])
        {
            // Cant get NSURLIsDirectoryKey seems shady, silently continue
            continue;
        }
        
        if(![url getResourceValue:&fileType forKey:NSURLTypeIdentifierKey error:&error])
        {
            // Cant get NSURLTypeIdentifierKey seems shady too, silently continue
            continue;
        }
        
        if([SynopsisSupportedFileTypes() containsObject:fileType] && (isDirectory.boolValue == FALSE))
        {
            NSURL* sourceDirectory = [url URLByDeletingLastPathComponent];
            
            BaseTranscodeOperation* operation = [self enqueueFileForTranscode:url tempDirectory:tempFolder outputDirectory:sourceDirectory];
            [completionOp addDependency:operation];
        }
    }
}

- (void) analysisTypeFolderToTempToOutput:(NSURL*)directoryToEncode tempFolder:(NSURL*)tempFolder completionOperation:(NSOperation*)completionOp
{
    // Attempts to fix #84
    [directoryToEncode removeAllCachedResourceValues];

    // Mirror the contents of our directory to encode - Our NSFileManagerDelegate handles knowing what to copy or not (only folders, or non media, or media too)
    NSError* error = nil;
    NSString* directoryToEncodeName = [directoryToEncode lastPathComponent];
    
//    if([self.fileManager copyItemAtURL:directoryToEncode toURL:[tempFolder URLByAppendingPathComponent:directoryToEncodeName] error:&error])
    if([self manuallyCopyFromURLBecauseNSFileManagerIsAPieceofShit:directoryToEncode toURL:[tempFolder URLByAppendingPathComponent:directoryToEncodeName] error:&error])
    {
        NSArray<NSURL*>* directoryEnumerator = [self manuallyEnumerateDirectoryWithFuckingDarwinCodeBecauseNSFileManagerIsalsdkf:directoryToEncode];
        
//        NSLog(@"Enumerating directory: %@", directoryToEncode);
//        NSDirectoryEnumerator* directoryEnumerator = [self.fileManager enumeratorAtURL:directoryToEncode
//                                                            includingPropertiesForKeys:[NSArray array]
//                                                                               options:NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
//
//                                                                                   if(error)
//                                                                                   {
//                                                                                       [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Unable to enumerate %@,  error: %@", url , error]];
//                                                                                       return NO;
//                                                                                   }
//
//                                                                                   return YES;
//                                                                               }];

        NSLog(@"DIRECTORY ENUMERATOR: %@", directoryEnumerator);
        
        for(NSURL* url in directoryEnumerator)
        {
            // Attempts to fix #84
            [url removeAllCachedResourceValues];
//            NSLog(@"analysisTypeFolderToTempToOutput : %@", url);

            NSNumber* isDirectory;
            NSString* fileType;
            NSError* error;

            if(![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error])
            {
                // Cant get NSURLIsDirectoryKey seems shady, silently continue
                continue;
            }

            if(![url getResourceValue:&fileType forKey:NSURLTypeIdentifierKey error:&error])
            {
                // Cant get NSURLTypeIdentifierKey seems shady too, silently continue
                continue;
            }

            if([SynopsisSupportedFileTypes() containsObject:fileType] && (isDirectory.boolValue == FALSE))
            {
                // TODO: Deduce the correct sub-directory in the temp folder to place our media in, so we only do work 'in place' within the temp folder structure.

                NSURL* newTempDir = tempFolder;

                // Remove the path components
                NSArray<NSString*>* topFolderComponentsToRemove = [[directoryToEncode URLByDeletingLastPathComponent] pathComponents];
                NSMutableArray<NSString*>* analysisFileComponents = [[[url URLByDeletingLastPathComponent] pathComponents] mutableCopy];

                [analysisFileComponents removeObjectsInArray:topFolderComponentsToRemove];

                for(NSString* component in analysisFileComponents)
                {
                    newTempDir = [newTempDir URLByAppendingPathComponent:component];
                }

                BaseTranscodeOperation* operation = [self enqueueFileForTranscode:url tempDirectory:newTempDir outputDirectory:newTempDir];
                [completionOp addDependency:operation];
            }
        }
    }
    else
    {
        [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Unable to copy %@, to Output Directory,  error: %@", [directoryToEncode lastPathComponent], error]];
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
                                    [[LogController sharedLogController] appendSuccessLog:[@"Finished Analysis for " stringByAppendingString:sourceFileName]];
                                    
                                    // Clean up
                                    NSError* error;
                                    // Note - dont use our own NSFileManager instance since this is on any thread.
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

#pragma mark - NSFileManager Delegate -

- (BOOL)fileManager:(NSFileManager *)fileManager shouldCopyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
{
    BOOL duplicateAllMediaToOutputFolder = NO;
    //    BOOL duplicateFolderStructureOnlyToOutputFolder = NO;
    
    if(duplicateAllMediaToOutputFolder)
    {
        return YES;
    }
    
    //    else if(duplicateFolderStructureOnlyToOutputFolder)
    //    {
    //        if(srcURL.hasDirectoryPath)
    //        {
    //            return YES;
    //        }
    //        {
    //            return NO;
    //        }
    //    }
    else
    {
        NSString* fileType;
        NSError* error;
        
        if(![[NSURL fileURLWithPath:srcPath] getResourceValue:&fileType forKey:NSURLTypeIdentifierKey error:&error])
        {
            // Cant get NSURLTypeIdentifierKey seems shady, return NO
            return NO;
        }
        
        if([SynopsisSupportedFileTypes() containsObject:fileType])
        {
            return NO;
        }
        
        if([[srcPath lastPathComponent] hasPrefix:@"."])
        {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)fileManager:(NSFileManager *)fileManager shouldCopyItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL
{
    BOOL duplicateAllMediaToOutputFolder = NO;
//    BOOL duplicateFolderStructureOnlyToOutputFolder = NO;
    
    if(duplicateAllMediaToOutputFolder)
    {
        return YES;
    }
    
//    else if(duplicateFolderStructureOnlyToOutputFolder)
//    {
//        if(srcURL.hasDirectoryPath)
//        {
//            return YES;
//        }
//        {
//            return NO;
//        }
//    }
    else
    {
        NSString* fileType;
        NSError* error;
        
        if(![srcURL getResourceValue:&fileType forKey:NSURLTypeIdentifierKey error:&error])
        {
            // Cant get NSURLTypeIdentifierKey seems shady, return NO
            return NO;
        }
        
        if([SynopsisSupportedFileTypes() containsObject:fileType])
        {
            return NO;
        }
        
        if([[srcURL lastPathComponent] hasPrefix:@"."])
        {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)fileManager:(NSFileManager *)fileManager shouldProceedAfterError:(NSError *)error copyingItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath;
{
    NSLog(@"File Manager should proceed after Error : %@, %@, %@", error, srcPath, dstPath);
    return YES;
}
- (BOOL)fileManager:(NSFileManager *)fileManager shouldProceedAfterError:(NSError *)error copyingItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL
{
    NSLog(@"File Manager should proceed after Error : %@, %@, %@", error, srcURL, dstURL);
    return YES;
}

#pragma mark - Replacement NSFileManager Methods -

/* Why do we have this code at all you may wonder?
 
 Because NSFileManager cannot be trusted to do work on remotely mounted volumes it appears.
 
 It appears there is some sort of race condition that occurs when NSFIleManager moves a directory on a remote volume, and then immeidatrly attempts to enumerate it.
 Because NSFileManager is a "good boye" and tries to copy all file meteadata along with the data itself, copies are not 'atomic' but rather may involve multiple writes/updates
 Copy src -> dest, then update ACLs, perms, modification/create dates, info, XATTR metadata).
 
 This, plus some internal caching of state, allow us to have the fun scneario where
 
 * NSFIleManager successfully moves /Volume/Mount_on_Server/Parent_1/Child to /Volume/Mount_on_Server/Parent_2/Child
 * (say user triggered manual or watch folder action, moves files into temp..)
 * Enumeration of contents ("Child") of "Parent_2" has stale state due to unfinished updates of metadata
 * Enumeration of directory fails because NSFIleManager *reads* stale metadata or cache and thinks its in a different folder, rather than where it just put it.
 
 Attempts to fix include

 * [url removeAllCachedResourceValues];
 * Using paths rather than NSURLs to avoid run loop caching of resource value metadata
 * Making replacements for the functions we need, which are smart enough, but not so smart they trigger the same issue
 
 The latter *appears* to have worked.
 
 Things to think about
 * Resulting files from these copies *DO NOT HAVE OUR SYNOPSIS / SPOTLIGHT XATTR Data* !!!
 * * Do we figure out if XATTR is safe in our scenario and trust out code to do the right thing
 * * This issue only rears its ugly head when a URL is on a volume
 * * Do we check for this, and only use our 'remote volume' safe methods when we need to?
 * What to do about .DSStore BS?
 * Do we care about any hidden files at all?
 * Do we are about moving to nftw which apparently is the way to correctly do directory enumeration?
 
 */

int myManualCopyFileCallBackBecauseNSFileManagerIsAPieceofShit(int what, int stage, copyfile_state_t state, const char * src, const char * dst, void * ctx)
{
    @autoreleasepool
    {
        NSString* srcPath = [[NSString alloc] initWithUTF8String:src];
        NSString* dstPath = [[NSString alloc] initWithUTF8String:dst];
        
        //        NSLog(@"CopyFileCallback %@", srcPath);
        //        NSLog(@"CopyFileCallback %@", dstPath);
        
        // Dont copy invisible files
        if([srcPath hasPrefix:@"."])
        {
            return COPYFILE_SKIP;
        }
        
        if(what == COPYFILE_RECURSE_FILE)
        {
            // check if src contains a type we dont want to copy
            NSURL* srcURL = [NSURL fileURLWithPath:srcPath];
            
            NSString* fileType;
            NSError* error;
            
            if(![srcURL getResourceValue:&fileType forKey:NSURLTypeIdentifierKey error:&error])
            {
                // Bail on error?
                return COPYFILE_QUIT;
            }
            
            if([SynopsisSupportedFileTypes() containsObject:fileType])
            {
                //                NSLog(@"Skipping copying %@", srcPath);
                return COPYFILE_SKIP;
            }
        }
        
        if(what == COPYFILE_RECURSE_ERROR)
        {
            COPYFILE_QUIT;
        }
        
        return COPYFILE_CONTINUE;
    }
}

- (BOOL) manuallyCopyFromURLBecauseNSFileManagerIsAPieceofShit:(NSURL*)fromURL toURL:(NSURL*)toURL error:(NSError**)error
{
    NSString* fromString = [fromURL path];
    NSString* toString = [toURL path];
    
    // TODO: Test the shit out of these flags
    copyfile_flags_t flags = COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC  | COPYFILE_DATA | COPYFILE_XATTR ;
    
    copyfile_state_t copystate = copyfile_state_alloc();
    
    copyfile_state_set(copystate, COPYFILE_STATE_STATUS_CB | COPYFILE_STATE_SRC_FILENAME , &myManualCopyFileCallBackBecauseNSFileManagerIsAPieceofShit);
    
    OSStatus returnValue = copyfile([fromString cStringUsingEncoding:NSUTF8StringEncoding], [toString cStringUsingEncoding:NSUTF8StringEncoding], copystate, flags);
    
    copyfile_state_free(copystate);
    
    if(returnValue == noErr)
    {
        return YES;
    }
    
    if(*error != nil)
    {
        //        TODO:set error to something descriptive
    }
    
    return NO;
}

- (NSArray<NSURL*>*) manuallyEnumerateDirectoryWithFuckingDarwinCodeBecauseNSFileManagerIsalsdkf:(NSURL*) directory// completionBlock:((void) ^(void))completionBlock
{
    NSString* path = directory.path;
    DIR* dirp = opendir([path cStringUsingEncoding:NSUTF8StringEncoding]);
    
    NSMutableArray<NSURL*>* urlArray = [NSMutableArray array];
    
    if (dirp == NULL)
    {
        return nil;
    }
    
    struct dirent* dp = NULL;
    while ((dp = readdir(dirp)) != NULL)
    {
        NSString* name = [[NSString alloc] initWithUTF8String: dp->d_name];
        if (dp->d_type == DT_DIR)
        {
            if(![name isEqualToString:@".."] && ![name isEqualToString:@"."])
            {
                NSURL* subDir = [directory URLByAppendingPathComponent:name isDirectory:YES];
                
                [urlArray addObjectsFromArray: [self manuallyEnumerateDirectoryWithFuckingDarwinCodeBecauseNSFileManagerIsalsdkf:subDir] ];
            }
        }
        
        if (dp->d_type == DT_REG)
        {
            // Dont add invisible files
            if([name hasPrefix:@"."])
            {
                continue;
            }
            
            NSURL* fileURL = [directory URLByAppendingPathComponent:name isDirectory:NO];
            [urlArray addObject:fileURL];
        }
    }
    
    (void)closedir(dirp);
    
    return urlArray;
}

@end
