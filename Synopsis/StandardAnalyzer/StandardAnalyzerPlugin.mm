//
//  OpenCVAnalyzerPlugin.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

// Include OpenCV before anything else because FUCK C++
//#import "highgui.hpp"

#import "opencv.hpp"
#import "ocl.hpp"
#import "types_c.h"
#import "features2d.hpp"
#import "utility.hpp"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>
#import <OpenCL/opencl.h>

#import "StandardAnalyzerPlugin.h"

#import "MedianCutOpenCV.hpp"
#import "CIEDE2000.h"

#import "LogController.h"

//#define TO_PERCEPTUAL cv::COLOR_BGR2HLS
//#define FROM_PERCEPTUAL cv::COLOR_HLS2BGR
//#define TO_PERCEPTUAL cv::COLOR_BGR2Luv
//#define FROM_PERCEPTUAL cv::COLOR_Luv2BGR
#define TO_PERCEPTUAL cv::COLOR_BGR2Lab
#define FROM_PERCEPTUAL cv::COLOR_Lab2BGR

#import "Defines.h"

@interface StandardAnalyzerPlugin ()
{
    // Custom OpenCL handling
//    cv::ocl::Context* openclIGPUContext;
//    cv::ocl::Context* openclDGPUContext;
//    cv::ocl::Context* openclCPUContext;
    
    //cv::ocl::Queue* mainCommandQueue;
    
    // Reused OpenCV Resources
    matType currentBGR8UC3Image;
    matType currentBGR32FC3Image;
    matType currentPerceptualImage;
    matType currentGray8UC1Image;
    
    matType lastImage;
    cv::Ptr<cv::ORB> detector;
    
    // No need for OpenCL for these
    cv::Mat accumulatedHist0;
    cv::Mat accumulatedHist1;
    cv::Mat accumulatedHist2;

    // for kMeans
    matType bestLables;
    matType centers;
    
    // For "Accumulated' DHas
    cv::Mat averageImageForHash;
    unsigned long long differenceHashAccumulated;

}

@property (atomic, readwrite, strong) NSString* pluginName;
@property (atomic, readwrite, strong) NSString* pluginIdentifier;

@property (atomic, readwrite, strong) NSArray* pluginAuthors;

@property (atomic, readwrite, strong) NSString* pluginDescription;

@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginAPIVersionMinor;

@property (atomic, readwrite, assign) NSUInteger pluginVersionMajor;
@property (atomic, readwrite, assign) NSUInteger pluginVersionMinor;

@property (atomic, readwrite, strong) NSDictionary* pluginReturnedMetadataKeysAndDataTypes;

@property (atomic, readwrite, strong) NSString* pluginMediaType;

// Module Support
@property (readwrite) BOOL hasModules;

@property (atomic, readwrite, strong) NSArray* moduleNames;

@property (atomic, readwrite, strong) NSMutableArray* everyDominantColor;
@property (atomic, readwrite, strong) NSMutableArray* everyHash;

@end

@implementation StandardAnalyzerPlugin

