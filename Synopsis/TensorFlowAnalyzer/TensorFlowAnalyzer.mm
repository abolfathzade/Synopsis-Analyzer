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


@interface TensorFlowAnalyzer ()
{
    // TensorFlow
    std::unique_ptr<tensorflow::Session> session;
    tensorflow::GraphDef tfInceptionGraphDef;

    // Cached resized tensor from our input buffer (image)
    tensorflow::Tensor resized_tensor;
    
    std::string input_layer;
    std::string output_layer;
    
    // top scoring classes
    std::vector<int> top_label_indices;  // contains top n label indices for input image
    std::vector<float> top_class_probs;  // contains top n probabilities for current input image
    
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

//
@property (atomic, readwrite, strong) NSString* inception2015GraphName;
@property (atomic, readwrite, strong) NSString* inception2015LabelName;
@property (atomic, readwrite, strong) NSArray* labelsArray;

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
        
        input_layer = "Mul";
        output_layer = "softmax";

        
        tensorflow::port::InitMain(NULL, NULL, NULL);
    }
    
    return self;
}

- (void) dealloc
{
    // TODO: Cleanup Tensorflow
    session.reset();
    
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{
    // Cache labels
    NSString* inception2015LabelPath = [[NSBundle bundleForClass:[self class]] pathForResource:self.inception2015LabelName ofType:@"txt"];
    NSString* rawLabels = [NSString stringWithContentsOfFile:inception2015LabelPath usedEncoding:nil error:nil];
    self.labelsArray = [rawLabels componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    // Create Tensorflow graph and session
    NSString* inception2015GraphPath = [[NSBundle bundleForClass:[self class]] pathForResource:self.inception2015GraphName ofType:@"pb"];
    
    tensorflow::Status load_graph_status = ReadBinaryProto(tensorflow::Env::Default(), [inception2015GraphPath cStringUsingEncoding:NSASCIIStringEncoding], &tfInceptionGraphDef);
    
    if (!load_graph_status.ok())
    {
        if(self.errorLog)
            self.errorLog(@"Tensorflow:Unable to Load Graph");
    }
    else
    {
        if(self.successLog)
            self.successLog(@"Tensorflow: Loaded Graph");
    }
    
    session = std::unique_ptr<tensorflow::Session>(tensorflow::NewSession(tensorflow::SessionOptions()));
    
    tensorflow::Status session_create_status = session->Create(tfInceptionGraphDef);
    
    if (!session_create_status.ok())
    {
        if(self.errorLog)
            self.errorLog(@"Tensorflow: Unable to create session");
    }
    else
    {
        if(self.successLog)
            self.successLog(@"Tensorflow: Created Session");
    }
}

- (void) submitAndCacheCurrentVideoBuffer:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow
{
    
    // http://stackoverflow.com/questions/36044197/how-do-i-pass-an-opencv-mat-into-a-c-tensorflow-graph
    
    // So - were going to ditch the last channel
    tensorflow::Tensor input_tensor(tensorflow::DT_UINT8,
                                    tensorflow::TensorShape({1, static_cast<long long>(height), static_cast<long long>(width), 3})); // was 4
    
    auto input_tensor_mapped = input_tensor.tensor<unsigned char, 4>();

    const unsigned char* source_data = (unsigned char*)baseAddress;
    
    for (int y = 0; y < height; ++y)
    {
        const unsigned char* source_row = source_data + (y * width * 4);
        for (int x = 0; x < width; ++x)
        {
            const unsigned char* source_pixel = source_row + (x * 4);
            for (int c = 0; c < 3; ++c) // was 4
            {
                const unsigned char* source_value = source_pixel + c;
                input_tensor_mapped(0, y, x, c) = *source_value;
            }
        }
    }
    
    std::vector<tensorflow::Tensor> resized_tensors = [self resizeAndNormalizeInputTensor:input_tensor];
    
    resized_tensor = resized_tensors[0];

}

- (NSDictionary*) analyzeMetadataDictionaryForModuleIndex:(SynopsisModuleIndex)moduleIndex error:(NSError**)error
{
    // Actually run the image through the model.
    std::vector<tensorflow::Tensor> outputs;
    tensorflow::Status run_status = session->Run({ {input_layer, resized_tensor} }, {output_layer}, {}, &outputs);
    if (!run_status.ok()) {
        LOG(ERROR) << "Running model failed: " << run_status;
        return nil;
    }

    
    return [self labelsFromOutput:outputs];
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    return nil;
}


#pragma mark - Utilities

// Construct Tensor from our base address image
template<typename T> void array_to_tensor(const T *in, tensorflow::Tensor &dst, bool do_memcpy) {
    auto dst_data = dst.flat<T>().data();
    long long n = dst.NumElements();
    if(do_memcpy) memcpy(dst_data, in, n * sizeof(T));
    else for(int i=0; i<n; i++) dst_data[i] = in[i];
}


// TODO: ensure we dont copy too much data around.
// TODO: Keep out_tensors cached and re-use
// TODO: Cache resizeAndNormalizeSession to re-use.

- (std::vector<tensorflow::Tensor>) resizeAndNormalizeInputTensor:(tensorflow::Tensor)inputTensor
{
    tensorflow::Status status;
    auto root = tensorflow::Scope::NewRootScope();

    std::vector<tensorflow::Tensor> out_tensors;
    
    std::string input_name = "input"; // was file_reader
    std::string output_name = "normalized";

    const int input_height = 299;
    const int input_width = 299;
    const float input_mean = 128;
    const float input_std = 128;
    
    // Now cast the image data to float so we can do normal math on it.
    auto float_caster = tensorflow::ops::Cast(root.WithOpName("float_caster"), inputTensor, tensorflow::DT_FLOAT);
    
    // The convention for image ops in TensorFlow is that all images are expected
    // to be in batches, so that they're four-dimensional arrays with indices of
    // [batch, height, width, channel]. Because we only have a single image, we
    // have to add a batch dimension of 1 to the start with ExpandDims().
    // auto dims_expander = tensorflow::ops::ExpandDims(root, float_caster, 0);
    
    // Bilinearly resize the image to fit the required dimensions.
    auto resized = tensorflow::ops::ResizeBilinear(root, float_caster, tensorflow::ops::Const(root.WithOpName("size"), {input_height, input_width}));
    
    // Subtract the mean and divide by the scale.
    tensorflow::ops::Div(root.WithOpName(output_name), tensorflow::ops::Sub(root, resized, {input_mean}),
        {input_std});
    
    // This runs the GraphDef network definition that we've just constructed, and
    // returns the results in the output tensor.
    tensorflow::GraphDef graph;
    status = root.ToGraphDef(&graph);
    
    if( status.ok() )
    {
        std::unique_ptr<tensorflow::Session> resizeAndNormalizeSession(tensorflow::NewSession(tensorflow::SessionOptions()));
        
        status = resizeAndNormalizeSession->Create(graph);
        
        if( status.ok() )
        {
            status = resizeAndNormalizeSession->Run({}, {output_name}, {}, &out_tensors);
            if( status.ok() )
                return out_tensors;
        }
    }
    
    if(self.errorLog)
        self.errorLog(@"Error resizing and normalizing Tensor");
    
    out_tensors.clear();
    return out_tensors;
}

- (NSDictionary*) labelsFromOutput:(const std::vector<tensorflow::Tensor>&)outputs
{
    const int numLabels = std::min(5, static_cast<int>(self.labelsArray.count));

    tensorflow::Tensor indices;
    tensorflow::Tensor scores;

    auto root = tensorflow::Scope::NewRootScope();
    using namespace ::tensorflow::ops;  // NOLINT(build/namespaces)
    
    std::string output_name = "top_k";
    
    tensorflow::ops::TopKV2(root.WithOpName(output_name), outputs[0], numLabels);

    // This runs the GraphDef network definition that we've just constructed, and
    // returns the results in the output tensors.
    tensorflow::GraphDef graph;
    root.ToGraphDef(&graph);
    
    std::unique_ptr<tensorflow::Session> topLabelsSession(tensorflow::NewSession(tensorflow::SessionOptions()));
    topLabelsSession->Create(graph);
    
    // The TopK node returns two outputs, the scores and their original indices,
    // so we have to append :0 and :1 to specify them both.
    std::vector<tensorflow::Tensor> out_tensors;
    (topLabelsSession->Run({}, {output_name + ":0", output_name + ":1"},
                                    {}, &out_tensors));
    scores = out_tensors[0];
    indices = out_tensors[1];

    
    NSMutableArray* outputLabels = [NSMutableArray arrayWithCapacity:numLabels];
    NSMutableArray* outputScores = [NSMutableArray arrayWithCapacity:numLabels];
    
    tensorflow::TTypes<float>::Flat scores_flat = scores.flat<float>();
    tensorflow::TTypes<int32_t>::Flat indices_flat = indices.flat<int32_t>();
    for (int pos = 0; pos < numLabels; ++pos) {
        const int label_index = indices_flat(pos);
        const float score = scores_flat(pos);

        [outputLabels addObject:[self.labelsArray objectAtIndex:label_index]];
        [outputScores addObject:@(score)];
        
    }
    return @{ @"Labels" : outputLabels,
              @"Scores" : outputScores};
}

@end
