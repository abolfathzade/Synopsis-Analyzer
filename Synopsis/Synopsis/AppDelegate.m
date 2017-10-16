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

#import "SessionController.h"
#import "PreferencesViewController.h"
#import "PresetObject.h"

@interface AppDelegate () <NSFileManagerDelegate>

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet DropFilesView* dropFilesView;

@property (readwrite,strong) IBOutlet SessionController* sessionController;
@property (atomic, readwrite, strong) NSOperationQueue* synopsisAsyncQueue;

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
@property (readwrite, strong) SynopsisRemoteFileHelper* remoteFileHelper;


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
        
        self.remoteFileHelper = [[SynopsisRemoteFileHelper alloc] init];
        
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
        self.synopsisAsyncQueue = [[NSOperationQueue alloc] init];
        self.synopsisAsyncQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
        self.synopsisAsyncQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        
//        // Serial metadata / passthrough writing queue
//        self.metadataQueue = [[NSOperationQueue alloc] init];
//        self.metadataQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
//        self.metadataQueue.qualityOfService = NSQualityOfServiceUserInitiated;
//
//        // Completion queue of group of encodes, be it a drag session, opening of a set folders with media, or a single encode operation
//        self.sessionComplectionQueue = [[NSOperationQueue alloc] init];
//        self.sessionComplectionQueue.maxConcurrentOperationCount = 1;
//        self.sessionComplectionQueue.qualityOfService = NSQualityOfServiceUtility;
        
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
    for (NSOperation* op in [self.synopsisAsyncQueue operations])
    {
        [op cancel];
        op.completionBlock = nil;
    }
    
//    for (NSOperation* op in [self.metadataQueue operations])
//    {
//        [op cancel];
//        op.completionBlock = nil;
//    }
    
    //clean bail.
    [self.synopsisAsyncQueue waitUntilAllOperationsAreFinished];
//    [self.metadataQueue waitUntilAllOperationsAreFinished];
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

#pragma mark - Operation State Setup

- (NSString*) stringForOperationType:(OperationType)type
{
    switch (type)
    {
        case OperationTypeUnknown: return @"OperationTypeUnknown";
        case OperationTypeFileInPlace: return @"OperationTypeFileInPlace";
        case OperationTypeFileToTempToInPlace: return @"OperationTypeFileToTempToInPlace";
        case OperationTypeFileToOutput: return @"OperationTypeFileToOutput";
        case OperationTypeFileToTempToOutput: return @"OperationTypeFileToTempToOutput";
        case OperationTypeFolderInPlace: return @"OperationTypeFolderInPlace";
        case OperationTypeFolderToTempToInPlace: return @"OperationTypeFolderToTempToInPlace";
        case OperationTypeFolderToTempToOutput: return @"OperationTypeFolderToTempToOutput";
    }
}
- (OperationType) operationTypeForURL:(NSURL*)url
{
    BOOL useTmpFolder = [self.prefsViewController.preferencesFileViewController usingTempFolder];
    NSURL* tmpFolderURL = [self.prefsViewController.preferencesFileViewController tempFolderURL];

    BOOL useOutFolder = [self.prefsViewController.preferencesFileViewController usingOutputFolder];
    NSURL* outFolderURL = [self.prefsViewController.preferencesFileViewController outputFolderURL];

    useTmpFolder = (useTmpFolder && (tmpFolderURL != nil));
    useOutFolder = (useOutFolder && (outFolderURL != nil));

    OperationType operationType = OperationTypeUnknown;
    if(!url.hasDirectoryPath)
    {
        if(useOutFolder && !useTmpFolder)
        {
            operationType = OperationTypeFileToOutput;
        }
        else if(useTmpFolder && !useOutFolder)
        {
            operationType = OperationTypeFileToTempToInPlace;
        }
        else if(useTmpFolder && useOutFolder)
        {
            operationType = OperationTypeFileToTempToOutput;
        }
        else
        {
            operationType = OperationTypeFileInPlace;
        }
    }
    else
    {
        operationType = OperationTypeFolderInPlace;
//        if(useOutFolder && !useTmpFolder)
//        {
//            SessionType = SessionTypeFolderToOutput;
//        }
        if(useTmpFolder && !useOutFolder)
        {
            operationType = OperationTypeFolderToTempToInPlace;
        }
        else if(useTmpFolder && useOutFolder)
        {
            operationType = OperationTypeFolderToTempToOutput;
        }
    }
    
    return operationType;
}