- (id) init
{
    self = [super init];
    if(self)
    {
        self.pluginName = @"OpenCV Analyzer";
        self.pluginIdentifier = @"info.v002.Synopsis.OpenCVAnalyzer";
        self.pluginAuthors = @[@"Anton Marini"];
        self.pluginDescription = @"OpenCV analysis for color, motion, features and more.";
        self.pluginAPIVersionMajor = 0;
        self.pluginAPIVersionMinor = 1;
        self.pluginVersionMajor = 0;
        self.pluginVersionMinor = 1;
        self.pluginMediaType = AVMediaTypeVideo;
        
        self.hasModules = YES;
        
        self.moduleNames  = @[@"Average Color",
                              @"Dominant Colors",
                              @"Features",
                              @"Motion",
                              @"Histogram",
                              @"Hash",
                              ];
        
        
//        const std::string info = cv::getBuildInformation();
//        NSLog(@"OpenCV Build Info: %@", [NSString stringWithCString:info.c_str() encoding:NSUTF8StringEncoding]);
        
        cv::setUseOptimized(true);
        
#if USE_OPENCL

        if(cv::ocl::haveOpenCL())
        {
            cv::ocl::setUseOpenCL(true);
            
//            openclIGPUContext = new cv::ocl::Context();
//            
//            if (!openclIGPUContext->create(cv::ocl::Device::TYPE_IGPU))
//            {
//                [[LogController sharedLogController] appendErrorLog:@"Unable to create Integrated GPU OpenCL Context"];
//            }
//            else
//            {
//                [[LogController sharedLogController] appendVerboseLog:@"Created Integrated GPU OpenCL Context"];
//            }
//            
//            openclDGPUContext = new cv::ocl::Context();
//
//            if (!openclDGPUContext->create(cv::ocl::Device::TYPE_DGPU))
//            {
//                [[LogController sharedLogController] appendErrorLog:@"Unable to create Discrete GPU OpenCL Context"];
//            }
//            else
//            {
//               [[LogController sharedLogController] appendVerboseLog:@"Created Discrete GPU OpenCL Context"];
//            }
//            
//            openclCPUContext = new cv::ocl::Context();
//            
//            if (!openclCPUContext->create(cv::ocl::Device::TYPE_CPU))
//            {
//                [[LogController sharedLogController] appendErrorLog:@"Unable to create CPU OpenCL Context"];
//            }
//            else
//            {
//                [[LogController sharedLogController] appendVerboseLog:@"Created CPU OpenCL Context"];
//            }
//            
//            for (int i = 0; i < openclIGPUContext->ndevices(); i++)
//            {
//                cv::ocl::Device device = openclIGPUContext->device(i);
//                NSLog(@"Device Name: %s", device.name().c_str());
//                NSLog(@"Available: %i", device.available());
//                NSLog(@"imageSupport: %i", device.imageSupport());
//                NSLog(@"OpenCL_C_Version: %s", device.OpenCL_C_Version().c_str());
//            }
//            
//            for (int i = 0; i < openclDGPUContext->ndevices(); i++)
//            {
//                cv::ocl::Device device = openclDGPUContext->device(i);
//                NSLog(@"Device Name: %s", device.name().c_str());
//                NSLog(@"Available: %s", device.available() ? "YES" : "NO");
//                NSLog(@"imageSupport: %s", device.imageSupport() ? "YES" : "NO");
//                NSLog(@"OpenCL_C_Version: %s", device.OpenCL_C_Version().c_str());
//            }
        }

        // We dont need our own queue unless we submit our own kernels it seems
//        mainCommandQueue = new cv::ocl::Queue(*(mainContext), mainContext->device(0));

#endif
        
        // Default parameters of ORB
        int nfeatures=100;
        float scaleFactor=1.2f;
        int nlevels=8;
        int edgeThreshold=20; // Changed default (31);
        int firstLevel=0;
        int WTA_K=2;
        int scoreType=cv::ORB::HARRIS_SCORE;
        int patchSize=31;
        int fastThreshold=20;
        
        detector = cv::ORB::create(nfeatures,
                                   scaleFactor,
                                   nlevels,
                                   edgeThreshold,
                                   firstLevel,
                                   WTA_K,
                                   scoreType,
                                   patchSize,
                                   fastThreshold );
        
        averageImageForHash = cv::Mat(8, 8, CV_8UC1);
        
//        lastImage = NULL;
        
        self.everyDominantColor = [NSMutableArray new];
        self.everyHash = [NSMutableArray new];
        
        differenceHashAccumulated = 0;

    }
    
    return self;
}

