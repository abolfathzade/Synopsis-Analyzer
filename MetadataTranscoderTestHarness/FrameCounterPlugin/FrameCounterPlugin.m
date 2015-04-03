//
//  FrameCounterPlugin.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "FrameCounterPlugin.h"
#import "SampleBufferAnalyzerPluginProtocol.h"

@interface FrameCounterPlugin ()

// Plugin API requirements
@property (atomic, readwrite, strong) NSString* pluginName;
@property (atomic, readwrite, strong) NSString* pluginIdentifier;
@property (atomic, readwrite, strong) NSArray* pluginAuthors;
@property (atomic, readwrite, strong) NSString* pluginDescription;
@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMinor;
@property (atomic, readwrite, assign) NSUInteger pluginVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginVersionMinor;
@property (atomic, readwrite, strong) NSString* pluginMediaType;

// Some 'metadata' we track
@property (atomic, readwrite, assign) NSUInteger sampleCount;

@end

@implementation FrameCounterPlugin

- (id) init
{
    self = [super init];
    if(self)
    {
        self.pluginName = @"Frame Counter";
        self.pluginIdentifier = @"org.metavisual.framecounter";
        self.pluginAuthors = @[@"Anton Marini"];
        self.pluginDescription = @"Simple Frame Counter and Plugin API Demonstrator";
        self.pluginAPIVersionMajor = 0;
        self.pluginAPIVersionMinor = 1;
        self.pluginVersionMajor = 0;
        self.pluginVersionMinor = 1;
        self.pluginMediaType = AVMediaTypeVideo;
        
        self.sampleCount = 0;
    }
    
    return self;
}

- (void) beginMetadataAnalysisSession
{
    // Reset
    self.sampleCount = 0;
}

- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError**) error
{
    NSDictionary* metadata =  @{@"Sample Count" : @(self.sampleCount)};
    
    self.sampleCount++;
    
    return metadata;
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    return @{ @"Total Sample Count" : @(self.sampleCount)};
}


@end
