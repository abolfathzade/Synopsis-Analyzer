//
//  SampleBufferAnalyzerPluginProtocol.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>

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

// Initialize any resources required by the plugin for Analysis - called
- (void) beginMetadataAnalysisSession;

// Note that the sample buffer's internal data type might differ from whats expected
- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError**)error;

// Finalize any calculations for global metadata
- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error;


@end