- (void) dealloc
{
    detector.release();
    
    currentBGR32FC3Image.release();
    currentBGR8UC3Image.release();
    currentGray8UC1Image.release();
    currentPerceptualImage.release();
    lastImage.release();

//    if(mainCommandQueue != nullptr)
//    	delete mainCommandQueue;

//    if(openclIGPUContext != nullptr)
//        delete openclIGPUContext;
//
//    if(openclDGPUContext != nullptr)
//        delete openclDGPUContext;
//
//    if(openclCPUContext != nullptr)
//        delete openclCPUContext;
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{
//    dispatch_async(dispatch_get_main_queue(), ^{
//        cv::namedWindow("OpenCV Debug", CV_WINDOW_NORMAL);
//    });
}

//static int lastDevice = 0;

- (void) submitAndCacheCurrentVideoBuffer:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow
{
    
#if USE_OPENCL
    // We enable / disable OpenCL per thread here
    // since we may be called on a dispatch queue whose underlying thread differs from our last call.
    // isnt this fun?
    
    // Simple round robin esque openCL device load bearing.
    
    // Idea is that since our OpenCL content is typically small
    // We dont get streaming performance to DGPUs
    // So we prefer Integrated
    
    // But maybe round robin between integrated and discreet is ok?
    // Who knows! This is hard!
    
    // If we dont have an integrated GPU
//    if( !openclIGPUContext->ndevices() )
//    {
//        // If we have a discrete GPU
////        if( openclDGPUContext->ndevices() )
////        {
////            // Ping Pong between discreet GPUs
////            int currentDevice = (lastDevice + 1) % (openclDGPUContext->ndevices());
////            cv::ocl::Device(openclDGPUContext->device(currentDevice));
////            lastDevice = currentDevice;
////        }
////        else
//        {
//            // Use the only  OpenCL context we have
//            cv::ocl::Device(openclCPUContext->device(0));
//        }
//    }
//    else
//    {
//        // If we have a more than a single GPU (and an integrated)
////        if( openclDGPUContext->ndevices() )
//
//        
//        cv::ocl::Device(openclIGPUContext->device(0));
//    }
//    
    
#endif
    
    cv::ocl::setUseOpenCL(USE_OPENCL);
    
    cv::Mat image = [self imageFromBaseAddress:baseAddress width:width height:height bytesPerRow:bytesPerRow];
    
    // Convert img BGRA to CIE_LAB or LCh - Float 32 for color calulation fidelity
    // Note floating point assumtions:
    // http://docs.opencv.org/2.4.11/modules/imgproc/doc/miscellaneous_transformations.html
    // The conventional ranges for R, G, and B channel values are:
    // 0 to 255 for CV_8U images
    // 0 to 65535 for CV_16U images
    // 0 to 1 for CV_32F images
    
    // Convert our 8 Bit BGRA to BGR
    cv::cvtColor(image, currentBGR8UC3Image, cv::COLOR_BGRA2BGR);

    // Convert 8 bit BGR to Grey
    cv::cvtColor(currentBGR8UC3Image, currentGray8UC1Image, cv::COLOR_BGR2GRAY);
    
    // Convert 8 Bit BGR to Float BGR
    currentBGR8UC3Image.convertTo(currentBGR32FC3Image, CV_32FC3, 1.0/255.0);
    
    // Convert Float BGR to Float Perceptual
    cv::cvtColor(currentBGR32FC3Image, currentPerceptualImage, TO_PERCEPTUAL);
}

- (cv::Mat) imageFromBaseAddress:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow
{
    size_t extendedWidth = bytesPerRow / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits

    return cv::Mat((int)height, (int)extendedWidth, CV_8UC4, baseAddress);
}

- (void) setOpenCLEnabled:(BOOL)enable
{
    if(enable)
    {
        if(cv::ocl::haveOpenCL())
        {
            cv::ocl::setUseOpenCL(true);
        }
        else
        {
            NSLog(@"Unable to Enable OpenCL - No OpenCL Devices detected");
        }
    }
    else
    {
        cv::ocl::setUseOpenCL(false);
    }
}

- (NSDictionary*) analyzeMetadataDictionaryForModuleIndex:(SynopsisModuleIndex)moduleIndex error:(NSError**)error
{
    NSDictionary* result = nil;

    
#define SHOWIMAGE 0
    
#if SHOWIMAGE
    
    cv::Mat flipped;
    cv::flip(currentBGRImage, flipped, 0);

    dispatch_sync(dispatch_get_main_queue(), ^{
        

        cv::imshow("Image", flipped);
    });

#endif
    
    // See inline notes for thoughts / considerations on each standard module.
    
    // Due to nuances with OpenCV's OpenCL (or maybe my own misunderstanding of OpenCL)
    // We cannot run this analysis in parallel for the OpenCL case.
    // We need to look into that...
    
    switch (moduleIndex)
    {
        case 0:
        {
            // This seems stupid and useless ?
            result = [self averageColorForCVMat:currentBGR32FC3Image];
            break;
        }
        case 1:
        {
            // KMeans is slow as hell and also stochastic - same image run 2x gets slightly different results.
            // Median Cut is not particularly accurate ? Maybe I have a subtle bug due to averaging / scaling?
            // Dominant colors still average absed on centroid, even though we attempt to look up the closest
            // real color value near the centroid.

            // This needs some looking at.
            
            // result = [self dominantColorForCVMatKMeans:currentPerceptualImage];
            result = [self dominantColorForCVMatMedianCutCV:currentPerceptualImage];
            break;
        }
        case 2:
        {
            // TODO: Experiment on Optical Flow techniques for features + motion amount + direction flow.
            // Can maybe lose the motion pass below.
            
            result = [self detectFeaturesORBCVMat:currentGray8UC1Image];
            
            // Todo: Implement Optical Flow:
            // result = [self detectFeaturesFlowCVMat:currentGray8UC1Image];
            break;
        }
        case 3:
        {
            result = [self detectMotionInCVMatAVG:currentGray8UC1Image];
            break;
        }
        case 4:
        {
            // Do we need this per frame?
            // Do we need this at all?
            // Does histogram similarity give us anything easily searchable?
            // Does histogram per frame give us anything to leverage for effects per frame?
            // Does a global accumulated histogram actually do anything for us at all
            
            result = [self detectHistogramInCVMat:currentBGR8UC3Image];
            break;
        }
        case 5:
        {
            // Its unclear if RGB hashing is of any benefit, since generally
            // speaking (and some testing confirms) that the GRADIENT's in
            // the RGB channels are similar, even if the values are different.
            // The resulting hashes tend to confirm this.
            
            // We should test to see if in fact searching / accuracy is worth
            // Storing the triple hash versis just one?
            
            // We also need to deduce a method to average the hash, or to compute
            // some sort of average image to hash.
            // My gut says literally averaging the image wont really result a useful difference
            // gradient, as we are just kind of making each frame more like the other
            // the opposite of a difference gradient.
            
            // Perhaps difference each frame with the last ?
            
            // result = [self differenceHashRGBInCVMat:currentBGR8UC3Image];
//            result = [self differenceHashGreyInCVMat:currentGray8UC1Image];
            result = [self perceptualHashGreyInCVMat:currentGray8UC1Image];
          break;
        }
            
        default:
            return nil;
    }
    
    return result;
}

- (NSDictionary*) averageColorForCVMat:(matType)image
{
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    cv::Scalar avgPixelIntensity = cv::mean(image);
    
    
    // Add to metadata - normalize to float
    metadata[@"AverageColor"] = @[@(avgPixelIntensity.val[2]), // R
                                  @(avgPixelIntensity.val[1]), // G
                                  @(avgPixelIntensity.val[0]), // B
                                  ];
    
    return metadata;
}

#pragma mark - Dominant Colors / Median Cut Method

- (cv::Mat) nearestColorCIEDE2000:(cv::Vec3f)labColorVec3f inFrame:(matType)frame
{
    cv::Vec3f closestDeltaEColor;
    
    double delta = DBL_MAX;
    
    // iterate every pixel in our frame, and generate an CIEDE2000::LAB color from it
    // test the delta, and test if our pixel is our min
    
#if USE_OPENCL
    // Get a MAT from our UMat
    cv::Mat frameMAT = frame.getMat(cv::ACCESS_READ);
#else
    cv::Mat frameMAT = frame;
#endif
    
    // Populate Median Cut Points by color values;
    for(int i = 0;  i < frameMAT.rows; i++)
    {
        for(int j = 0; j < frameMAT.cols; j++)
        {
            // get pixel value
            cv::Vec3f frameLABColor = frameMAT.at<cv::Vec3f>(i, j);

            double currentPixelDelta = CIEDE2000::CIEDE2000(labColorVec3f, frameLABColor);
            
            if(currentPixelDelta < delta)
            {
                closestDeltaEColor = frameLABColor;
                delta = currentPixelDelta;
            }
        }
    }
    
#if USE_OPENCL
    // Free Mat which unlocks our UMAT if we have it
    frameMAT.release();
#endif
    
    cv::Mat closestLABColor(1,1, CV_32FC3, closestDeltaEColor);
    return closestLABColor;
}

// This doesnt appear to do anything.
- (cv::Mat) nearestColorMinMaxLoc:(cv::Vec3f)colorVec inFrame:(matType)frame
{
    //  find our nearest *actual* LAB pixel in the frame, not from the median cut..
    // Split image into channels
    std::vector<matType> frameChannels;
    cv::split(frame, frameChannels);
    
    // Find absolute differences for each channel
    matType diff_L;
    cv::absdiff(frameChannels[0], colorVec[0], diff_L);
    matType diff_A;
    cv::absdiff(frameChannels[1], colorVec[1], diff_A);
    matType diff_B;
    cv::absdiff(frameChannels[2], colorVec[2], diff_B);
    
    // Calculate L1 distance (diff_L + diff_A + diff_B)
    matType dist;
    matType dist2;
    cv::add(diff_L, diff_A, dist);
    cv::add(dist, diff_B, dist2);
    
    // Find the location of pixel with minimum color distance
    cv::Point minLoc;
    cv::minMaxLoc(dist2, 0, 0, &minLoc);

    // get pixel value
#if USE_OPENCL
    cv::Mat frameMat = frame.getMat(cv::ACCESS_READ);
    cv::Vec3f closestColor = frameMat.at<cv::Vec3f>(minLoc);
    frameMat.release();
#else
    cv::Vec3f closestColor = frame.at<cv::Vec3f>(minLoc);
#endif
    
    cv::Mat closestColorPixel(1,1, CV_32FC3, closestColor);
    
    return closestColorPixel;
}

- (NSDictionary*) dominantColorForCVMatMedianCutCV:(matType)image
{
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // Also this code is heavilly borrowed so yea.
    int k = 5;
    
    bool useCIEDE2000 = USE_CIEDE2000;
    
    #if USE_OPENCL
        cv::Mat imageMat = image.getMat(cv::ACCESS_READ);
    #else
        cv::Mat imageMat = image;
    #endif
    
    auto palette = MedianCutOpenCV::medianCut(imageMat, k, useCIEDE2000);

    #if USE_OPENCL
        imageMat.release();
    #endif

    
    NSMutableArray* dominantColors = [NSMutableArray new];
    
    for ( auto colorCountPair: palette )
    {
        // convert from LAB to BGR
        const cv::Vec3f& labColor = colorCountPair.first;
        
        cv::Mat closestLABPixel = cv::Mat(1,1, CV_32FC3, labColor);

        // Looking at inspector output, its not clear that nearestColorMinMaxLoc is effective at all
//        cv::Mat closestLABPixel = [self nearestColorMinMaxLoc:labColor inFrame:image];
//        cv::Mat closestLABPixel = [self nearestColorCIEDE2000:labColor inFrame:image];
        
        // convert to BGR
        cv::Mat bgr(1,1, CV_32FC3);
        cv::cvtColor(closestLABPixel, bgr, FROM_PERCEPTUAL);
        
        cv::Vec3f bgrColor = bgr.at<cv::Vec3f>(0,0);
        
        NSArray* color = @[@(bgrColor[2]), // / 255.0), // R
                           @(bgrColor[1]), // / 255.0), // G
                           @(bgrColor[0]), // / 255.0), // B
                           ];
        
        NSArray* lColor = @[ @(labColor[0]), // L
                             @(labColor[1]), // A
                             @(labColor[2]), // B
                             ];
        
        [dominantColors addObject:color];
        
        // We will process this in finalize
        [self.everyDominantColor addObject:lColor];
    }
    
    metadata[@"DominantColors"] = dominantColors;
    
    return metadata;

}

- (NSDictionary*) dominantColorForCVMatKMeans:(matType)image
{
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // We choose k = 5 to match Adobe Kuler because whatever.
    int k = 5;
    int n = currentPerceptualImage.rows * currentPerceptualImage.cols;
    
    std::vector<matType> imgSplit;
    cv::split(currentPerceptualImage,imgSplit);
    
    matType img3xN(n,3,CV_32F);
    
    for(int i = 0; i != 3; ++i)
    {
        imgSplit[i].reshape(1,n).copyTo(img3xN.col(i));
    }
    
    // TODO: figure out what the fuck makes sense here.
    cv::kmeans(img3xN,
               k,
               bestLables,
//               cv::TermCriteria(),
               cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 5.0, 1.0),
               5,
               cv::KMEANS_PP_CENTERS,
               centers);
    
    NSMutableArray* dominantColors = [NSMutableArray new];
    
    //            cv::imshow("OpenCV Debug", quarterResLAB);
    
    for(int i = 0; i < centers.rows; i++)
    {
        // 0 1 or 0 - 255 .0 ?
#if USE_OPENCL
        cv::Mat centersMat = centers.getMat(cv::ACCESS_READ);
        cv::Vec3f labColor = centersMat.at<cv::Vec3f>(i, 0);
        centersMat.release();
#else
        cv::Vec3f labColor = centers.at<cv::Vec3f>(i, 0);
#endif
        
        cv::Mat lab(1,1, CV_32FC3, cv::Vec3f(labColor[0], labColor[1], labColor[2]));
        
        cv::Mat bgr(1,1, CV_32FC3);
        
        cv::cvtColor(lab, bgr, FROM_PERCEPTUAL);
        
        cv::Vec3f bgrColor = bgr.at<cv::Vec3f>(0,0);
        
        NSArray* color = @[@(bgrColor[2]), // / 255.0), // R
                           @(bgrColor[1]), // / 255.0), // G
                           @(bgrColor[0]), // / 255.0), // B
                           ];
        
        NSArray* lColor = @[ @(labColor[0]), // L
                             @(labColor[1]), // A
                             @(labColor[2]), // B
                             ];

        [dominantColors addObject:color];
        
        // We will process this in finalize
        [self.everyDominantColor addObject:lColor];
    }
    
    metadata[@"DominantColors"] = dominantColors;
    
    return metadata;
}

