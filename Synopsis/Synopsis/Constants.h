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

#define kSynopsisAnalyzerDefaultPresetPreferencesKey @"DefaultPreset"
#define kSynopsisAnalyzerConcurrentJobAnalysisPreferencesKey @"ConcurrentJobAnalysis"
#define kSynopsisAnalyzerConcurrentFrameAnalysisPreferencesKey @"ConcurrentFrameAnalysis"

#define kSynopsisAnalyzerUseWatchFolderKey @"UseWatchFolder" // BOOL
#define kSynopsisAnalyzerUseOutputFolderKey @"UseOutputFolder" // BOOL

#define kSynopsisAnalyzerWatchFolderURLKey @"WatchFolder" //
#define kSynopsisAnalyzerOutputFolderURLKey @"OutputFolder" //

// Notifications
#define kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification @"kSynopsisAnalyzerConcurrentJobAnalysisDidChangeNotification"
#define kSynopsisAnalyzerConcurrentFrameAnalysisDidChangeNotification @"kSynopsisAnalyzerConcurrentFrameAnalysisD"

#endif /* Constants_h */
