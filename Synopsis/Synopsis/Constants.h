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

// Notifications
#define kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification @"kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification"
#define kSynopsisAnalyzerConcurrentFrameAnalysisDidChangeNotification @"kSynopsisAnalyzerConcurrentFrameAnalysisD"

#endif /* Constants_h */