#pragma mark - Feature Detection

- (NSDictionary*) detectFeaturesORBCVMat:(matType)image
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    std::vector<cv::KeyPoint> keypoints;
    detector->detect(image, keypoints, cv::noArray());
    
    NSMutableArray* keyPointsArray = [NSMutableArray new];
    
    for(std::vector<cv::KeyPoint>::iterator keyPoint = keypoints.begin(); keyPoint != keypoints.end(); keyPoint++)
    {
        CGPoint point = CGPointZero;
        {
            point = CGPointMake((float)keyPoint->pt.x / (float)image.size().width,
                                (float)keyPoint->pt.y / (float)image.size().height);
        }
        
        [keyPointsArray addObject:@[ @(point.x), @(point.y)]];
    }
    
//    cv::goodFeaturesToTrack(<#InputArray image#>, <#OutputArray corners#>, <#int maxCorners#>, <#double qualityLevel#>, <#double minDistance#>)
    
    // Add Features to metadata
    metadata[@"Features"] = keyPointsArray;
        
    return metadata;
}

- (NSDictionary*) detectFeaturesFLowCVMat:(matType)image
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    cv::Mat corners;
    cv::goodFeaturesToTrack(image, corners, 200, 1.0, 0.1);
    
    
    for(int i = 0; i < corners.rows; i++)
    {
        cv::Vec2f corner = corners.at<cv::Vec2f>(i, 0);
        
    }
    
    // Add Features to metadata
