//
//  VideoTransformScaleLinearizeHelper.h
//  Synopsis
//
//  Created by vade on 6/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Synopsis/Synopsis.h>
typedef void(^VideoTransformScaleLinearizeCompletionBlock)(SynopsisVideoFormatConverter*, NSError*);

@interface VideoTransformScaleLinearizeHelper : NSObject

- (NSBlockOperation*) pixelBuffer:(CVPixelBufferRef)pixelbuffer withTransform:(CGAffineTransform)transform rect:(CGRect)rect completionBlock:(VideoTransformScaleLinearizeCompletionBlock)completionBlock;

@end
