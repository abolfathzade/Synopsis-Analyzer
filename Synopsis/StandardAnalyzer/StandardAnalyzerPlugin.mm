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

#import "StandardAnalyzerPlugin.h"

#import "MedianCut.h"
#import "CIEDE2000.h"

#define TO_PERCEPTUAL cv::COLOR_BGR2Luv
#define FROM_PERCEPTUAL cv::COLOR_Luv2BGR
//#define TO_PERCEPTUAL cv::COLOR_BGR2Lab
//#define FROM_PERCEPTUAL cv::COLOR_Lab2BGR

#define USE_OPENCL 1

#if USE_OPENCL
#define matType cv::UMat
#else
#define matType cv::Mat
#endif

@interface StandardAnalyzerPlugin ()
{
    matType currentBGRImage;
    matType currentPerceptualImage;
    matType currentGray8u3Image;
    
    matType lastImage;
    cv::Ptr<cv::ORB> detector;
    
    // for kMeans
    matType bestLables;
    matType centers;
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
                              ];
        
        cv::setUseOptimized(true);
        
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
        
        
//        lastImage = NULL;
        
        self.everyDominantColor = [NSMutableArray new];

    }
    
    return self;
}

- (void) dealloc
{
    detector.release();
    
    currentBGRImage.release();
    currentPerceptualImage.release();
    lastImage.release();
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{
}

- (void) submitAndCacheCurrentVideoBuffer:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow
{
    // We enable / disable OpenCL per thread here
    // since we may be called on a dispatch queue whose underlying thread differs from our last call.
    // isnt this fun?
    
    [self setOpenCLEnabled:USE_OPENCL];
    
    cv::Mat image = [self imageFromBaseAddress:baseAddress width:width height:height bytesPerRow:bytesPerRow];
    
    // This needs to be refactored - ideally we can median cut straight from a cv::Mat
    // But whatever, Kmeans is so goddamned slow anyway
    
    // Convert img BGRA to CIE_LAB or LCh - Float 32 for color calulation fidelity
    // Note floating point assumtions:
    // http://docs.opencv.org/2.4.11/modules/imgproc/doc/miscellaneous_transformations.html
    // The conventional ranges for R, G, and B channel values are:
    // 0 to 255 for CV_8U images
    // 0 to 65535 for CV_16U images
    // 0 to 1 for CV_32F images
    
    // Convert our 8 Bit BGRA to Gray
    cv::cvtColor(image, currentGray8u3Image, cv::COLOR_BGRA2GRAY);

    // Convert to Float for maximum color fidelity
    matType quarterResBGRAFloat = matType();
    
    image.copyTo(quarterResBGRAFloat);
    
    quarterResBGRAFloat.convertTo(quarterResBGRAFloat, CV_32FC4, 1.0/255.0);
    
    matType quarterResBGR = currentPerceptualImage = matType(quarterResBGRAFloat.size(), CV_32FC3);
    matType quarterResLAB = currentBGRImage = matType(quarterResBGRAFloat.size(), CV_32FC3);
    
    cv::cvtColor(quarterResBGRAFloat, quarterResBGR, cv::COLOR_BGRA2BGR);
    cv::cvtColor(quarterResBGR, quarterResLAB, TO_PERCEPTUAL);
    
    currentPerceptualImage = quarterResLAB;
    currentBGRImage = quarterResBGR;
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
    
    switch (moduleIndex)
    {
        case 0:
        {
            result = [self averageColorForCVMat:currentBGRImage];
            break;
        }
        case 1:
        {
            result = [self dominantColorForCVMatMedianCut:currentPerceptualImage];
            //                result = [self dominantColorForCVMatKMeans:currentPerceptualImage];
            break;
        }
        case 2:
        {
            result = [self detectFeaturesCVMat:currentGray8u3Image];
            break;
        }
        case 3:
        {
            result = [self detectMotionInCVMat:currentBGRImage];
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
    CIEDE2000::LAB deltaEColor;
    CIEDE2000::LAB closestDeltaEColor;
    CIEDE2000::LAB frameDeltaEColor;

    deltaEColor.l = labColorVec3f[0];
    deltaEColor.a = labColorVec3f[1];
    deltaEColor.b = labColorVec3f[2];
    
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

            frameDeltaEColor.l = frameLABColor[0];
            frameDeltaEColor.a = frameLABColor[1];
            frameDeltaEColor.b = frameLABColor[2];

            double currentPixelDelta = CIEDE2000::CIEDE2000(deltaEColor, frameDeltaEColor);
            
            if(currentPixelDelta < delta)
            {
                closestDeltaEColor = deltaEColor;
                delta = currentPixelDelta;
            }
        }
    }
    
#if USE_OPENCL
    // Free Mat which unlocks our UMAT if we have it
    frameMAT.release();
#endif
    
    cv::Mat closestLABColor(1,1, CV_32FC3, cv::Vec3f(closestDeltaEColor.l, closestDeltaEColor.a, closestDeltaEColor.b));
    return closestLABColor;
}

- (cv::Mat) nearestColorMinMaxLoc:(cv::Vec3f)colorVec inFrame:(matType)frame
{
    //  find our nearest *actual* LAB pixel in the frame, not from the median cut..
    // Split image into channels
    std::vector<matType> frameChannels;
    cv::split(frame, frameChannels);
    
    // Find absolute differences for each channel
    matType diff_L;
    cv::absdiff(frameChannels[0], colorVec[2], diff_L);
    matType diff_A;
    cv::absdiff(frameChannels[1], colorVec[1], diff_A);
    matType diff_B;
    cv::absdiff(frameChannels[0], colorVec[0], diff_B);
    
    // Calculate L1 distance (diff_L + diff_A + diff_B)
    matType dist;
    cv::add(diff_L, diff_A, dist);
    cv::add(dist, diff_B, dist);
    
    // Find the location of pixel with minimum color distance
    cv::Point minLoc;
    cv::minMaxLoc(dist, 0, 0, &minLoc);

    // get pixel value
#if USE_OPENCL
    cv::Vec3f closestColor = frame.getMat(cv::ACCESS_READ).at<cv::Vec3f>(minLoc);
#else
    cv::Vec3f closestColor = frame.at<cv::Vec3f>(minLoc);
#endif
    
    cv::Mat closestColorPixel(1,1, CV_32FC3, closestColor);

    return closestColorPixel;
}

- (NSDictionary*) dominantColorForCVMatMedianCut:(matType)image
{
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // Also this code is heavilly borrowed so yea.
    int k = 5;
    int numPixels =  currentPerceptualImage.rows * currentPerceptualImage.cols;
    
    // Walk through the pixels and store colours.
    // Let's be fancy and make a smart pointer. Unfortunately shared_ptr doesn't automatically know how to delete a C++ array, so we have to write a [] lambda (aka 'block' in Obj-C) to clean up the object.
    std::shared_ptr<MedianCut::Point> points(new MedianCut::Point[numPixels],
                                             []( MedianCut::Point* p ) { delete[] p; } );
    
    int sourceColorCount = 0;
    
    // TODO: Optimize Median Cut for OpenCL somehow? Is that even possible?
    // Use some different OpenCV method?
    
#if USE_OPENCL
    // Get a MAT from our UMat
    cv::Mat currentPerceptualImageMAT = currentPerceptualImage.getMat(cv::ACCESS_READ);
#else
    cv::Mat currentPerceptualImageMAT = currentPerceptualImage;
#endif
    
    // Populate Median Cut Points by color values;
    for(int i = 0;  i < currentPerceptualImageMAT.rows; i++)
    {
        for(int j = 0; j < currentPerceptualImageMAT.cols; j++)
        {
            // You can now access the pixel value with cv::Vec3 (or 4 for if BGRA)
            cv::Vec3f labColor = currentPerceptualImageMAT.at<cv::Vec3f>(i, j);
            
            points.get()[sourceColorCount].x[0] = labColor[0]; // B L
            points.get()[sourceColorCount].x[1] = labColor[1]; // G A
            points.get()[sourceColorCount].x[2] = labColor[2]; // R B
            
            sourceColorCount++;
        }
    }
    
#if USE_OPENCL
    // Clear our cv::Mat backed by our OpenCL buffer
    currentPerceptualImageMAT.release();
#endif
    
    auto palette = MedianCut::medianCut(points.get(), numPixels, k);
    
    NSMutableArray* dominantColors = [NSMutableArray new];
    
    for ( auto colorCountPair: palette )
    {
        // convert from LAB to BGR
        const MedianCut::Point& labColorPoint = colorCountPair.first;
       
        cv::Vec3f labColorVec3F = cv::Vec3f(labColorPoint.x[0], labColorPoint.x[1], labColorPoint.x[2]);
        
        cv::Mat closestLABPixel = [self nearestColorMinMaxLoc:labColorVec3F inFrame:currentPerceptualImage];
//        cv::Mat closestLABPixel = [self nearestColorCIEDE2000:labColor inFrame:currentPerceptualImage];
        
        // convert to BGR
        cv::Mat bgr(1,1, CV_32FC3);
        cv::cvtColor(closestLABPixel, bgr, FROM_PERCEPTUAL);
        
        cv::Vec3f bgrColor = bgr.at<cv::Vec3f>(0,0);

        
        NSArray* color = @[@(bgrColor[2]), // / 255.0), // R
                           @(bgrColor[1]), // / 255.0), // G
                           @(bgrColor[0]), // / 255.0), // B
                           ];
        
        [dominantColors addObject:color];
        
        // We will process this in finalize
        [self.everyDominantColor addObject:color];
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
    
//    img3xN.convertTo(img3xN,CV_32F);
    
    
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
        cv::Vec3f labColor = centers.getMat(cv::ACCESS_READ).at<cv::Vec3f>(i, 0);
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
        
        [dominantColors addObject:color];
        
        // We will process this in finalize
        [self.everyDominantColor addObject:color];
    }
    
    metadata[@"DominantColors"] = dominantColors;
    
    return metadata;
}

#pragma mark - Histogram Calculation

//            // Quantize the hue to 30 levels
//            // and the saturation to 32 levels
//            int lbins = 256;
//            int abins = 256;
//            int bbins = 256;
//
//            int histSize[] = {lbins, abins};// bbins};
//
//            float range[] = { 0.0, 1.0 };
//            const float* ranges[] = { range, range};//, range };
//            
//            cv::MatND hist;
//            
//            // we compute the histogram from these channels
//            int channels[] = {0, 1};//, 2};
//            
//            calcHist( &quarterResLAB, // image
//                     1, // image count
//                     channels, // channel mapping
//                     cv::Mat(), // do not use mask
//                     hist,
//                     2, // dimensions
//                     histSize,
//                     ranges,
//                     true, // the histogram is uniform
//                     false );
//
//            double maxVal = 0;
//            
//            minMaxLoc(hist, 0, &maxVal, 0, 0);
//            
////            int scale = 10;
//            
//            cv::Mat histImg = cv::Mat::zeros(256, 256, CV_8UC3);
//            
//            for( int l = 0; l < 256; l++ )
//            {
//                for( int a = 0; a < 256; a++ )
//                {
////                    for( int b = 0; b < bbins; b++)
//                    {
//                        float binVal = hist.at<float>(l, a);
//                        
//                        int intensity = cvRound(binVal * 255.0 / maxVal);
//                        rectangle(histImg,
//                                  cv::Point(l, a),
//                                  cv::Point( (l+1), (a+1)),
//                                  
//                                  cv::Scalar::all(intensity),
//                                  //cv::Scalar::all(b*scale),
//                                  CV_FILLED );
//
//                    }
//                }
//               
//            }
//            cv::imshow("OpenCV Debug", histImg);
        
#pragma mark - Feature Detection

- (NSDictionary*) detectFeaturesCVMat:(matType)image
{
//    dispatch_async(dispatch_get_main_queue(), ^{
//        cv::imshow("OpenCV Debug", image);
//    });
 
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    std::vector<cv::KeyPoint> keypoints;
    detector->detect(image, keypoints, cv::noArray());
    
    NSMutableArray* keyPointsArray = [NSMutableArray new];
    
    for(std::vector<cv::KeyPoint>::iterator keyPoint = keypoints.begin(); keyPoint != keypoints.end(); keyPoint++)
    {
        CGPoint point = CGPointZero;
        {
            point = CGPointMake((float)keyPoint->pt.x / (float)image.size().width,
                                1.0f - (float)keyPoint->pt.y / (float)image.size().height);
        }
        
        [keyPointsArray addObject:@[ @(point.x), @(point.y)]];
    }
    
    // Add Features to metadata
    metadata[@"Features"] = keyPointsArray;
        
    return metadata;
}

#pragma mark - Frame Difference Motion

- (NSDictionary*) detectMotionInCVMat:(matType)image
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];

    
    // Can we do frame differencing - note all these tests should pass because we got it last time when the sample was current
    // otherwise it wouldnt be set as last.
    if(!lastImage.empty())
    {
        // Convert to greyscale
        matType currentGreyImage;
        matType lastGreyImage;
        cv::cvtColor(image, currentGreyImage, cv::COLOR_BGR2GRAY);
        cv::cvtColor(self->lastImage, lastGreyImage, cv::COLOR_BGR2GRAY);
        
        matType diff;
        cv::subtract(currentGreyImage, lastGreyImage, diff);
        
        // Average the difference:
        cv::Scalar avgMotion = cv::mean(diff);
        
        // Normalize to float
        metadata[@"Motion"] = @(avgMotion.val[0]);
    }
    
    // If we have our old last sample buffer, free it