//    metadata[@"Features"] = keyPointsArray;
    
    return metadata;
}


#pragma mark - Frame Difference Motion

- (NSDictionary*) detectMotionInCVMatAVG:(matType)image
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // Can we do frame differencing - note all these tests should pass because we got it last time when the sample was current
    // otherwise it wouldnt be set as last.
    if(!lastImage.empty())
    {
        matType diff;
        cv::subtract(image, lastImage, diff);
        
        // Average the difference:
        cv::Scalar avgMotion = cv::mean(diff);
        
        // Normalize to float
        metadata[@"Motion"] = @(avgMotion.val[0] / 255.0);
    }
    else {
        metadata[@"Motion"] = @(0);
    }
    
    image.copyTo(self->lastImage);
    
    return metadata;
}

//- (NSDictionary*) detectMotionInCVMatOpticalFlow:(matType)image
//{
//    NSMutableDictionary* metadata = [NSMutableDictionary new];
//
//}
//

#pragma mark - Histogram

- (NSDictionary*) detectHistogramInCVMat:(matType)image
{
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // Split image into channels
    std::vector<cv::Mat> imageChannels(3);
    cv::split(image, imageChannels);
    
    cv::Mat histMat0, histMat1, histMat2;
    
    int numBins = 256;
    int histSize[] = {numBins};
    
    float range[] = { 0, 256 };
    const float* ranges[] = { range };

    // we compute the histogram from these channels
    int channels[] = {0};
    
    // TODO : use Accumulation of histogram to average over all frames ?
    
    calcHist(&imageChannels[0], // image
             1, // image count
             channels, // channel mapping
             cv::Mat(), // do not use mask
             histMat0,
             1, // dimensions
             histSize,
             ranges,
             true, // the histogram is uniform
             false );
    
    calcHist(&imageChannels[1], // image
             1, // image count
             channels, // channel mapping
             cv::Mat(), // do not use mask
             histMat1,
             1, // dimensions
             histSize,
             ranges,
             true, // the histogram is uniform
             false );
    
    calcHist(&imageChannels[2], // image
             1, // image count
             channels, // channel mapping
             cv::Mat(), // do not use mask
             histMat2,
             1, // dimensions
             histSize,
             ranges,
             true, // the histogram is uniform
             false );
    
    // We are going to accumulate our histogram to get an average histogram for every frame of the movie
    if(accumulatedHist0.empty())
    {
        histMat0.copyTo(accumulatedHist0);
    }
    else
    {
        cv::add(accumulatedHist0, histMat0, accumulatedHist0);
    }

    if(accumulatedHist1.empty())
    {
        histMat1.copyTo(accumulatedHist1);
    }
    else
    {
        cv::add(accumulatedHist1, histMat1, accumulatedHist1);
    }

    if(accumulatedHist2.empty())
    {
        histMat2.copyTo(accumulatedHist2);
    }
    else
    {
        cv::add(accumulatedHist2, histMat2, accumulatedHist2);
    }
    
    // Normalize the result
    normalize(histMat0, histMat0, 0.0, 256, cv::NORM_MINMAX, -1, cv::Mat() );
    normalize(histMat1, histMat1, 0.0, 256, cv::NORM_MINMAX, -1, cv::Mat() );
    normalize(histMat2, histMat2, 0.0, 256, cv::NORM_MINMAX, -1, cv::Mat() );
    
    NSMutableArray* histogramValues = [NSMutableArray arrayWithCapacity:histMat0.rows];
    
    for(int i = 0; i < histMat0.rows; i++)
    {
        NSArray* channelValuesForRow = @[ @( histMat2.at<float>(i, 0) / 255.0 ), // R
                                          @( histMat1.at<float>(i, 0) / 255.0 ), // G
                                          @( histMat0.at<float>(i, 0) / 255.0 ), // B
                                          ];
        
        histogramValues[i] = channelValuesForRow;
        
    }
    
    
    metadata[@"Histogram"] = histogramValues;
    
    return metadata;
}

