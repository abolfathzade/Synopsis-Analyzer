//
//  TensorFlowAnalyzer.m
//  Synopsis
//
//  Created by vade on 12/6/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//


#include "tensorflow/cc/ops/const_op.h"
#include "tensorflow/cc/ops/image_ops.h"
#include "tensorflow/cc/ops/standard_ops.h"
#include "tensorflow/core/framework/graph.pb.h"
#include "tensorflow/core/framework/tensor.h"
#include "tensorflow/core/graph/default_device.h"
#include "tensorflow/core/graph/graph_def_builder.h"
#include "tensorflow/core/lib/core/errors.h"
#include "tensorflow/core/lib/core/stringpiece.h"
#include "tensorflow/core/lib/core/threadpool.h"
#include "tensorflow/core/lib/io/path.h"
#include "tensorflow/core/lib/strings/stringprintf.h"
#include "tensorflow/core/platform/init_main.h"
#include "tensorflow/core/platform/logging.h"
#include "tensorflow/core/platform/types.h"
#include "tensorflow/core/public/session.h"
#include "tensorflow/core/util/command_line_flags.h"

#import "TensorFlowAnalyzer.h"


@interface TensorFlowAnalyzer ()
{
    // TensorFlow
    tensorflow::Session* inceptionSession;
}
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
@property (readwrite) BOOL hasModules;

@property (atomic, readwrite, strong) NSString* inception2015GraphName;
@property (atomic, readwrite, strong) NSString* inception2015LabelName;

@end

@implementation TensorFlowAnalyzer

using namespace tensorflow;

- (id) init
{
    self = [super init];
    if(self)
    {
        self.pluginName = @"TensowFlow based Analyzer";
        self.pluginIdentifier = @"info.Synopsis.TensorFlowAnalyzer";
        self.pluginAuthors = @[@"Anton Marini"];
        self.pluginDescription = @"Analysis via Google's Tensor Flow machine learning library";
        self.pluginAPIVersionMajor = 0;
        self.pluginAPIVersionMinor = 1;
        self.pluginVersionMajor = 0;
        self.pluginVersionMinor = 1;
        self.pluginMediaType = AVMediaTypeVideo;
        self.hasModules = NO;
        
        self.inception2015GraphName = @"tensorflow_inception_graph.pb";
        self.inception2015LabelName = @"imagenet_comp_graph_label_strings.txt";
    }
    
    return self;
}

- (void) dealloc
{
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{
    NSArray* args = [[NSProcessInfo processInfo] arguments];
    
    //tensorflow::port::InitMain([args[0] cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL);

    Status status = NewSession(SessionOptions(), &inceptionSession);

    NSString* inception2015GraphPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"tensorflow_inception_graph" ofType:@"pb"];
    
    GraphDef tfInceptionGraphDef;
    Status load_graph_status = ReadBinaryProto(Env::Default(), [inception2015GraphPath cStringUsingEncoding:NSASCIIStringEncoding], &tfInceptionGraphDef);
    if (!load_graph_status.ok())
    {
        NSLog(@"Unable to load graph");
    }
    
    Status session_create_status = inceptionSession->Create(tfInceptionGraphDef);
    
    if (!session_create_status.ok()) {
        NSLog(@"Unable to create session");
    }
    
}

- (void) submitAndCacheCurrentVideoBuffer:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow
{
    
}

- (NSDictionary*) analyzeMetadataDictionaryForModuleIndex:(SynopsisModuleIndex)moduleIndex error:(NSError**)error
{
    return nil;
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    return nil;
}


@end
