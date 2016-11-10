//
//  Module.h
//  Synopsis
//
//  Created by vade on 11/10/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#import "opencv.hpp"
#import "ocl.hpp"
#import "types_c.h"
#import "utility.hpp"

#import "StandardAnalyzerDefines.h"
#import <Foundation/Foundation.h>
#import "AnalyzerPluginProtocol.h"

@interface Module : NSObject

- (instancetype) initWithQualityHint:(SynopsisAnalysisQualityHint)qualityHint NS_DESIGNATED_INITIALIZER;
- (NSString*) moduleName;
- (NSDictionary*) analyzedMetadataForFrame:(matType)frame;
- (NSDictionary*) finaledAnalysisMetadata;

@end
