//
//  LogViewController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/12/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "LogController.h"

@interface LogController ()
@property (strong) IBOutlet NSTextView* logTextField;
@property (atomic, readwrite, strong) NSDateFormatter* dateFormatter;
@property (atomic, readwrite, strong) NSDictionary* verboseStyle;
@property (atomic, readwrite, strong) NSDictionary* warningStyle;
@property (atomic, readwrite, strong) NSDictionary* errorStyle;
@property (atomic, readwrite, strong) NSDictionary* successStyle;
@end

@implementation LogController

+ (LogController*) sharedLogController
{
    static LogController* sharedLogController = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedLogController = [[self allocActually] initActually];
    });
    
    return sharedLogController;
}

+ (id)allocActually
{
    return [super allocWithZone:NULL];
}

+ (id)alloc
{
    return [self sharedLogController];
}

+ (id)allocWithZone:(NSZone *)zone
{
    return [self sharedLogController];
}

- (id)initActually
{
    self = [super init];
    if (self)
    {
        self.verboseStyle = @{ NSForegroundColorAttributeName : [NSColor darkGrayColor]};
        self.warningStyle = @{ NSForegroundColorAttributeName : [NSColor orangeColor]};
        self.errorStyle = @{ NSForegroundColorAttributeName : [NSColor redColor]};
        self.successStyle = @{ NSForegroundColorAttributeName : [NSColor colorWithRed:0 green:0.66 blue:0 alpha:1]};
        
        self.dateFormatter = [[NSDateFormatter alloc] init] ;
        
        //Set the required date format
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:MM:SS"];

    }
    return self;
}

- (id)init
{
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    return self;
}

- (NSString*) logStringWithDate
{    
    //Get the string date
    return [self.dateFormatter stringFromDate:[NSDate date]];
}

- (NSString*) verboseString
{
    return [[self logStringWithDate] stringByAppendingString:@" [LOG] "];
}

- (NSString*) warningString
{
    return [[self logStringWithDate] stringByAppendingString:@" [WARNING] "];
}

- (NSString*) errorString
{
    return [[self logStringWithDate] stringByAppendingString:@" [ERROR] "];
}

- (NSString*) successString
{
    return [[self logStringWithDate] stringByAppendingString:@" [SUCCESS] "];
}

- (NSString*)appendLine:(NSString*)string
{
    unichar newLine = NSLineSeparatorCharacter;
    return [string stringByAppendingString:[NSString stringWithCharacters:&newLine length:1]];
}

- (void) appendVerboseLog:(NSString*)log
{
    dispatch_async(dispatch_get_main_queue(), ^ {
        NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
        NSMutableAttributedString* verboseString = [[NSMutableAttributedString alloc] initWithString:[self verboseString] attributes:self.verboseStyle];
        
        [verboseString appendAttributedString:logString];
        
        [self.logTextField.textStorage appendAttributedString:verboseString];
    });
}

- (void) appendWarningLog:(NSString*)log
{
    dispatch_async(dispatch_get_main_queue(), ^{
       
        NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
        NSMutableAttributedString* warningString = [[NSMutableAttributedString alloc] initWithString:[self warningString] attributes:self.warningStyle];
        [warningString appendAttributedString:logString];
        
        [self.logTextField.textStorage appendAttributedString:warningString];
    });

}

- (void) appendErrorLog:(NSString*)log
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
        NSMutableAttributedString* errorString = [[NSMutableAttributedString alloc] initWithString:[self errorString] attributes:self.errorStyle];
        [errorString appendAttributedString:logString];
        
        [self.logTextField.textStorage appendAttributedString:errorString];
    });
  
}

- (void) appendSuccessLog:(NSString*)log
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
        NSMutableAttributedString* successString = [[NSMutableAttributedString alloc] initWithString:[self successString] attributes:self.successStyle];
        
        [successString appendAttributedString:logString];
        
        [self.logTextField.textStorage appendAttributedString:successString];
    });

}


@end
