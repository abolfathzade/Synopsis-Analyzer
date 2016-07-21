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

#import "MedianCutOpenCV.hpp"
#import "CIEDE2000.h"

//#define TO_PERCEPTUAL cv::COLOR_BGR2HLS
//#define FROM_PERCEPTUAL cv::COLOR_HLS2BGR
//#define TO_PERCEPTUAL cv::COLOR_BGR2Luv
//#define FROM_PERCEPTUAL cv::COLOR_Luv2BGR
#define TO_PERCEPTUAL cv::COLOR_BGR2Lab
#define FROM_PERCEPTUAL cv::COLOR_Lab2BGR

#define USE_OPENCL 0
#define USE_CIEDE2000 0

#if USE_OPENCL
#define matType cv::UMat
#else
#define matType cv::Mat
#endif

@interface StandardAnalyzerPlugin ()
{
    matType currentBGR8UC3Image;
    matType currentBGR32FC3Image;
    matType currentPerceptualImage;
    matType currentGray8UC1Image;
    
    matType lastImage;
    cv::Ptr<cv::ORB> detector;
    
    matType accumulatedHist0;
    matType accumulatedHist1;
    matType accumulatedHist2;

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
                              @"Histogram",
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
    
    currentBGR32FC3Image.release();
    currentBGR8UC3Image.release();
    currentGray8UC1Image.release();
    
