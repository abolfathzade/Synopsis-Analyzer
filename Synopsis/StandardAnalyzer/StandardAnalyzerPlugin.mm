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

#import "LogController.h"

#import "StandardAnalyzerDefines.h"

// Modules
#import "FrameCache.h"
#import "AverageColor.h"
#import "DominantColorModule.h"
#import "HistogramModule.h"
#import "MotionModule.h"
#import "PerceptualHashModule.h"

@interface StandardAnalyzerPlugin ()
{
}

#pragma mark - Plugin Protocol Requirements

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

#pragma mark - Analyzer Modules

@property (readwrite) BOOL hasModules;
@property (atomic, readwrite, strong) NSArray* moduleClasses;

@property (readwrite, strong) FrameCache* frameCache;

@property (readwrite, strong) AverageColor* averageColorModule;
@property (readwrite, strong) DominantColorModule* dominantColorModule;
@property (readwrite, strong) HistogramModule* histogramModule;
@property (readwrite, strong) MotionModule* motionModule;
@property (readwrite, strong) PerceptualHashModule* perceptualHashModule;

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
        
        self.moduleClasses  = @[NSStringFromClass([AverageColor class]),
                                NSStringFromClass([DominantColorModule class]),
                                NSStringFromClass([HistogramModule class]),
                                NSStringFromClass([MotionModule class]),
                                NSStringFromClass([PerceptualHashModule class]),
                              ];
        
        cv::setUseOptimized(true);
        [self setOpenCLEnabled:USE_OPENCL];
        
    }
    
    return self;
}

- (void) beginMetadataAnalysisSessionWithQuality:(SynopsisAnalysisQualityHint)qualityHint
{
//    dispatch_async(dispatch_get_main_queue(), ^{
//        cv::namedWindow("OpenCV Debug", CV_WINDOW_NORMAL);
//    });
    
    self.frameCache = [[FrameCache alloc] initWithQualityHint:qualityHint];
    
    self.averageColorModule = [[AverageColor alloc] initWithQualityHint:qualityHint];
    self.dominantColorModule = [[DominantColorModule alloc] initWithQualityHint:qualityHint];
    self.histogramModule = [[HistogramModule alloc] initWithQualityHint:qualityHint];
    self.perceptualHashModule = [[PerceptualHashModule alloc] initWithQualityHint:qualityHint];
    self.motionModule = [[MotionModule alloc] initWithQualityHint:qualityHint];
}

- (void) submitAndCacheCurrentVideoBuffer:(void*)baseAddress width:(size_t)width height:(size_t)height bytesPerRow:(size_t)bytesPerRow
{
    [self setOpenCLEnabled:USE_OPENCL];
    
    [self.frameCache cacheAndConvertBuffer:baseAddress width:width height:height bytesPerRow:bytesPerRow];
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
            result = [self.averageColorModule analyzedMetadataForFrame:self.frameCache.currentBGR_32FC3_Frame];
            break;
        }
        case 1:
        {
            result = [self.dominantColorModule analyzedMetadataForFrame:self.frameCache.currentPerceptual_32FC3_Frame];
            break;
        }
        case 2:
        {
            // Do we need this per frame?
            // Do we need this at all?
            // Does histogram similarity give us anything easily searchable?
            // Does histogram per frame give us anything to leverage for effects per frame?
            // Does a global accumulated histogram actually do anything for us at all
            
            result = [self.histogramModule analyzedMetadataForFrame:self.frameCache.currentBGR_8UC3I_Frame];
            break;
        }
        case 3:
        {
            result = [self.motionModule analyzedMetadataForFrame:self.frameCache.currentGray_8UC1_Frame lastFrame:self.frameCache.lastGray_8UC1_Frame];
            break;
        }
        case 4:
        {
            result = [self.perceptualHashModule analyzedMetadataForFrame:self.frameCache.currentGray_8UC1_Frame];
            break;
        }
            
        default:
            return nil;
    }
    
    return result;
}

#pragma mark - Finalization

- (NSDictionary*) finalizeMetadataAnalysisSessionWithError:(NSError**)error
{
    NSMutableDictionary* finalized = [NSMutableDictionary new];
    [finalized addEntriesFromDictionary:[self.dominantColorModule finaledAnalysisMetadata]];
    [finalized addEntriesFromDictionary:[self.perceptualHashModule finaledAnalysisMetadata]];
    [finalized addEntriesFromDictionary:[self.histogramModule finaledAnalysisMetadata]];
    [finalized addEntriesFromDictionary:[self.motionModule finaledAnalysisMetadata]];

    return finalized;
}



@end
