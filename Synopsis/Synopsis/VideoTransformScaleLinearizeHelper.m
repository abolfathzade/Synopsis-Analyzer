//
//  VideoTransformScaleLinearizeHelper.m
//  Synopsis
//
//  Created by vade on 6/13/17.
//  Copyright © 2017 metavisual. All rights reserved.
//

#import "VideoTransformScaleLinearizeHelper.h"
#import <CoreMedia/CoreMedia.h>
#import <Accelerate/Accelerate.h>
#import "VideoTransformScaleLinearizeHelperVImage.h"

#define SynopsisvImageTileFlag kvImageNoFlags
//#define SynopsisvImageTileFlag kvImageDoNotTile


@interface VideoTransformScaleLinearizeHelper ()
@property (readwrite, strong) VideoTransformScaleLinearizeHelperVImage* vImageHelper;
@end

@implementation VideoTransformScaleLinearizeHelper

- (id) init
{
    self = [super init];
    if(self)
    {
         self.vImageHelper = [[VideoTransformScaleLinearizeHelperVImage alloc] init];
    }
    
    return self;
}

- (void) dealloc
{
   
}

- (NSBlockOperation*) pixelBuffer:(CVPixelBufferRef)pixelBuffer
       withTransform:(CGAffineTransform)transform
                rect:(CGRect)rect
     completionBlock:(VideoTransformScaleLinearizeCompletionBlock)completionBlock
{
    return [self.vImageHelper pixelBuffer:pixelBuffer withTransform:transform rect:rect completionBlock:completionBlock];
}



@end
