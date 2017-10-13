//
//  Constants.h
//  Synopsis
//
//  Created by vade on 7/19/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#ifndef Constants_h
#define Constants_h

#import <CoreFoundation/CoreFoundation.h>

#pragma mark - Enums & Constants - 

// Support various types of Analysis file handling
// This might seem verbose, but its helpful for edge cases...
// TODO: Move to flags ?
typedef enum : NSUInteger {
    // Bail case
    SessionTypeUnknown = 0,
    
    // temp file and output file adjacent to input file
    SessionTypeFileInPlace,
    // temp file and output file within output folder
    SessionTypeFileToOutput,
    // temp file in temp folder, output file adjacent to input file
    SessionTypeFileToTempToInPlace,
    // temp file in temp folder, output file in output folder
    SessionTypeFileToTempToOutput,
    
    // temp file and output file adjacent to input file, in any subfolder of source URL
    SessionTypeFolderInPlace,
    // temp file flat within temp folder, output file adjacent to input file, in any subfolder of source URL
    SessionTypeFolderToTempToInPlace,
    SessionTypeFolderToTempToOutput,
    
} SessionType;

typedef enum : NSUInteger {
    SessionStateUnknown = 0,
    SessionStatePending,
    SessionStateRunning,
    SessionStateCancelled,
    SessionStateFailed,
    SessionStateSuccess,
} SessionState;

typedef enum : NSUInteger {
    OperationStateUnknown = 0,
    OperationStatePending,
    OperationStateRunning,
    OperationStateCancelled,
    OperationStateFailed,
    OperationStateSuccess,
} OperationState;

#pragma mark - Preferences -

#define kSynopsisAnalyzerDefaultPresetPreferencesKey @"DefaultPreset" // UUID string
#define kSynopsisAnalyzerConcurrentJobAnalysisPreferencesKey @"ConcurrentJobAnalysis" // BOOL
#define kSynopsisAnalyzerConcurrentFrameAnalysisPreferencesKey @"ConcurrentFrameAnalysis" // BOOL

#define kSynopsisAnalyzerUseWatchFolderKey @"UseWatchFolder" // BOOL
#define kSynopsisAnalyzerUseOutputFolderKey @"UseOutputFolder" // BOOL
#define kSynopsisAnalyzerUseTempFolderKey @"UseTempFolder" // BOOL

#define kSynopsisAnalyzerWatchFolderURLKey @"WatchFolder" // NSString
#define kSynopsisAnalyzerOutputFolderURLKey @"OutputFolder" // NSString
#define kSynopsisAnalyzerTempFolderURLKey @"TempFolder" // NSString

// TODO: Is this necessary or should this just be implicit if we have an output folder selected?
#define kSynopsisAnalyzerMirrorFolderStructureToOutputKey @"MirrorFolderStructureToOutput" // BOOL

#pragma mark - Notifications -

#define kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification @"kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification"
#define kSynopsisAnalyzerConcurrentFrameAnalysisDidChangeNotification @"kSynopsisAnalyzerConcurrentFrameAnalysisD"

#endif /* Constants_h */