#pragma mark - Hashing

- (NSDictionary*) differenceHashRGBInCVMat:(matType)image
{
    
    // resize greyscale to 8x8
    matType eightByEight;
    cv::resize(image, eightByEight, cv::Size(8,8));
    
#if USE_OPENCL
    cv::Mat imageMat = eightByEight.getMat(cv::ACCESS_READ);
#else
    cv::Mat imageMat = eightByEight;
#endif
    
    unsigned long long differenceHashR = 0;
    unsigned long long differenceHashG = 0;
    unsigned long long differenceHashB = 0;

    cv::Vec3b lastValue;

    for(int i = 0;  i < imageMat.rows; i++)
    {
        for(int j = 0; j < imageMat.cols; j++)
        {
            differenceHashR <<= 1;
            differenceHashG <<= 1;
            differenceHashB <<= 1;

            // get pixel value
            cv::Vec3b value = imageMat.at<cv::Vec3b>(i, j);
            
            differenceHashR |=  1 * ( value[2] >= lastValue[2]);
            differenceHashG |=  1 * ( value[1] >= lastValue[1]);
            differenceHashB |=  1 * ( value[0] >= lastValue[0]);
            
            lastValue = value;
        }
    }

#if USE_OPENCL
    imageMat.release();
#endif
    
    return @{@"Hash R" : [NSString stringWithFormat:@"%llx", differenceHashR],
             @"Hash G" : [NSString stringWithFormat:@"%llx", differenceHashG],
             @"Hash B" : [NSString stringWithFormat:@"%llx", differenceHashB],
             };
}

- (NSDictionary*) differenceHashGreyInCVMat:(matType)image
{
    // resize greyscale to 8x8
    matType eightByEight;
    cv::resize(image, eightByEight, cv::Size(8,8));
    
#if USE_OPENCL
    cv::Mat imageMat = eightByEight.getMat(cv::ACCESS_READ);
#else
    cv::Mat imageMat = eightByEight;
#endif
    
    unsigned long long differenceHash = 0;
    unsigned char lastValue = 127;

    for(int i = 0;  i < imageMat.rows; i++)
    {
        for(int j = 0; j < imageMat.cols; j++)
        {
            differenceHash <<= 1;
            
            // get pixel value
            unsigned char value = imageMat.at<unsigned char>(i, j);
            
            differenceHash |=  1 * ( value >= lastValue);
            
            lastValue = value;
        }
    }
    
    // average our running average with our imageMat
    if(averageImageForHash.empty())
    {
        averageImageForHash = imageMat.clone();
    }
    else
    {
        cv::addWeighted(imageMat, 0.5, averageImageForHash, 0.5, 0.0, averageImageForHash);
    }
    
#if USE_OPENCL
    imageMat.release();
#endif
    
    // Experiment with different accumulation strategies for our Hash?
    differenceHashAccumulated = differenceHashAccumulated ^ differenceHash;
    
    return @{
             @"Hash" : [NSString stringWithFormat:@"%llx", differenceHash],
            };
}