    currentPerceptualImage.release();
    lastImage.release();
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{
    dispatch_async(dispatch_get_main_queue(), ^{
        cv::namedWindow("OpenCV Debug", CV_WINDOW_NORMAL);
    });
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
    
    switch (moduleIndex)
    {
        case 0:
        {
            result = [self averageColorForCVMat:currentBGR32FC3Image];
            break;
        }
        case 1:
        {
            // Histogram technique is fundamentally flawed
            // result = [self dominantColorForCVHistogram:currentBGRImage];
            
            // KMeans is slow as hell
            //result = [self dominantColorForCVMatKMeans:currentPerceptualImage];

            result = [self dominantColorForCVMatMedianCutCV:currentPerceptualImage];

            break;
        }
        case 2:
        {
            result = [self detectFeaturesCVMat:currentGray8UC1Image];
            break;
        }
        case 3:
        {
            result = [self detectMotionInCVMatAVG:currentGray8UC1Image];
//            result = [self detectMotionInCVMatOpticalFlow:currentGray8UC1Image];
            break;
        }
        case 4:
        {
            result = [self detectHistogramInCVMat:currentBGR8UC3Image];
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

- (NSDictionary*) dominantColorForCVMatMedianCutCV:(matType)image
{
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // Also this code is heavilly borrowed so yea.
    int k = 5;
    
    bool useCIEDE2000 = USE_CIEDE2000;
    auto palette = MedianCutOpenCV::medianCut(image, k, useCIEDE2000);

    NSMutableArray* dominantColors = [NSMutableArray new];
    
    for ( auto colorCountPair: palette )
    {
        // convert from LAB to BGR
        const cv::Vec3f& labColor = colorCountPair.first;
        
//        cv::Mat closestLABPixel = cv::Mat(1,1, CV_32FC3, labColor);
        cv::Mat closestLABPixel = [self nearestColorMinMaxLoc:labColor inFrame:image];
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

- (NSDictionary*) dominantColorForCVHistogram:(matType)image
{
#define RANGE 256 // 1.0
#define RANGE_MULTIPLIER 1.0 // 256
#define NUMCLUSTERS 5
    // Our Mutable Metadata Dictionary:
    NSMutableDictionary* metadata = [NSMutableDictionary new];
    
    // Split image into channels
    std::vector<cv::Mat> imageChannels(3);
    cv::split(image, imageChannels);

    // SparseMat can't hold Zeros.
    // TODO: What happens when we try find a histogram on a pure black image?
    
//    cv::SparseMat Lhist, Ahist, Bhist;
    cv::Mat histMat0, histMat1, histMat2;
    
#if USE_OPENCL
    cv::Mat imageMat = image.getMat(cv::ACCESS_READ);
#else
    cv::Mat imageMat = image;
#endif
    
    int lbins = 256;
    int histSize[] = {lbins};//, abins, bbins};
    
    float range[] = { 0, RANGE };
    const float* ranges[] = { range } ;//, range, range };
    // we compute the histogram from these channels
    int channels[] = {0};//, 1, 2};

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
    
    /// Normalize the result to [ 0, histImage.rows ]
    normalize(histMat0, histMat0, 0.0, RANGE, cv::NORM_MINMAX, -1, cv::Mat() );
    normalize(histMat1, histMat1, 0.0, RANGE, cv::NORM_MINMAX, -1, cv::Mat() );
    normalize(histMat2, histMat2, 0.0, RANGE, cv::NORM_MINMAX, -1, cv::Mat() );

    // Merge to a single 3 channel hist
    std::vector<cv::Mat> histVec;
    histVec.push_back(histMat0);
    histVec.push_back(histMat1);
    histVec.push_back(histMat2);
    
    cv::Mat hist;
    cv::merge(histVec, hist);
    
    cv::Mat flipped;
    cv::flip(image, flipped, 0);
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        int hist_w = 256; int hist_h = 256;
        int bin_w = 1;//cvRound( (double) hist_w/lbins );
        
        cv::Mat histImage( hist_h, hist_w, CV_8UC3, cv::Scalar( 0,0,0) );

        for( int i = 1; i < lbins; i++ )
        {
            line( histImage,
                 cv::Point( bin_w*(i-1), hist_h - cvRound(histMat0.at<float>(i-1) * RANGE_MULTIPLIER ) ) ,
                 cv::Point( bin_w*(i), hist_h - cvRound(histMat0.at<float>(i) * RANGE_MULTIPLIER ) ),
                 cv::Scalar( 255, 0, 0), 2, cv::LineTypes::LINE_8, 0  );
            line( histImage,
                 cv::Point( bin_w*(i-1), hist_h - cvRound(histMat1.at<float>(i-1) * RANGE_MULTIPLIER ) ) ,
                 cv::Point( bin_w*(i), hist_h - cvRound(histMat1.at<float>(i) * RANGE_MULTIPLIER ) ),
                 cv::Scalar( 0, 255, 0), 2, cv::LineTypes::LINE_8, 0  );
            line( histImage,
                 cv::Point( bin_w*(i-1), hist_h - cvRound(histMat2.at<float>(i-1) * RANGE_MULTIPLIER ) ) ,
                 cv::Point( bin_w*(i), hist_h - cvRound(histMat2.at<float>(i) * RANGE_MULTIPLIER) ),
                 cv::Scalar( 0, 0, 255), 2, cv::LineTypes::LINE_8, 0  );
        }
        cv::imshow("Hist", histImage);
        
        cv::imshow("Image", flipped);
    });
    
    
    
    // Blur Histogram because I have no idea why not
//    matType blurredHist;
//    cv::GaussianBlur(hist, blurredHist,cv::Size(7,1), 0, 0);
    
//    matType resizedHist;
//    cv::resize(hist, resizedHist, cv::Size(5, 1), 0, 0, cv::INTER_AREA);
    
#if USE_OPENCL
    // Get a MAT from our UMat
//    cv::Mat histMAT =  hist;//blurredHist.getMat(cv::ACCESS_READ);
#else
    cv::Mat histMAT = hist;//blurredHist;
#endif
    
    // TODO: figure out what the fuck makes sense here.
    std::vector<int> labels0, labels1, labels2;
    cv::Mat centers0, centers1, centers2;
    double result = cv::kmeans(histMAT,
                               NUMCLUSTERS,
                               labels0,
                               //               cv::TermCriteria(),
                               cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 10000.0, 0.00001),
                               5,
                               cv::KMEANS_PP_CENTERS,
                               centers0);
    
//    // TODO: figure out what the fuck makes sense here.
//    std::vector<int> labels0, labels1, labels2;
//    cv::Mat centers0, centers1, centers2;
//    double result = cv::kmeans(histMat0,
//                               NUMCLUSTERS,
//                               labels0,
//                               //               cv::TermCriteria(),
//                               cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 10000.0, 0.00001),
//                               5,
//                               cv::KMEANS_PP_CENTERS,
//                               centers0);
//    
//     result = cv::kmeans(histMat1,
//                               NUMCLUSTERS,
//                               labels1,
//                               //               cv::TermCriteria(),
//                               cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 10000.0, 0.00001),
//                               5,
//                               cv::KMEANS_PP_CENTERS,
//                               centers1);
//    
//    result = cv::kmeans(histMat2,
//                        NUMCLUSTERS,
//                        labels2,
//                        //               cv::TermCriteria(),
//                        cv::TermCriteria(cv::TermCriteria::EPS + cv::TermCriteria::COUNT, 10000.0, 0.00001),
//                        5,
//                        cv::KMEANS_PP_CENTERS,
//                        centers2);
    
//    int max = 0, indx= 0, id = 0;
//    std::vector<int> clusters(NUMCLUSTERS,0);
//    
//    for (size_t i = 0; i < blabels.size(); i++)
//    {
//        id = blabels[i];
//        clusters[id]++;
//        
//        if (clusters[id] > max)
//        {
//            max = clusters[id];
//            indx = id;
//        }
//    }
//    
//    /* save largest cluster */
//    int cluster = indx;
    
    NSMutableArray* dominantColors = [NSMutableArray new];

    // We have a cluster label for each color now
    // To begin we average each cluster together
    // I think this should match our centroid but...
    
    std::vector<cv::Vec3f> clusterAverages(NUMCLUSTERS);
    
    for(int i = 0; i < labels0.size(); i++)
    {
        int index = labels0[i];
        
        cv::Vec3f color = histMAT.at<cv::Vec3f>(i);
        cv::Vec3f clusterColorAvg = clusterAverages[index];
        
        cv::add(clusterColorAvg,  color, clusterColorAvg);

        cv::multiply(clusterColorAvg, cv::Vec3f(0.5, 0.5, 0.5), clusterColorAvg);
        
        clusterAverages[index] = clusterColorAvg;
        
//        NSLog(@"Index: %i, color: %f %f %f", index, color[2], color[1], color[0]);

    }
    
    for(int i = 0; i < clusterAverages.size(); i++)
    {
        cv::Vec3f bgrColor = clusterAverages[i];
        
        NSArray* color = @[@(bgrColor[2] / 255.0), // / 255.0), // R
                           @(bgrColor[1] / 255.0), // / 255.0), // G
                           @(bgrColor[0] / 255.0), // / 255.0), // B
                           ];
        
        NSLog(@"Color: %@", color);
        
        [dominantColors addObject:color];
        
        // We will process this in finalize
        [self.everyDominantColor addObject:color];
    }
    
//    NSLog(@"New Frame");
//    for(int i = 0; i < centers0.rows; i++)
//    {
////#if USE_OPENCL
////        cv::Vec3f center = kCenters.getMat(cv::ACCESS_READ).at<cv::Vec3f>(i, 0);
////#else
////        float center0 = centers0.row(i).at<float>(0);
////        float center1 = centers1.row(i).at<float>(0);
////        float center2 = centers2.row(i).at<float>(0);
////#endif
////        double center = kCenters.row(1)
//
////        cv::Mat labRow = kCenters.row(i);
////        cv::Vec3f labVec = cv::Vec3f(labRow.at<float>(0, 0), labRow.at<float>(0,1), labRow.at<float>(0, 2));
//        
//        cv::Vec3f center = centers0.at<cv::Vec3f>(i, 0);
//        
//        NSLog(@"Center: %f %f %f", center[2] / RANGE, center[1] / RANGE, center[0] / RANGE);
//        
//        // find the location in our histogram that containsthe center
//        
////        cv::Mat lab(1,1, CV_32FC3);
////        lab.at<cv::Vec3f>(0, 0) = labVec;
////        
////        cv::Mat bgr(1,1, CV_32FC3);
////        
////        cv::cvtColor(lab, bgr, FROM_PERCEPTUAL);
////        
////        cv::Vec3f bgrColor = bgr.at<cv::Vec3f>(0,0);
//        
//        // Unsure why we have to subtract 1
//
//        NSArray* color = @[@(center[2] / RANGE), // R
//                           @(center[1] / RANGE), // G
//                           @(center[0] / RANGE), // B
//                           ];
//        
//        [dominantColors addObject:color];
//        
//        // We will process this in finalize
//        [self.everyDominantColor addObject:color];
//    }

    
//    for(int i = 0;  i < resizedHistMAT.rows; i++)
//    {
//        for(int j = 0; j < resizedHistMAT.cols; j++)
//        {
//            cv::Vec3f labColor = resizedHistMAT.at<cv::Vec3f>(i, j);
//
//            cv::Mat lab(1,1, CV_32FC3, cv::Vec3f(labColor[0], labColor[1] , labColor[2]));
//            
//            cv::Mat bgr(1,1, CV_32FC3);
//            
//            cv::cvtColor(lab, bgr, FROM_PERCEPTUAL);
//            
//            cv::Vec3f bgrColor = bgr.at<cv::Vec3f>(0,0);
//            
//            NSArray* color = @[@(bgrColor[2]), // / 255.0), // R
//                               @(bgrColor[1]), // / 255.0), // G
//                               @(bgrColor[0]), // / 255.0), // B
//                               ];
//            
//            [dominantColors addObject:color];
//            
//            // We will process this in finalize
//            [self.everyDominantColor addObject:color];
//        }
//    }
    
#if USE_OPENCL
    imageMat.release();
    resizedHistMAT.release();
#endif

    metadata[@"DominantColors"] = dominantColors;
    
        return metadata;
}

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
                                (float)keyPoint->pt.y / (float)image.size().height);
        }
        