//    if(!lastImage.empty())
//    {
//        lastImage.release();
//    }
//    
    // set a new one
    // TODO:: Asign? 
    image.copyTo(self->lastImage);

//    lastImage.addref();
    
    return metadata;
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    // analyzed
    
    // Also this code is heavilly borrowed so yea.
    int k = 5;
    int numPixels = (int)self.everyDominantColor.count;
    
    // Walk through the pixels and store colours.
    // Let's be fancy and make a smart pointer. Unfortunately shared_ptr doesn't automatically know how to delete a C++ array, so we have to write a [] lambda (aka 'block' in Obj-C) to clean up the object.
    std::shared_ptr<MedianCut::Point> points(new MedianCut::Point[numPixels],
                                             []( MedianCut::Point* p ) { delete[] p; } );
    
    int sourceColorCount = 0;
    
    // Populate Median Cut Points by color values;
    for(NSArray* dominantColorsArray in self.everyDominantColor)
    {
            points.get()[sourceColorCount].x[0] = [dominantColorsArray[0] floatValue];
            points.get()[sourceColorCount].x[1] = [dominantColorsArray[1] floatValue];
            points.get()[sourceColorCount].x[2] = [dominantColorsArray[2] floatValue];
            
            sourceColorCount++;
    }
    
    auto palette = MedianCut::medianCut(points.get(), numPixels, k);
    
    NSMutableArray* dominantColors = [NSMutableArray new];
    
    for ( auto colorCountPair: palette )
    {
        // convert from LAB to BGR
        const MedianCut::Point& labColor = colorCountPair.first;
        
        cv::Mat rgb(1,1, CV_32FC3, cv::Vec3f(labColor.x[0], labColor.x[1], labColor.x[2]));
        
        cv::Vec3f rgbColor = rgb.at<cv::Vec3f>(0,0);
        
        [dominantColors addObject: @[@(rgbColor[0]),
                                     @(rgbColor[1]),
                                     @(rgbColor[2]),
                                     ]];
    }
    
    // If we have our old last sample buffer, free it
    
    lastImage.release();
    
    return  @{@"DominantColors" : dominantColors};
}

@end