#pragma mark - Create Session State Wrapper

- (void) analysisSessionForFiles:(NSArray *)URLArray sessionCompletionBlock:(void (^)(void))completionBlock
{
    SessionStateWrapper* session = [[SessionStateWrapper alloc] init];
    session.sessionCompletionBlock = completionBlock;
    
    NSMutableArray<OperationStateWrapper*>* operationStates = [NSMutableArray new];
    NSMutableArray<CopyOperationStateWrapper*>* copyStates = [NSMutableArray new];
    NSMutableArray<MoveOperationStateWrapper*>* moveStates = [NSMutableArray new];

    NSURL* tmpFolderURL = [self.prefsViewController.preferencesFileViewController tempFolderURL];
    NSURL* outFolderURL = [self.prefsViewController.preferencesFileViewController outputFolderURL];
    
    NSError* error = nil;
    BOOL makeTemp = NO;
    
    // TODO: Add test to check for existence of output and temp folder here - otherwise we throw a warning in the log and continue as if the option is not set?
    
    // If we have a specified temp folder, and pref is enabled, set it
    if(tmpFolderURL != nil && [self.prefsViewController.preferencesFileViewController usingTempFolder])
    {
        tmpFolderURL = [tmpFolderURL URLByAppendingPathComponent:session.sessionID.UUIDString isDirectory:YES];
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
            
            OperationType operationType = [self operationTypeForURL:url];
            
            [[LogController sharedLogController] appendVerboseLog:[@"Starting" stringByAppendingString:[self stringForOperationType:operationType] ] ];

            switch (operationType)
            {
                case OperationTypeUnknown:
                    [[LogController sharedLogController] appendWarningLog:[NSString stringWithFormat:@"Could Not Deduce Analysis Type For %@", url]];
                    break;
                    
                case OperationTypeFileInPlace:
                case OperationTypeFileToTempToInPlace:
                case OperationTypeFileToOutput:
                case OperationTypeFileToTempToOutput:
                {
                    OperationStateWrapper* operationState = [[OperationStateWrapper alloc] initWithSourceFileURL:url
                                                                                                   operationType:operationType
                                                                                                          preset:[self.prefsViewController defaultPreset]
                                                                                                   tempDirectory:tmpFolderURL
                                                                                            destinationDirectory:outFolderURL];
                    [operationStates addObject:operationState];
                    break;
                }
                case OperationTypeFolderInPlace:
                {
                    [operationStates addObjectsFromArray:[self operationStatesFolderInPlace:url]];
                    break;
                }
                case OperationTypeFolderToTempToInPlace:
                {
                    [operationStates addObjectsFromArray:[self operationStatesFolderToTempToPlace:url tempFolder:tmpFolderURL]];
                    break;
                }
                case OperationTypeFolderToTempToOutput:
                {
                    NSString* folderName = [url lastPathComponent];

                    CopyOperationStateWrapper* copyState = [[CopyOperationStateWrapper alloc] init];
                    copyState.srcURL = url;
                    copyState.dstURL = [tmpFolderURL URLByAppendingPathComponent:folderName];
                    [copyStates addObject:copyState];
                    
                    [operationStates addObjectsFromArray:[self operationStatesFolderToTempToOutput:url tempFolder:tmpFolderURL]];

                    MoveOperationStateWrapper* moveState = [[MoveOperationStateWrapper alloc] init];
                    moveState.srcURL = [tmpFolderURL URLByAppendingPathComponent:folderName];
                    moveState.dstURL = [outFolderURL URLByAppendingPathComponent:folderName];
                    [moveStates addObject:moveState];
                    
                    break;
                }
            }
        }
    }
    
    session.sessionOperationStates = operationStates;
    session.fileCopyOperationStates = copyStates;
    session.fileMoveOperationStates = moveStates;
    [self.sessionController addNewSession:session];
    
    // Temporary - runs analysis immediately
    [self submitSessionOperations:session];
}

