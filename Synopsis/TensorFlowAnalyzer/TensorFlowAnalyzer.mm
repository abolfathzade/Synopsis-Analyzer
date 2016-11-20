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
    std::unique_ptr<tensorflow::Session> inceptionSession;
    tensorflow::GraphDef inceptionGraphDef;

    std::unique_ptr<tensorflow::Session> resizeSession;

    std::unique_ptr<tensorflow::Session> topLabelsSession;

    
    // Cached resized tensor from our input buffer (image)
    tensorflow::Tensor resized_tensor;
    
    // input image tensor
    std::string input_layer;
    
    // Label / Score tensor
    std::string final_layer;
    
    // Feature vector tensor
    std::string feature_layer;
    
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
@property (atomic, readwrite, strong) NSMutableArray* averageFeatureVec;

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
        
        inceptionSession = NULL;
        resizeSession = NULL;
        topLabelsSession = NULL;

        input_layer = "Mul";
        final_layer = "softmax";
        feature_layer = "pool_3";
        
        self.averageFeatureVec = nil;
    }
    
    return self;
}

- (void) dealloc
{
    // TODO: Cleanup Tensorflow
    inceptionSession.reset();
    resizeSession.reset();
    topLabelsSession.reset();
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{
    // we need to ensure the GPU has memory for the max num of batches we can run
    // if we try to run more than 1 analysis session at a time then TF's CUDNN wont have memory and bail
    // However, if we dont get enough memory, we wont be performant.
    // Fuck.
    
    tensorflow::port::InitMain(NULL, NULL, NULL);

    // Cache labels
    NSString* inception2015LabelPath = [[NSBundle bundleForClass:[self class]] pathForResource:self.inception2015LabelName ofType:@"txt"];
    NSString* rawLabels = [NSString stringWithContentsOfFile:inception2015LabelPath usedEncoding:nil error:nil];
    self.labelsArray = [rawLabels componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    // Create Tensorflow graph and session
    NSString* inception2015GraphPath = [[NSBundle bundleForClass:[self class]] pathForResource:self.inception2015GraphName ofType:@"pb"];
    
    tensorflow::Status load_graph_status = ReadBinaryProto(tensorflow::Env::Default(), [inception2015GraphPath cStringUsingEncoding:NSUTF8StringEncoding], &inceptionGraphDef);
    
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
    
    inceptionSession = std::unique_ptr<tensorflow::Session>(tensorflow::NewSession(tensorflow::SessionOptions()));
    
    tensorflow::Status session_create_status = inceptionSession->Create(inceptionGraphDef);
    
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
    
    // TODO: check that I am dropping the alpha channel correctly :X
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
    tensorflow::Status run_status = inceptionSession->Run({ {input_layer, resized_tensor} }, {final_layer, feature_layer}, {}, &outputs);
    if (!run_status.ok()) {
        LOG(ERROR) << "Running model failed: " << run_status;
        return nil;
    }

    NSDictionary* labelsAndScores = [self dictionaryFromOutput:outputs];
    
    return labelsAndScores ;
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    return @{ @"Features" : self.averageFeatureVec };
}


#pragma mark - Utilities

// TODO: ensure we dont copy too much data around.
// TODO: Keep out_tensors cached and re-use
// TODO: Cache resizeAndNormalizeSession to re-use.

- (std::vector<tensorflow::Tensor>) resizeAndNormalizeInputTensor:(tensorflow::Tensor)inputTensor
{
    tensorflow::Status status;
    std::vector<tensorflow::Tensor> out_tensors;
    std::string input_name = "input"; // was file_reader
    std::string output_name = "normalized";

    if(resizeSession == NULL)
    {
        auto root = tensorflow::Scope::NewRootScope();
        
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
           resizeSession = std::unique_ptr<tensorflow::Session>(tensorflow::NewSession(tensorflow::SessionOptions()));
            
            status = resizeSession->Create(graph);
            
            if( status.ok() )
            {
                status = resizeSession->Run({}, {output_name}, {}, &out_tensors);
                if( status.ok() )
                    return out_tensors;
            }
        }
    }
    else
    {
        status = resizeSession->Run({}, {output_name}, {}, &out_tensors);
        if( status.ok() )
            return out_tensors;

    }
    
    if(self.errorLog)
        self.errorLog(@"Error resizing and normalizing Tensor");
    
    out_tensors.clear();
    return out_tensors;
}

- (NSDictionary*) dictionaryFromOutput:(const std::vector<tensorflow::Tensor>&)outputs
{
    const int numLabels = std::min(5, static_cast<int>(self.labelsArray.count));

    std::vector<tensorflow::Tensor> out_tensors;
    tensorflow::Tensor indices;
    tensorflow::Tensor scores;
    std::string output_name = "top_k";

    if(topLabelsSession == NULL)
    {
        auto root = tensorflow::Scope::NewRootScope();
        
        tensorflow::ops::TopKV2(root.WithOpName(output_name), outputs[0], numLabels);

        // This runs the GraphDef network definition that we've just constructed, and
        // returns the results in the output tensors.
        tensorflow::GraphDef graph;
        root.ToGraphDef(&graph);
        
        topLabelsSession = std::unique_ptr<tensorflow::Session>(tensorflow::NewSession(tensorflow::SessionOptions()));
        topLabelsSession->Create(graph);
        
        // The TopK node returns two outputs, the scores and their original indices,
        // so we have to append :0 and :1 to specify them both.
        (topLabelsSession->Run({}, {output_name + ":0", output_name + ":1"},
                                        {}, &out_tensors));
    }
    else
    {
        (topLabelsSession->Run({}, {output_name + ":0", output_name + ":1"},
                               {}, &out_tensors));

    }
    
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
    
    // Feature Vector
//    tensorflow::DataType type = outputs[1].dtype();
    int64_t numElements = outputs[1].NumElements();
    
    tensorflow::TensorShape featureShape = outputs[1].shape();

//    auto featureVec = outputs[1].vec<float>();
//
//    for(auto element = featureVec.begin(); element != featureVec.end(); ++element)
//    {
//
//    }
    
//    for(auto featureElement = featureShape.begin(); featureElement != featureShape.end(); ++featureElement)
//    {
//        float element = *featureElement;
//        //auto& v = *it; // should also work
//        std::cout << v(0,0);
//        std::cout << v(1,0);
//    }

#pragma mark - Feature Vector
    
    // TODO: Figure out how to access the tensor values directly as floats
    std::string summaryFeatureVec = outputs[1].SummarizeValue(numElements);
    
    NSMutableString* featureVec = [NSMutableString stringWithCString:summaryFeatureVec.c_str() encoding:NSUTF8StringEncoding];
    
    // delete the [ and ]'s
    NSString* cleanedFeatureVec = [featureVec stringByReplacingOccurrencesOfString:@"[" withString:@""];
    cleanedFeatureVec = [cleanedFeatureVec stringByReplacingOccurrencesOfString:@"]" withString:@""];

    NSArray* stringsOfFeatureElements = [cleanedFeatureVec componentsSeparatedByString:@" "];
    
    NSMutableArray* featureElements = [NSMutableArray arrayWithCapacity:stringsOfFeatureElements.count];
    for(NSString* element in stringsOfFeatureElements)
    {
        [featureElements addObject:@( [element floatValue] ) ];
    }
    
    if(self.averageFeatureVec == nil)
    {
        self.averageFeatureVec = featureElements;
    }
    else
    {
        // average each vector element with the prior
        for(int i = 0; i < featureElements.count; i++)
        {
            float  a = [featureElements[i] floatValue];
            float  b = [self.averageFeatureVec[i] floatValue];
            
            self.averageFeatureVec[i] = @( (a + b / 2.0)) ;
        }
    }
    
    
    return @{ @"Labels" : outputLabels,
              @"Scores" : outputScores,
              };
}

@end
