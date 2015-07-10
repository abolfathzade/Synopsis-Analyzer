//
//  SampleBufferAnalyzerPluginProtocol.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>

// Rough amount of overhead a particular plugin or module has
// For example very very taxing
typedef enum : NSUInteger {
    SynopsisAnalysisOverheadNone = 0,
    SynopsisAnalysisOverheadLow,
    SynopsisAnalysisOverheadMedium,
    SynopsisAnalysisOverheadHigh,
} SynopsisAnalysisOverhead;

// Should a plugin have configurable quality settings
// Hint the plugin to use a specific quality hint
typedef enum : NSUInteger {
    SynopsisAnalysisQualityHintLow,
    SynopsisAnalysisQualityHintMedium,
    SynopsisAnalysisQualityHintHigh,
} SynopsisAnalysisQualityHint;

@protocol SampleBufferAnalyzerPluginProtocol <NSObject>

@required

// Human Readable Plugin Named Also used in UI
@property (readonly) NSString* pluginName;

// Metadata Tag identifying the analyzers metadata section in the aggegated metatada track
// This should be something like org.metavisial.plugin -
// all metadata either global or per frame is within a dictionary under this key
@property (readonly) NSString* pluginIdentifier;

// Authors for Credit - array of NSStrings
@property (readonly) NSArray* pluginAuthors;

// Human Readable Description
@property (readonly) NSString* pluginDescription;

// Expected host API Version
@property (readonly) NSUInteger pluginAPIVersionMajor;
@property (readonly) NSUInteger pluginAPIVersionMinor;

// Plugin Version (for tuning / changes to capabilities, etc)
@property (readonly) NSUInteger pluginVersionMajor;
@property (readonly) NSUInteger pluginVersionMinor;

// The type of media the plugin analyzes. For now, plugins only work with Video or Audio, we dont pass in two buffers at once.
// Supported values are currently only AVMediaTypeVideo, or AVMediaTypeAudio. Perhaps Muxed comes in the future.
@property (readonly) NSString* pluginMediaType;

// Initialize any resources required by the plugin for Analysis
// enabledModuleKeys may be nil if no modules are optionally defined
- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint andEnabledModules:(NSDictionary*)enabledModuleKeys;

// Note that the sample buffer's internal data type might differ from whats expected
- (
) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError**)error;

// Finalize any calculations required to return global metadata
// Global Metadata is metadata that describes the entire file, not the individual frames or samples
// Things like most prominent colors over all, agreggate amounts of motion, etc
- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error;

@optional

// An array of keys used to enable or disable modules within the plugin.
// A plugin may support multiple types modes of analysis - called modules
// Each module may have overhead associated with it (processing time, etc), and end users may which to enable or disable modules

@property (readonly) NSArray* pluginModuleNames;

// Human Readable Description for the module in question
-(NSString*) descriptionForModule:(NSString*)moduleNameKey;

// Approximate computational overhead for a module - to hint user interface of computation 'expense' / duration etc.
-(SynopsisAnalysisOverhead) overheadForModule:(NSString*)moduleNameKey;

@end