        [keyPointsArray addObject:@[ @(point.x), @(point.y)]];
    }
    
//    cv::goodFeaturesToTrack(<#InputArray image#>, <#OutputArray corners#>, <#int maxCorners#>, <#double qualityLevel#>, <#double minDistance#>)
    
    // Add Features to metadata
    metadata[@"Features"] = keyPointsArray;
        
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
        metadata[@"Motion"] = @(avgMotion.val[0]);
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
    
#if USE_OPENCL
    cv::Mat imageMat = image.getMat(cv::ACCESS_READ);
#else
    cv::Mat imageMat = image;
#endif
    
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
    
    // Walk through the pixels and store colours.
    // Let's be fancy and make a smart pointer. Unfortunately shared_ptr doesn't automatically know how to delete a C++ array, so we have to write a [] lambda (aka 'block' in Obj-C) to clean up the object.
    std::shared_ptr<cv::Vec3f> points(new cv::Vec3f[numPixels],
                                             []( cv::Vec3f* p ) { delete[] p; } );
    
    int sourceColorCount = 0;
    
    // Populate Median Cut Points by color values;
    for(NSArray* dominantColorsArray in self.everyDominantColor)
    {
        points.get()[sourceColorCount][0] = [dominantColorsArray[0] floatValue];
        points.get()[sourceColorCount][1] = [dominantColorsArray[1] floatValue];
        points.get()[sourceColorCount][2] = [dominantColorsArray[2] floatValue];
        
        sourceColorCount++;
    }
    
    bool useCIEDE2000 = USE_CIEDE2000;
    MedianCutOpenCV::ColorCube allColorCube(points.get(), numPixels, useCIEDE2000);
    
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
    
    // If we have our old last sample buffer, free it
    
    lastImage.release();
    
    return  @{@"DominantColors" : dominantColors,
              @"Histogram" : histogramValues};
}

@end
