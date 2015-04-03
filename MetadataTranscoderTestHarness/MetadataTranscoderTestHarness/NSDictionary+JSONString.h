//
//  NSDictionary+JSONString.h
//  MetadataTranscoderTestHarness
//
//  Created by vade on 4/3/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDictionary (JSONString)
-(NSString*) jsonStringWithPrettyPrint:(BOOL) prettyPrint;
@end
