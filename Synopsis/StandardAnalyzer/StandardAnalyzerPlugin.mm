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
#import "types_c.h"
#import "features2d.hpp"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreGraphics/CoreGraphics.h>

#import "StandardAnalyzerPlugin.h"

#import "MedianCut.h"

@interface StandardAnalyzerPlugin ()
{
    CMSampleBufferRef lastSampleBuffer;
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

@property (atomic, readwrite, strong) NSArray* pluginModuleNames;

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
        
        self.pluginModuleNames  = @[@"Average Color",
                                    @"Dominant Colors",
                                    @"Features To Track",
                                    @"Motion",
                                    ];
        
        detector = cv::ORB::create(100);
        
        cv::namedWindow("OpenCV Debug");
        
        self.everyDominantColor = [NSMutableArray new];

    }
    
    return self;
}

- (void) dealloc
{
    detector.release();
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint andEnabledModules:(NSDictionary*)enabledModuleKeys
{
    
}

// NOTE YOU HAVE TO MANUALLY MANAGE LOCKING AND UNLOCKING YOURSELF - lifetime of the baseAddress is yours to manage
- (cv::Mat) cvPixelBufferToCVMat:(CVPixelBufferRef)pixelBuffer
{
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( pixelBuffer );
//    size_t width = CVPixelBufferGetWidth( pixelBuffer );
    size_t height = CVPixelBufferGetHeight( pixelBuffer );
    size_t stride = CVPixelBufferGetBytesPerRow( pixelBuffer );
    size_t extendedWidth = stride / sizeof( uint32_t ); // each pixel is 4 bytes/32 bits
    
    // Since the OpenCV Mat is wrapping the CVPixelBuffer's pixel data, we must do all of our modifications while its base address is locked.
    // If we want to operate on the buffer later, we'll have to do an expensive deep copy of the pixel data, using memcpy or Mat::clone().
    
    // Use extendedWidth instead of width to account for possible row extensions (sometimes used for memory alignment).
    // We only need to work on columms from [0, width - 1] regardless.
    
    cv::Mat bgraImage = cv::Mat( (int)height, (int)extendedWidth, CV_8UC4, base );
    
    return bgraImage;
}

- (NSDictionary*) analyzedMetadataDictionaryForSampleBuffer:(CMSampleBufferRef)sampleBuffer transform:(CGAffineTransform)transform error:(NSError**) error
{
//    return nil;
    
    if(sampleBuffer == NULL)
    {
        if (error != NULL)
        {
            *error = [[NSError alloc] initWithDomain:@"Synopsis.noSampleBuffer" code:-6666 userInfo:nil];
        }
        return nil;
    }
    else
    {
        // Our Mutable Metadata Dictionary:
        NSMutableDictionary* metadata = [NSMutableDictionary new];
        
        // Step 1, grab a CVImageBuffer from our CMSampleBuffer
        // This requires our sample buffer to be decoded, not passthrough.
        CVPixelBufferRef currentPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        if(currentPixelBuffer == NULL)
        {
            if (error != NULL)
            {
                *error = [[NSError alloc] initWithDomain:@"Synopsis.noPixelBufferInSampleBuffer" code:-666 userInfo:nil];
            }
            return nil;
        }
        else
        {
            CVPixelBufferLockBaseAddress( currentPixelBuffer, 0 );
            cv::Mat currentBGRAImage = [self cvPixelBufferToCVMat:currentPixelBuffer];
            
#pragma mark - Average Color

            // Half width/height image -
            // TODO: Maybe this becomes part of a quality preference?
            cv::Size quaterSize(currentBGRAImage.size().width * 0.2, currentBGRAImage.size().height * 0.2);
            
            cv::Mat quarterResBGRA(quaterSize, CV_8UC4);
            
            cv::resize(currentBGRAImage,
                       quarterResBGRA,
                       quaterSize,
                       0,
                       0,
                       cv::INTER_AREA); // INTER_AREA resize gives cleaner downsample results vs INTER_LINEAR.
            
            cv::Scalar avgPixelIntensity = cv::mean(quarterResBGRA);

            // Add to metadata - normalize to float
            metadata[@"AverageColor"] = @[@(avgPixelIntensity.val[2] / 255.0), // R
                                          @(avgPixelIntensity.val[1] / 255.0), // G
                                          @(avgPixelIntensity.val[0] / 255.0), // B
                                          ];
            
#pragma mark - Dominant Colors / Median Cut Method

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
            quarterResBGRA.convertTo(quarterResBGRAFloat, CV_32FC4, 1.0/255.0);
            
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
            
            //cv::goodFeaturesToTrack(InputArray image, <#OutputArray corners#>, <#int maxCorners#>, <#double qualityLevel#>, <#double minDistance#>)
            
            std::vector<cv::KeyPoint> keypoints;// = new std::vector<cv::KeyPoint>;
            detector->detect(currentBGRAImage, keypoints, cv::noArray());
            
            NSMutableArray* keyPointsArray = [NSMutableArray new];
            
            for(std::vector<cv::KeyPoint>::iterator keyPoint = keypoints.begin(); keyPoint != keypoints.end(); ++keyPoint)
            {
//                NSArray* point = nil;
                CGPoint point = CGPointZero;
                // Ensure our coordinate system is correct
                if(CVImageBufferIsFlipped(currentPixelBuffer))
                {
                    point = CGPointMake((float)keyPoint->pt.x / (float)currentBGRAImage.size().width,
                                        1.0f - (float)(keyPoint->pt.y / (float)currentBGRAImage.size().height));
                }
                else
                {
                    point = CGPointMake((float)keyPoint->pt.x / (float)currentBGRAImage.size().width,
                                        (float)keyPoint->pt.y / (float)currentBGRAImage.size().height);
                }
                
                // Normalize tx and ty from our transform since they are pixel sized transforms
                if(transform.tx)
                    transform.tx = (float)transform.tx/(float)currentBGRAImage.size().width;
                if(transform.ty)
                    transform.ty = (float)transform.ty/(float)currentBGRAImage.size().height;

////                point = CGPointApplyAffineTransform(point, CGAffineTransformMakeScale(1.0/currentBGRAImage.size().width, 1.0/currentBGRAImage.size().height));
                point = CGPointApplyAffineTransform(point, transform);
                
                [keyPointsArray addObject:@[ @(point.x), @(point.y)]];
            }
            
            // Add Features to metadata
            metadata[@"Features"] = keyPointsArray;

#pragma mark - Frame Difference Motion

            // Can we do frame differencing - note all these tests should pass because we got it last time when the sample was current
            // otherwise it wouldnt be set as last.
            if(lastSampleBuffer != NULL)
            {
                CVPixelBufferRef lastPixelBuffer = CMSampleBufferGetImageBuffer(lastSampleBuffer);
                if(lastPixelBuffer)
                {
                    CVPixelBufferRetain(lastPixelBuffer);

                    CVPixelBufferLockBaseAddress( lastPixelBuffer, 0 );
                    cv::Mat lastBGRAImage = [self cvPixelBufferToCVMat:lastPixelBuffer];
                    
                    // Convert to greyscale
                    cv::Mat currentGreyImage;
                    cv::Mat lastGreyImage;
                    cv::cvtColor(currentBGRAImage, currentGreyImage, cv::COLOR_BGRA2GRAY);
                    cv::cvtColor(lastBGRAImage, lastGreyImage, cv::COLOR_BGRA2GRAY);
                    
                    cv::Mat diff;
                    cv::subtract(currentGreyImage, lastGreyImage, diff);
                    
                    // Average the difference:
                    cv::Scalar avgMotion = cv::mean(diff);

                    // Normalize to float
                    metadata[@"Motion"] = @(avgMotion.val[0] / 255.0);
                    
                    CVPixelBufferUnlockBaseAddress(lastPixelBuffer, 0);
                    CVPixelBufferRelease(lastPixelBuffer);
                }
            }
            
#pragma mark -
            
            // Finished with our current pixel buffer, we have to unlock it.
            CVPixelBufferUnlockBaseAddress( currentPixelBuffer, 0 );
                              
            // If we have our old last sample buffer, free it
            if(lastSampleBuffer != NULL)
            {
                CFRelease(lastSampleBuffer);
                lastSampleBuffer = NULL;
            }
            
            // set a new one
            lastSampleBuffer = (CMSampleBufferRef)CFRetain(sampleBuffer);
        }
        
        return metadata;
    }
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
    if(lastSampleBuffer != NULL)
    {
        CFRelease(lastSampleBuffer);
        lastSampleBuffer = NULL;
    }
    
    return  @{@"DominantColors" : dominantColors};
}

@end
