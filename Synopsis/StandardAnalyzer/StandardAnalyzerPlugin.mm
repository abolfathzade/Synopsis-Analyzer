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

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>

#import "StandardAnalyzerPlugin.h"

#import "MedianCut.h"

@interface StandardAnalyzerPlugin ()
{
    cv::Mat lastImage;
    cv::Ptr<cv::ORB> detector;
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
        
        
        
        detector = cv::ORB::create(100);
        
        
        lastImage = NULL;
        
        self.everyDominantColor = [NSMutableArray new];

    }
    
    return self;
}

- (void) dealloc
{
    detector.release();
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint forModuleIndex:(SynopsisModuleIndex)moduleIndex
{
    // setup OpenCV to use OpenCL and a specific device
    if(cv::ocl::haveOpenCL())
    {
        cv::ocl::setUseOpenCL(true);
        
        //OpenCL: Platform Info
        std::vector<cv::ocl::PlatformInfo> platforms;
        cv::ocl::getPlatfomsInfo(platforms);
        
        //OpenCL Platforms
        for (size_t i = 0; i < platforms.size(); i++)
        {
            //Access to Platform
            const cv::ocl::PlatformInfo* platform = &platforms[i];
            
            //Platform Name
            std::cout << "Platform Name: " << platform->name().c_str() << "\n";
            
            //Access Device within Platform
            cv::ocl::Device current_device;
            for (int j = 0; j < platform->deviceNumber(); j++)
            {
                //Access Device
                platform->getDevice(current_device, j);
                
                //Device Type
                int deviceType = current_device.type();
                
                if(deviceType == cv::ocl::Device::TYPE_GPU)
                {
                    // set our device
                    cv::ocl::Device(current_device);
                    
                    break;
                }
                
            }
        }
    }
    cv::namedWindow("OpenCV Debug", CV_WINDOW_NORMAL);

    
}

- (cv::Mat) imageFromBaseAddress:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow
{
    size_t extendedWidth = bytesPerRow / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits

    cv::Mat bgraImage = cv::Mat((int)height, (int)extendedWidth, CV_8UC4, baseAddress);
    return bgraImage;
}


- (NSDictionary*) analyzedMetadataDictionaryForVideoBuffer:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow forModuleIndex:(SynopsisModuleIndex)moduleIndex error:(NSError**)error;
{
    if(baseAddress == NULL)
    {
        if (error != NULL)
        {
            *error = [[NSError alloc] initWithDomain:@"Synopsis.noSampleBuffer" code:-6666 userInfo:nil];
        }
        return nil;
    }
    else
    {
        cv::Mat currentBGRAImage = [self imageFromBaseAddress:baseAddress width:width height:height bytesPerRow:bytesPerRow];
        
        // Half width/height image -
        // TODO: Maybe this becomes part of a quality preference?
//        cv::Size quaterSize(currentBGRAImage.size().width * 0.2, currentBGRAImage.size().height * 0.2);
        
//        cv::Mat quarterResBGRA(quaterSize, CV_8UC4);
//        
//        cv::resize(currentBGRAImage,
//                   quarterResBGRA,
//                   quaterSize,
//                   0,
//                   0,
//                   cv::INTER_AREA); // INTER_AREA resize gives cleaner downsample results vs INTER_LINEAR.
        
        switch (moduleIndex)
        {
            case 0:
            {
                return [self averageColorForCVMat:currentBGRAImage];
            }
            case 1:
            {
                return [self dominantColorForCVMat:currentBGRAImage];
            }
            case 2:
            {
                return [self detectFeaturesCVMat:currentBGRAImage];
            }
            case 3:
            {
                return [self detectMotionInCVMat:currentBGRAImage];
            }
                
            default:
                return nil;
        }
    }
    
}

- (NSDictionary*) averageColorForCVMat:(cv::Mat)image
{
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    cv::Scalar avgPixelIntensity = cv::mean(image);
    
    // Add to metadata - normalize to float
    metadata[@"AverageColor"] = @[@(avgPixelIntensity.val[2] / 255.0), // R
                                  @(avgPixelIntensity.val[1] / 255.0), // G
                                  @(avgPixelIntensity.val[0] / 255.0), // B
                                  ];
    
    return metadata;
}

#pragma mark - Dominant Colors / Median Cut Method

- (NSDictionary*) dominantColorForCVMat:(cv::Mat)image
{

    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // This needs to be refactored - ideally we can median cut straight from a cv::Mat
    // But whatever, Kmeans is so goddamned slow anyway
    
    // Convert img BGRA to CIE_LAB or LCh - Float 32 for color calulation fidelity
    // Note floating point assumtions:
    // http://docs.opencv.org/2.4.11/modules/imgproc/doc/miscellaneous_transformations.html
    // The conventional ranges for R, G, and B channel values are:
    // 0 to 255 for CV_8U images
    // 0 to 65535 for CV_16U images
    // 0 to 1 for CV_32F images
    
    // Convert to Float for maximum color fidelity
    cv::Mat quarterResBGRAFloat;
    
    image.copyTo(quarterResBGRAFloat);
    
    quarterResBGRAFloat.convertTo(quarterResBGRAFloat, CV_32FC4, 1.0/255.0);
    
    cv::Mat quarterResBGR(quarterResBGRAFloat.size(), CV_32FC3);
    cv::Mat quarterResLAB(quarterResBGRAFloat.size(), CV_32FC3);
    
    cv::cvtColor(quarterResBGRAFloat, quarterResBGR, cv::COLOR_BGRA2BGR);
    cv::cvtColor(quarterResBGR, quarterResLAB, cv::COLOR_BGR2Lab);
    
    // Also this code is heavilly borrowed so yea.
    int k = 5;
    int numPixels = quarterResLAB.rows * quarterResLAB.cols;
    
    // Walk through the pixels and store colours.
    // Let's be fancy and make a smart pointer. Unfortunately shared_ptr doesn't automatically know how to delete a C++ array, so we have to write a [] lambda (aka 'block' in Obj-C) to clean up the object.
    std::shared_ptr<MedianCut::Point> points(new MedianCut::Point[numPixels],
                                             []( MedianCut::Point* p ) { delete[] p; } );
    
    int sourceColorCount = 0;
    
    // Populate Median Cut Points by color values;
    for(int i = 0;  i < quarterResLAB.rows; i++)
    {
        for(int j = 0; j < quarterResLAB.cols; j++)
        {
            // You can now access the pixel value with cv::Vec3 (or 4 for if BGRA)
            cv::Vec3f labColor = quarterResLAB.at<cv::Vec3f>(i, j);
            
            //                    NSLog(@"Color: %f %f %f", labColor[0], labColor[1], labColor[2]);
            
            points.get()[sourceColorCount].x[0] = labColor[0]; // B L
            points.get()[sourceColorCount].x[1] = labColor[1]; // G A
            points.get()[sourceColorCount].x[2] = labColor[2]; // R B
            
            sourceColorCount++;
        }
    }
    
    auto palette = MedianCut::medianCut(points.get(), numPixels, k);
    
    NSMutableArray* dominantColors = [NSMutableArray new];
    
    for ( auto colorCountPair: palette )
    {
        // convert from LAB to BGR
        const MedianCut::Point& labColor = colorCountPair.first;
        
        cv::Mat lab(1,1, CV_32FC3, cv::Vec3f(labColor.x[0], labColor.x[1], labColor.x[2]));
        
        cv::Mat bgr(1,1, CV_32FC3);
        
        cv::cvtColor(lab, bgr, cv::COLOR_Lab2BGR);
        
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
    
#pragma mark - Dominant Colors / kMeans
//
//            // We choose k = 5 to match Adobe Kuler because whatever.
//            int k = 5;
//            int n = quarterResBGRA.rows * quarterResBGRA.cols;
//
//            // Convert to Float for maximum color fidelity
//            cv::Mat quarterResBGRAFloat;
//            quarterResBGRA.convertTo(quarterResBGRAFloat, CV_32FC4, 1.0/255.0);
//            
//            cv::Mat quarterResBGR(quarterResBGRAFloat.size(), CV_32FC3);
//            cv::Mat quarterResLAB(quarterResBGRAFloat.size(), CV_32FC3);
//            
//            cv::cvtColor(quarterResBGRAFloat, quarterResBGR, cv::COLOR_BGRA2BGR);
//            cv::cvtColor(quarterResBGR, quarterResLAB, cv::COLOR_BGR2Lab);
//            
//            std::vector<cv::Mat> imgSplit;
//            cv::split(quarterResBGRAFloat,imgSplit);
//            
//            cv::Mat img3xN(n,3,CV_32F);
//            
//            for(int i = 0; i != 3; ++i)
//            {
//                imgSplit[i].reshape(1,n).copyTo(img3xN.col(i));
//            }
//            
//            img3xN.convertTo(img3xN,CV_32F);
//            
//            cv::Mat bestLables;
//            cv::Mat centers;
//            
//            // TODO: figure out what the fuck makes sense here.
//            cv::kmeans(img3xN,
//                       k,
//                       bestLables,
//                       cv::TermCriteria(),
////                       cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 5.0, 1.0),
//                       1,
//                       cv::KMEANS_PP_CENTERS,
//                       centers);
//            
//            NSMutableArray* dominantColors = [NSMutableArray new];
//            
////            cv::imshow("OpenCV Debug", quarterResLAB);
//
//            for(int i = 0; i < centers.rows; i++)
//            {
//                // 0 1 or 0 - 255 .0 ?
//                cv::Vec3f labColor = centers.at<cv::Vec3f>(i, 0);
//                
//                cv::Mat lab(1,1, CV_32FC3, cv::Vec3f(labColor[0], labColor[1], labColor[2]));
//                
//                cv::Mat bgr(1,1, CV_32FC3);
//                
//                cv::cvtColor(lab, bgr, cv::COLOR_Lab2BGR);
//                
//                cv::Vec3f bgrColor = bgr.at<cv::Vec3f>(0,0);
//                
//                [dominantColors addObject: @[@(bgrColor[2]), // / 255.0), // R
//                                             @(bgrColor[1]), // / 255.0), // G
//                                             @(bgrColor[0]), // / 255.0), // B
//                                             ]];
//                
////                [dominantColors addObject: @[@(colorBGR.val[2] / 255.0), // R
////                                             @(colorBGR.val[1] / 255.0), // G
////                                             @(colorBGR.val[0] / 255.0), // B
////                                            ]];
//            }
//            
//            metadata[@"DominantColors"] = dominantColors;
        
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

- (NSDictionary*) detectFeaturesCVMat:(cv::Mat)image
{
    dispatch_async(dispatch_get_main_queue(), ^{
        cv::imshow("OpenCV Debug", image);
    });
 
    
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    std::vector<cv::KeyPoint> keypoints;
    detector->detect(image, keypoints, cv::noArray());
    
    NSMutableArray* keyPointsArray = [NSMutableArray new];
    
    for(std::vector<cv::KeyPoint>::iterator keyPoint = keypoints.begin(); keyPoint != keypoints.end(); ++keyPoint)
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

- (NSDictionary*) detectMotionInCVMat:(cv::Mat)image
{
    NSMutableDictionary* metadata = [NSMutableDictionary new];

    
    // Can we do frame differencing - note all these tests should pass because we got it last time when the sample was current
    // otherwise it wouldnt be set as last.
    if(!lastImage.empty())
    {
        
        // Convert to greyscale
        cv::Mat currentGreyImage;
        cv::Mat lastGreyImage;
        cv::cvtColor(image, currentGreyImage, cv::COLOR_BGRA2GRAY);
        cv::cvtColor(self->lastImage, lastGreyImage, cv::COLOR_BGRA2GRAY);
        
        cv::Mat diff;
        cv::subtract(currentGreyImage, lastGreyImage, diff);
        
        // Average the difference:
        cv::Scalar avgMotion = cv::mean(diff);
        
        // Normalize to float
        metadata[@"Motion"] = @(avgMotion.val[0] / 255.0);
    }
    
    
    // If we have our old last sample buffer, free it
    if(!lastImage.empty())
    {
        lastImage.release();
    }
    
    // set a new one
    image.copyTo(self->lastImage);
    
    return metadata;
}

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    // analyzed
    
    // Also this code is heavilly borrowed so yea.
    int k = 5;
    int numPixels = self.everyDominantColor.count;
    
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