#pragma mark - Submit Session State Wrapper

-(void) submitSessionOperations:(SessionStateWrapper*)session
{
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];

    // Create Begin Operation
    NSBlockOperation* beginOperation = [NSBlockOperation blockOperationWithBlock:^{
        [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Begin Session %@", session.sessionID]];
    }];
    
    [self.synopsisAsyncQueue addOperation:beginOperation];

    // Create Completion Operation
    NSBlockOperation* completionOperation = [NSBlockOperation blockOperationWithBlock:^{
        
        NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - start;
        
        [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"End Session %@, Duration: %f seconds", session.sessionID, delta]];
        
        if(session.sessionCompletionBlock != NULL)
        {
            session.sessionCompletionBlock();
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserNotification* sessionComplete = [[NSUserNotification alloc] init];
            sessionComplete.title = @"Finished Batch";
            sessionComplete.subtitle = @"Synopsis Analyzer finished batch";
            sessionComplete.hasActionButton = NO;
            sessionComplete.identifier = session.sessionID.UUIDString;
            
            [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:sessionComplete];
        });
    }];

    NSMutableArray<BaseTranscodeOperation*>* mediaOperations = [NSMutableArray new];
    NSMutableArray<NSBlockOperation*>* copyOperations = [NSMutableArray new];
    NSMutableArray<NSBlockOperation*>* moveOperations = [NSMutableArray new];

    for(CopyOperationStateWrapper* copyState in session.fileCopyOperationStates)
    {
        NSURL* source = copyState.srcURL;
        NSURL* dest = copyState.dstURL;
        
        NSBlockOperation* copyOperation = [NSBlockOperation blockOperationWithBlock:^{
            
            // Attempts to fix #84
            [source removeAllCachedResourceValues];
            
            // TODO: Thread Safe NSFileManager / remoteFileHelper invocation?
            
            BOOL useRemotePath = [self.remoteFileHelper fileURLIsRemote:source];
            BOOL copySuccessful = NO;
            NSError* error = nil;
            
            if(useRemotePath)
            {
                [[LogController sharedLogController] appendVerboseLog:[@"Using Remote File Helper for " stringByAppendingString:source.path]];
                copySuccessful = [self.remoteFileHelper safelyCopyFileURLOnRemoteFileSystem:source toURL:dest error:&error];
            }
            else
            {
                copySuccessful = [self.fileManager copyItemAtURL:source toURL:dest error:&error];
            }
            
            if(copySuccessful)
            {
                [[LogController sharedLogController] appendSuccessLog:[@"Copied file" stringByAppendingString:source.path]];
            }
            else
            {
                [[LogController sharedLogController] appendErrorLog:[@"Unable to copy file" stringByAppendingString:error.localizedDescription]];
            }
        }];
        
        [copyOperations addObject:copyOperation];
    }
    
    for(MoveOperationStateWrapper* moveState in session.fileMoveOperationStates)
    {
        NSURL* source = moveState.srcURL;
        NSURL* dest = moveState.dstURL;

        NSBlockOperation* moveOperation = [NSBlockOperation blockOperationWithBlock:^{
            
            // TODO: Thread Safe NSFileManager / remoteFileHelper invocation?
            NSError* error = nil;
            if([self.fileManager moveItemAtURL:source
                                         toURL:dest error:&error])
            {
                [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Moved %@ to Output Directory", source]];
            }
            else
            {
                [[LogController sharedLogController] appendWarningLog:[NSString stringWithFormat:@"Unable to move %@ to Output Directory: %@", source, error]];
            }
        }];
        
        [moveOperations addObject:moveOperation];
    }
    
    // Assign Dependencies
    for(OperationStateWrapper* operationState in session.sessionOperationStates)
    {
        NSArray<BaseTranscodeOperation*>* operations = [self createOperationsFromOperationState:operationState];
        for(BaseTranscodeOperation* operation in operations)
        {
            // Every copy operation must happen first
            // Completion dependecies on copy
            for(NSBlockOperation* copyOp in copyOperations)
            {
                [operation addDependency:copyOp];
                [completionOperation addDependency:copyOp];
            }
            
            // Every move Operation must happen after our final pass
            // Completion requires move to finish
            for(NSBlockOperation* moveOp in moveOperations)
            {
                [moveOp addDependency:operation];
                [completionOperation addDependency:moveOp];
            }
            
            // Completion has dependecies our op too, of course
            // This is important if we dont have moves or copies
            [completionOperation addDependency:operation];
        }
        
        [mediaOperations addObjectsFromArray:operations];
    }

    // Enqueue Operations
    for(NSBlockOperation* copyOp in copyOperations)
    {
        [self.synopsisAsyncQueue addOperation:copyOp];
    }

    for(BaseTranscodeOperation* operation in mediaOperations)
    {
        [self.synopsisAsyncQueue addOperation:operation];
    }
    
    for(NSBlockOperation* moveOp in moveOperations)
    {
        [self.synopsisAsyncQueue addOperation:moveOp];
    }
    
    [self.synopsisAsyncQueue addOperation:completionOperation];
}

