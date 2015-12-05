//
//  SampleBufferAnalyzerPluginProtocol.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>


#pragma mark - Standard Analyzer and Spotlight Keys

// These keys are used within out Spotlight plugin, and our Standard Analyzer plugin to ensure spotlight and our analyzer agree on key names.
// These particular keys allow for a spotlight UI to be created, certain keys to be visible in the ui (and others to not be)
// This lets users easily find specific information in the Finder and in the UI.

// To be clear, if a plugin writes out custom summary metadata, that metada will be included in the HFS extended attributes
// under the com.apple.metadata: key allowing programmatic spotlight searches to work (along with command line searches).
// The only limitation is that a custom UI wont be made (as the spotlight schema wont match).

// Note, these strings need to match our scheme.xml file exactly.

// A multivalue (NSArray) that holds the actual RGB (or RGBA) values (another NSArray) for a color.
// Note, this is an Array of colors. Or an Array of Arrays.
// Not exposed to the UI
extern NSString * const kStandardAnalyzerKey_DominantColorValues;
// A multivalue (NSArray) of of NSStrings for readable color names.
// values can be Black, White, Gray, Red, Green, Blue, Cyan, Magenta, Yellow, Orange, Brown
extern NSString * const kStandardAnalyzerKey_DominantColorName;

#pragma mark - Plugin Particulars

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

@protocol AnalyzerPluginProtocol <NSObject>

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
- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer transform:(CGAffineTransform)transform error:(NSError**)error;

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
