//
//  VideoTransformScaleLinearizeHelperVImage.h
//  Synopsis Analyzer
//
//  Created by vade on 10/24/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "VideoTransformScaleLinearizeHelper.h"

@interface VideoTransformScaleLinearizeHelperVImage : NSObject

- (NSBlockOperation*) pixelBuffer:(CVPixelBufferRef)pixelbuffer withTransform:(CGAffineTransform)transform rect:(CGRect)rect completionBlock:(VideoTransformScaleLinearizeCompletionBlock)completionBlock;

@end