- (NSArray<BaseTranscodeOperation*>*) createOperationsFromOperationState:(OperationStateWrapper*)state
{
    return [self enqueueFileForTranscode:state.sourceFileURL
                                  preset:state.preset
                           tempDirectory:state.tempDirectory
                         outputDirectory:state.destinationDirectory];
}

#pragma mark - Create Operation State Wrappers

- (NSArray<OperationStateWrapper*>*) operationStatesFolderInPlace:(NSURL*)directoryToEncode
{
    NSMutableArray<OperationStateWrapper*>* operationStates = [NSMutableArray new];

    // Attempts to fix #84
    [directoryToEncode removeAllCachedResourceValues];
    id<NSFastEnumeration> directoryEnumerator = [self safeDirectoryEnumeratorForURL:directoryToEncode];

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
          
            OperationStateWrapper* operationState = [[OperationStateWrapper alloc] initWithSourceFileURL:url
                                                                                           operationType:OperationTypeFolderInPlace
                                                                                                  preset:[self.prefsViewController defaultPreset]
                                                                                           tempDirectory:sourceDirectory
                                                                                    destinationDirectory:sourceDirectory];
            [operationStates addObject:operationState];
        }
    }
    
    return operationStates;
}

- (NSArray<OperationStateWrapper*>*) operationStatesFolderToTempToPlace:(NSURL*)directoryToEncode tempFolder:(NSURL*)tempFolder
{
    NSMutableArray<OperationStateWrapper*>* operationStates = [NSMutableArray new];

    // Attempts to fix #84
    [directoryToEncode removeAllCachedResourceValues];
    
    id<NSFastEnumeration> directoryEnumerator = [self safeDirectoryEnumeratorForURL:directoryToEncode];
    
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
            OperationStateWrapper* operationState = [[OperationStateWrapper alloc] initWithSourceFileURL:url
                                                                                           operationType:OperationTypeFolderToTempToInPlace
                                                                                                  preset:[self.prefsViewController defaultPreset]
                                                                                           tempDirectory:tempFolder
                                                                                    destinationDirectory:sourceDirectory];
            [operationStates addObject:operationState];
        }
    }
    
    return operationStates;

}

- (NSArray<OperationStateWrapper*>*) operationStatesFolderToTempToOutput:(NSURL*)directoryToEncode tempFolder:(NSURL*)tempFolder
{
    NSMutableArray<OperationStateWrapper*>* operationStates = [NSMutableArray new];

    id<NSFastEnumeration> directoryEnumerator = [self safeDirectoryEnumeratorForURL:directoryToEncode];
    
    for(NSURL* url in directoryEnumerator)
    {
        // Attempts to fix #84
        [url removeAllCachedResourceValues];
        //            NSLog(@"SessionTypeFolderToTempToOutput : %@", url);
        
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
            
            OperationStateWrapper* operationState = [[OperationStateWrapper alloc] initWithSourceFileURL:url
                                                                                           operationType:OperationTypeFolderToTempToOutput
                                                                                                  preset:[self.prefsViewController defaultPreset]
                                                                                           tempDirectory:newTempDir
                                                                                    destinationDirectory:newTempDir];
            [operationStates addObject:operationState];
        }
    }
    
    return operationStates;
}

