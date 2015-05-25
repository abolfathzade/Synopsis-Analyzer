//
//  LogViewController.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 5/12/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "LogController.h"

@interface LogController ()
@property (strong) IBOutlet NSTextView* logTextField;
@property (atomic, readwrite, strong) NSDateFormatter* dateFormatter;
@property (atomic, readwrite, strong) NSDictionary* verboseStyle;
@property (atomic, readwrite, strong) NSDictionary* warningStyle;
@property (atomic, readwrite, strong) NSDictionary* errorStyle;
@property (atomic, readwrite, strong) NSDictionary* successStyle;

@property (atomic, readwrite, strong) NSAttributedString* staticVerboseString;
@property (atomic, readwrite, strong) NSAttributedString* staticWarningString;
@property (atomic, readwrite, strong) NSAttributedString* staticErrorString;
@property (atomic, readwrite, strong) NSAttributedString* staticSuccessString;
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
        
        self.staticVerboseString = [[NSAttributedString alloc] initWithString:@" [LOG] " attributes:self.verboseStyle];
        self.staticWarningString = [[NSAttributedString alloc] initWithString:@" [WARNING] " attributes:self.warningStyle];
        self.staticErrorString = [[NSAttributedString alloc] initWithString:@" [ERROR] " attributes:self.errorStyle];
        self.staticSuccessString = [[NSAttributedString alloc] initWithString:@" [SUCCESS] " attributes:self.successStyle];
        
        self.dateFormatter = [[NSDateFormatter alloc] init] ;
        
        //Set the required date format
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd hh:mm:ss : "];

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

- (NSMutableAttributedString*) logStringWithDate
{    
    //Get the string date
    return [[NSMutableAttributedString alloc] initWithString:[self.dateFormatter stringFromDate:[NSDate date] ] attributes:self.verboseStyle];
}

- (NSMutableAttributedString*) verboseString
{
    NSMutableAttributedString* string = [self logStringWithDate];
    [string appendAttributedString:self.staticVerboseString];
    return string;
}

- (NSMutableAttributedString*) warningString
{
    NSMutableAttributedString* string = [self logStringWithDate];
    [string appendAttributedString:self.staticWarningString];
    return string;
}

- (NSMutableAttributedString*) errorString
{
    NSMutableAttributedString* string = [self logStringWithDate];
    [string appendAttributedString:self.staticErrorString];
    return string;
}

- (NSMutableAttributedString*) successString
{
    NSMutableAttributedString* string = [self logStringWithDate];
    [string appendAttributedString:self.staticSuccessString];
    return string;
}

- (NSString*)appendLine:(NSString*)string
{
    unichar newLine = NSLineSeparatorCharacter;
    return [string stringByAppendingString:[NSString stringWithCharacters:&newLine length:1]];
}

- (void) appendVerboseLog:(NSString*)log
{
    NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
    NSMutableAttributedString* verboseString = [self verboseString];
    [verboseString appendAttributedString:logString];

    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.logTextField.textStorage appendAttributedString:verboseString];
    });
}

- (void) appendWarningLog:(NSString*)log
{
    // Always Log Warnings
    NSLog(@" [WARNING] %@", log);

    NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
    
    NSMutableAttributedString* warningString = [self warningString];
    [warningString appendAttributedString:logString];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logTextField.textStorage appendAttributedString:warningString];
    });

}

- (void) appendErrorLog:(NSString*)log
{
    // Always Log Errors
    NSLog(@" [ERROR] %@", log);
    
    NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
   
    NSMutableAttributedString* errorString = [self errorString];
    [errorString appendAttributedString:logString];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logTextField.textStorage appendAttributedString:errorString];
    });
  
}

- (void) appendSuccessLog:(NSString*)log
{
    NSAttributedString* logString = [[NSAttributedString alloc] initWithString:[self appendLine:log] attributes:self.verboseStyle];
    
    NSMutableAttributedString* successString = [self successString];
    [successString appendAttributedString:logString];

    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self.logTextField.textStorage appendAttributedString:successString];
    });

}


@end
