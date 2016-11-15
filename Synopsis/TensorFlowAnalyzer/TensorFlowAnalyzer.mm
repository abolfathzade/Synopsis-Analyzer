//
//  TensorFlowAnalyzer.m
//  Synopsis
//
//  Created by vade on 12/6/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//
#import "TensorFlowAnalyzer.h"

#import <fstream>
#import <vector>

#import "tensorflow/cc/ops/const_op.h"
#import "tensorflow/cc/ops/image_ops.h"
#import "tensorflow/cc/ops/standard_ops.h"
#import "tensorflow/core/framework/graph.pb.h"
#import "tensorflow/core/framework/tensor.h"
#import "tensorflow/core/graph/default_device.h"
#import "tensorflow/core/graph/graph_def_builder.h"
#import "tensorflow/core/lib/core/errors.h"
#import "tensorflow/core/lib/core/stringpiece.h"
#import "tensorflow/core/lib/core/threadpool.h"
#import "tensorflow/core/lib/io/path.h"
#import "tensorflow/core/lib/strings/stringprintf.h"
#import "tensorflow/core/platform/init_main.h"
#import "tensorflow/core/platform/logging.h"
#import "tensorflow/core/platform/types.h"
#import "tensorflow/core/public/session.h"
#import "tensorflow/core/util/command_line_flags.h"

using namespace tensorflow;

@interface TensorFlowAnalyzer ()
{
    // TensorFlow
    std::unique_ptr<tensorflow::Session> session;
    GraphDef tfInceptionGraphDef;

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
        
        self.inception2015GraphName = @"tensorflow_inception_graph";
        self.inception2015LabelName = @"imagenet_comp_graph_label_strings";
        
        tensorflow::port::InitMain(NULL, NULL, NULL);

        NSString* inception2015GraphPath = [[NSBundle bundleForClass:[self class]] pathForResource:self.inception2015GraphName ofType:@"pb"];
        
        Status load_graph_status = ReadBinaryProto(Env::Default(), [inception2015GraphPath cStringUsingEncoding:NSASCIIStringEncoding], &tfInceptionGraphDef);
       
        if (!load_graph_status.ok())
        {
            NSLog(@"Tensorflow:Unable to Load Graph");
        }
        else
        {
            NSLog(@"Tensorflow: Loaded Graph");
        }

        session = std::unique_ptr<tensorflow::Session>(tensorflow::NewSession(tensorflow::SessionOptions()));
        
        Status session_create_status = session->Create(tfInceptionGraphDef);
        
        if (!session_create_status.ok())
        {
            NSLog(@"Tensorflow: Unable to create session");
        }
        else
        {
            NSLog(@"Tensorflow: Created Session");
        }
    }
    
    return self;
}

- (void) dealloc
{
    
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{


    
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


#pragma mark - Utilities

// Resize to expected tensor size - Models expect a specific size input tensor


@end