- (NSDictionary*) perceptualHashGreyInCVMat:(matType)image
{
    // resize greyscale to 8x8
    matType thirtyTwo;
    cv::resize(image, thirtyTwo, cv::Size(32,32));

    thirtyTwo.convertTo(thirtyTwo, CV_32FC1);
    
    // calculate DCT on our float image
    matType dct;
    
    cv::dct(thirtyTwo, dct);
    
#if USE_OPENCL
    cv::Mat dctMat = dct.getMat(cv::ACCESS_READ);
#else
    cv::Mat dctMat = dct;
#endif
    
    // sample only the top left to get lowest frequency components in an 8x8
    // Setup a rectangle to define your region of interest
    cv::Rect roi(0, 0, 8, 8);

    cv::Mat dctEight = dctMat(roi);
    dctEight.at<float>(0, 0) = 0;
    
    cv::Scalar mean = cv::mean(dctEight);
    float meanD = mean[0];
    
    uint64_t differenceHash = 0x0000000000000000;
    uint64_t one = 0x0000000000000001;
    
    for(int i = 0;  i < dctEight.rows; i++)
    {
        for(int j = 0; j < dctEight.cols; j++)
        {
            // get pixel value
            float value = dctEight.at<float>(i, j);
            if( value >= meanD)
                differenceHash |=  one;
            
            one = one << 1;
 
        }
    }

    NSString* hashString = [NSString stringWithFormat:@"%llx", differenceHash];

    [self.everyHash addObject:hashString];
    
#if USE_OPENCL
    dctMat.release();
#endif
    
    return @{
             @"Hash" : hashString,
             };
}


#pragma mark - Finalization

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    // Histogram:
    
    // Normalize the result
    normalize(accumulatedHist0, accumulatedHist0, 0.0, 256, cv::NORM_MINMAX, -1, cv::Mat() ); // B
    normalize(accumulatedHist1, accumulatedHist1, 0.0, 256, cv::NORM_MINMAX, -1, cv::Mat() ); // G
    normalize(accumulatedHist2, accumulatedHist2, 0.0, 256, cv::NORM_MINMAX, -1, cv::Mat() ); // R
    
    NSMutableArray* histogramValues = [NSMutableArray arrayWithCapacity:accumulatedHist0.rows];
    
    for(int i = 0; i < accumulatedHist0.rows; i++)
    {
        NSArray* channelValuesForRow = @[ @( accumulatedHist2.at<float>(i, 0) / 255.0 ), // R
                                          @( accumulatedHist1.at<float>(i, 0) / 255.0 ), // G
                                          @( accumulatedHist0.at<float>(i, 0) / 255.0 ), // B
                                          ];
        
        histogramValues[i] = channelValuesForRow;
    }
    
    
    // Also this code is heavilly borrowed so yea.
    int k = 5;
    int numPixels = (int)self.everyDominantColor.count;
    
    int sourceColorCount = 0;

    cv::Mat allDomColors = cv::Mat(1, numPixels, CV_32FC3);

    // Populate Median Cut Points by color values;
    for(NSArray* dominantColorsArray in self.everyDominantColor)
    {
        allDomColors.at<cv::Vec3f>(0, sourceColorCount) = cv::Vec3f([dominantColorsArray[0] floatValue], [dominantColorsArray[1] floatValue], [dominantColorsArray[2] floatValue]);
        sourceColorCount++;
    }
    
    bool useCIEDE2000 = USE_CIEDE2000;
    
    MedianCutOpenCV::ColorCube allColorCube(allDomColors, useCIEDE2000);
    
    auto palette = MedianCutOpenCV::medianCut(allColorCube, k, useCIEDE2000);
    
    NSMutableArray* dominantColors = [NSMutableArray new];
    
    for ( auto colorCountPair: palette )
    {
        // convert from LAB to BGR
        const cv::Vec3f& labColor = colorCountPair.first;
        
        cv::Mat closestLABPixel = cv::Mat(1,1, CV_32FC3, labColor);
        cv::Mat bgr(1,1, CV_32FC3);
        cv::cvtColor(closestLABPixel, bgr, FROM_PERCEPTUAL);
        
        cv::Vec3f bgrColor = bgr.at<cv::Vec3f>(0,0);
        
        [dominantColors addObject: @[@(bgrColor[2]),
                                     @(bgrColor[1]),
                                     @(bgrColor[0]),
                                     ]];
    }
    
    NSString* firstHash = self.everyHash[0];
    NSString* lastHash = [self.everyHash lastObject];
    NSString* firstQuarterHash = self.everyHash[self.everyHash.count/4];
    NSString* lastQuarterHash = self.everyHash[self.everyHash.count/4 + self.everyHash.count/2];
    
//    unsigned long long differenceHash = 0;
//    unsigned char lastValue = 0;
//    
//    // Calculate Hash from running average image
//    for(int i = 0;  i < averageImageForHash.rows; i++)
//    {
//        for(int j = 0; j < averageImageForHash.cols; j++)
//        {
//            differenceHash <<= 1;
//            
//            // get pixel value
//            unsigned char value = averageImageForHash.at<unsigned char>(i, j);
//            
//            //cv::Vec3i
//            differenceHash |=  1 * ( value >= lastValue);
//            
//            lastValue = value;
//        }
//    }
    
    // If we have our old last sample buffer, free it
    lastImage.release();
    averageImageForHash.release();
    
    return  @{@"DominantColors" : dominantColors,
              @"Histogram" : histogramValues,
              @"Hash" : [NSString stringWithFormat:@"%@-%@-%@-%@", firstHash,firstQuarterHash,lastQuarterHash, lastHash],
              @"Description" : [self matchColorNamesToColors:dominantColors],
              };
}