#pragma mark - Create NSOperations

- (NSArray<BaseTranscodeOperation*>*) enqueueFileForTranscode:(NSURL*)fileURL preset:(PresetObject*)currentPreset tempDirectory:(NSURL*)tempDirectory outputDirectory:(NSURL*)outputDirectory
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
		
    __weak MetadataWriterTranscodeOperation* weakMetadata = metadata;

    metadata.completionBlock = (^(void)
                                {
                                    __strong MetadataWriterTranscodeOperation* strongMetadata = weakMetadata;

                                    if (strongMetadata.succeeded)
                                    {
                                        [[LogController sharedLogController] appendSuccessLog:[@"Finished Analysis for " stringByAppendingString:sourceFileName]];
                                        
                                        // Clean up
                                        NSError* error;
                                        // Note - dont use our own NSFileManager instance since this is on any thread.
                                        if(![[NSFileManager defaultManager] removeItemAtURL:analysisFileURL error:&error])
                                        {
                                            [[LogController sharedLogController] appendErrorLog:[@"Error deleting temporary file: " stringByAppendingString:error.description]];
                                        }
                                    }
                                    else
                                    {
                                        [[LogController sharedLogController] appendErrorLog:[@"Unsucessful Analysis for: " stringByAppendingString:sourceFileName]];
                                    }
                                });
    
    // Ensure we fire only once analysis completes, and its completion block is fired off
    [metadata addDependency:analysis];

    [[LogController sharedLogController] appendVerboseLog:@"Begin Transcode and Analysis"];

    return @[analysis, metadata];
}


#pragma mark - Toolbar

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

static BOOL isRunning = NO;
- (IBAction) runAnalysisAndTranscode:(id)sender
{
    isRunning = !isRunning;
    
    if(isRunning)
    {
        self.startPauseToolbarItem.image = [NSImage imageNamed:@"ic_pause_circle_filled"];
        self.synopsisAsyncQueue.suspended = YES;
    }
    else
    {
        self.startPauseToolbarItem.image = [NSImage imageNamed:@"ic_play_circle_filled"];
        self.synopsisAsyncQueue.suspended = NO;
    }
    
    for(SessionStateWrapper* session in [self.sessionController sessions])
    {
        if(session.sessionState == SessionStatePending)
        {
            [self submitSessionOperations:session];
        }
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
    self.synopsisAsyncQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
    
    // Serial metadata / passthrough writing queue
//    self.metadataQueue.maxConcurrentOperationCount = (concurrentJobs) ? [[NSProcessInfo processInfo] activeProcessorCount] / 2 : 1;
}

#pragma mark - Helpers

- (id<NSFastEnumeration>) safeDirectoryEnumeratorForURL:(NSURL*)urlToEnumerate
{
    BOOL useRemotePath = [self.remoteFileHelper fileURLIsRemote:urlToEnumerate];
    id<NSFastEnumeration> directoryEnumerator = nil;
    
    if(useRemotePath)
        directoryEnumerator = [self.remoteFileHelper safelyEnumerateDirectoryOnRemoteVolume:urlToEnumerate];
    else
    {
        directoryEnumerator = [self.fileManager enumeratorAtURL:urlToEnumerate
                                     includingPropertiesForKeys:[NSArray array]
                                                        options:NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles
                                                   errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
                                                       
                                                       if(error)
                                                       {
                                                           [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Unable to enumerate %@,  error: %@", url , error]];
                                                           return NO;
                                                       }
                                                       
                                                       return YES;
                                                   }];
    }
    
    return directoryEnumerator;
}

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
- (BOOL)fileManager:(NSFileManager *)fileManager shouldProceedAfterError:(NSError *)error copyingItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL
{
    NSLog(@"File Manager should proceed after Error : %@, %@, %@", error, srcURL, dstURL);
    return YES;
}


@end