#pragma mark - Color Helpers

-(NSArray*) matchColorNamesToColors:(NSArray*)colorArray
{
    CGColorSpaceRef linear = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    NSColorSpace* colorspace = [[NSColorSpace alloc] initWithCGColorSpace:linear];
    CGColorSpaceRelease(linear);

    NSMutableArray* dominantNSColors = [NSMutableArray arrayWithCapacity:colorArray.count];
    
    for(NSArray* color in colorArray)
    {
        CGFloat alpha = 1.0;
        if(color.count > 3)
            alpha = [color[3] floatValue];
        
        NSColor* domColor = [[NSColor colorWithRed:[color[0] floatValue]
                                            green:[color[1] floatValue]
                                             blue:[color[2] floatValue]
                                            alpha:alpha] colorUsingColorSpace:colorspace];
        
        [dominantNSColors addObject:domColor];
    }
    
    NSMutableSet* matchedNamedColors = [NSMutableSet setWithCapacity:dominantNSColors.count];
    
    for(NSColor* color in dominantNSColors)
    {
        NSString* namedColor = [self closestNamedColorForColor:color];
        NSLog(@"Found Color %@", namedColor);
        if(namedColor)
            [matchedNamedColors addObject:namedColor];
    }
    
    return matchedNamedColors.allObjects;
}

- (NSString*) closestNamedColorForColor:(NSColor*)color
{
    NSColor* matchedColor = nil;
    
    // White, Grey, Black all are 'calibrated white' color spaces so you cant fetch color components from them
    // because no one at apple has seen a fucking prism.
    CGColorSpaceRef linear = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    NSColorSpace* colorspace = [[NSColorSpace alloc] initWithCGColorSpace:linear];
    CGColorSpaceRelease(linear);
    
    CGFloat white[4] = {1.0, 1.0, 1.0, 1.0};
    CGFloat black[4] = {0.0, 0.0, 0.0, 1.0};
    CGFloat gray[4] = {0.5, 0.5, 0.5, 1.0};

    CGFloat red[4] = {1.0, 0.0, 0.0, 1.0};
    CGFloat green[4] = {0.0, 1.0, 0.0, 1.0};
    CGFloat blue[4] = {0.0, 0.0, 1.0, 1.0};

    CGFloat cyan[4] = {0.0, 1.0, 1.0, 1.0};
    CGFloat magenta[4] = {1.0, 0.0, 1.0, 1.0};
    CGFloat yellow[4] = {1.0, 1.0, 0.0, 1.0};

    CGFloat orange[4] = {1.0, 0.5, 0.0, 1.0};
    CGFloat purple[4] = {1.0, 0.0, 1.0, 1.0};

    NSDictionary* knownColors = @{ @"White" : [NSColor colorWithColorSpace:colorspace components:white count:4], // White
                                   @"Black" : [NSColor colorWithColorSpace:colorspace components:black count:4], // Black
                                   @"Gray" : [NSColor colorWithColorSpace:colorspace components:gray count:4], // Gray
                                   @"Red" : [NSColor colorWithColorSpace:colorspace components:red count:4],
                                   @"Green" : [NSColor colorWithColorSpace:colorspace components:green count:4],
                                   @"Blue" : [NSColor colorWithColorSpace:colorspace components:blue count:4],
                                   @"Cyan" : [NSColor colorWithColorSpace:colorspace components:cyan count:4],
                                   @"Magenta" : [NSColor colorWithColorSpace:colorspace components:magenta count:4],
                                   @"Yellow" : [NSColor colorWithColorSpace:colorspace components:yellow count:4],
                                   @"Orange" : [NSColor colorWithColorSpace:colorspace components:orange count:4],
                                   @"Purple" : [NSColor colorWithColorSpace:colorspace components:purple count:4],
                                   };
    
    //    NSUInteger numberMatches = 0;
    
    // Longest distance from any float color component
    CGFloat distance = CGFLOAT_MAX;
    
    for(NSColor* namedColor in [knownColors allValues])
    {
        CGFloat namedRed = [namedColor hueComponent];
        CGFloat namedGreen = [namedColor saturationComponent];
        CGFloat namedBlue = [namedColor brightnessComponent];
        
        CGFloat red = [color hueComponent];
        CGFloat green = [color saturationComponent];
        CGFloat blue = [color brightnessComponent];
        
        // Early bail
        if( red == namedRed && green == namedGreen && blue == namedBlue)
        {
            matchedColor = namedColor;
            break;
        }
        
        CGFloat newDistance = sqrt( pow( fabs(namedRed - red), 2.0) + pow( fabs(namedGreen - green), 2.0) + pow(fabs(namedBlue - blue), 2.0));
        
        if(newDistance < distance)
        {
            distance = newDistance;
            matchedColor = namedColor;
        }
    }
    
    return [[knownColors allKeysForObject:matchedColor] firstObject];
}

@end
