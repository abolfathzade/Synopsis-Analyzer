//
//  AppDelegate.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTVideoEncoderList.h>
#import <VideoToolbox/VTProfessionalVideoWorkflow.h>

#import "SampleBufferAnalyzerPluginProtocol.h"

#import "AnalysisAndTranscodeOperation.h"
#import "MetadataWriterTranscodeOperation.h"

// Preferences Keys
const NSString* title = @"Title";
const NSString* value = @"Value";


@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (atomic, readwrite, strong) NSOperationQueue* transcodeQueue;
@property (atomic, readwrite, strong) NSOperationQueue* metadataQueue;

@property (atomic, readwrite, strong) NSMutableArray* analyzerPlugins;

// Preferences
@property (weak) IBOutlet NSPopUpButton* prefsVideoCompressor;
@property (weak) IBOutlet NSPopUpButton* prefsVideoDimensions;
@property (weak) IBOutlet NSPopUpButton* prefsVideoQuality;
@property (weak) IBOutlet NSTextField* prefsVideoDimensionsCustomWidth;
@property (weak) IBOutlet NSTextField* prefsVideoDimensionsCustomHeight;
@property (weak) IBOutlet NSPopUpButton* prefsVideoAspectRatio;

// sent to kMetavisualTranscodeVideoSettingsKey
@property (atomic, readwrite, strong) NSDictionary* prefsVideoSettings;

@property (weak) IBOutlet NSPopUpButton* prefsAudioFormat;
@property (weak) IBOutlet NSPopUpButton* prefsAudioRate;
@property (weak) IBOutlet NSPopUpButton* prefsAudioQuality;
@property (weak) IBOutlet NSPopUpButton* prefsAudioBitrate;

// sent to kMetavisualTranscodeAudioSettingsKey
@property (atomic, readwrite, strong) NSDictionary* prefsAudioSettings;

@end

@implementation AppDelegate

- (id) init
{
    self = [super init];
    if(self)
    {
        // Serial transcode queue
        self.transcodeQueue = [[NSOperationQueue alloc] init];
        self.transcodeQueue.maxConcurrentOperationCount = 1;

        // Serial metadata / passthrough writing queue
        self.metadataQueue = [[NSOperationQueue alloc] init];
        self.metadataQueue.maxConcurrentOperationCount = 1;
        
        self.analyzerPlugins = [NSMutableArray new];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    // Load our plugins
    NSString* pluginsPath = [[NSBundle mainBundle] builtInPlugInsPath];
    
    NSError* error = nil;
    
    NSArray* possiblePlugins = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:pluginsPath error:&error];
    
    if(!error)
    {
        for(NSString* possiblePlugin in possiblePlugins)
        {
            NSBundle* pluginBundle = [NSBundle bundleWithPath:possiblePlugin];
            
            NSError* loadError = nil;
            if([pluginBundle preflightAndReturnError:&loadError])
            {
                if([pluginBundle loadAndReturnError:&loadError])
                {
                    // Weve sucessfully loaded our bundle, time to make a plugin instance
                    Class pluginClass = pluginBundle.principalClass;
                    
                    id<SampleBufferAnalyzerPluginProtocol> pluginInstance = [[pluginClass alloc] init];
                
                    if(pluginInstance)
                    {
                        [self.analyzerPlugins addObject:pluginInstance];
                        
                        NSLog(@"Loaded Plugin: %@", pluginInstance.pluginName);
                    }
                }
                else
                {
                    NSLog(@"Error Loading Plugin : %@ : %@", [pluginsPath lastPathComponent], loadError);
                }
            }
            else
            {
                NSLog(@"Error Preflighting Plugin : %@ : %@", [pluginsPath lastPathComponent], loadError);
            }
        }
    }
    
    [self initPrefs];
}

#pragma mark - Prefs

- (void) initPrefs
{
    [self initVideoPrefs];
    [self initAudioPrefs];
}

- (void) initVideoPrefs
{
    [self.prefsVideoCompressor removeAllItems];
    [self.prefsVideoDimensions removeAllItems];
    [self.prefsVideoQuality removeAllItems];
    [self.prefsVideoAspectRatio removeAllItems];
    
#pragma mark - Video Prefs Encoders

    VTRegisterProfessionalVideoWorkflowVideoDecoders();
    VTRegisterProfessionalVideoWorkflowVideoEncoders();
    
    // Passthrough :
    NSMenuItem* passthroughItem = [[NSMenuItem alloc] initWithTitle:@"Passthrough" action:@selector(selectVideoEncoder:) keyEquivalent:@""];
    [passthroughItem setRepresentedObject:[NSNull null]];
    [self.prefsVideoCompressor.menu addItem:passthroughItem];
    [self.prefsVideoCompressor.menu addItem:[NSMenuItem separatorItem]];
    
    // TODO: HAP / Hardware Accelerated HAP encoding
//    [self.prefsVideoCompressor addItemWithTitle:@"HAP"];
//    [self.prefsVideoCompressor addItemWithTitle:@"HAP Alpha"];
//    [self.prefsVideoCompressor addItemWithTitle:@"HAP Q"];

    // TODO:CMVideoCodecType / check what works as a value for AVVideoCodecKey
    CFArrayRef videoEncoders;
    VTCopyVideoEncoderList(NULL, &videoEncoders);
    NSArray* videoEncodersArray = (__bridge NSArray*)videoEncoders;
    
    NSMutableArray* encoderArrayWithTitles = [NSMutableArray arrayWithCapacity:videoEncodersArray.count];
    
    for(NSDictionary* encoder in videoEncodersArray)
    {
        [encoderArrayWithTitles addObject:@{title: encoder[@"DisplayName"], value:encoder}];
    }
    
    [self addMenuItemsToMenu:self.prefsVideoCompressor.menu withArray:encoderArrayWithTitles withSelector:@selector(selectVideoEncoder:)];

#pragma mark - Video Prefs Resolution

    NSArray* videoResolutions = @[//@"Native Resolution",
                                  @{title : @"Half",  value : [NSValue valueWithSize:(NSSize){0.5, 0.5}] },
                                  @{title : @"Quarter", value : [NSValue valueWithSize:(NSSize){0.25, 0.25}] },
                                  @{title : @"640 x 480 (NTSC)", value : [NSValue valueWithSize:(NSSize){640.0, 480.0}] },
                                  @{title : @"768 x 576 (PAL)", value : [NSValue valueWithSize:(NSSize){786.0, 576.0}] },
                                  @{title : @"720 x 480 (480p)", value : [NSValue valueWithSize:(NSSize){720.0, 480.0}] },
                                  @{title : @"720 x 576 (576p)", value : [NSValue valueWithSize:(NSSize){720.0, 576.0}] },
                                  @{title : @"1280 x 720 (720p)", value : [NSValue valueWithSize:(NSSize){1280.0, 720.0}] },
                                  @{title : @"1920 x 1080 (1080p)", value : [NSValue valueWithSize:(NSSize){720.0, 480.0}] },
                                  @{title : @"2048 × 1080 (2k)", value : [NSValue valueWithSize:(NSSize){2048.0, 1080.0}] },
                                  @{title : @"2048 × 858 (2k Cinemascope)", value : [NSValue valueWithSize:(NSSize){2048.0, 858.0}] },
                                  @{title : @"3840 × 2160 (UHD)", value : [NSValue valueWithSize:(NSSize){3840.0, 2160.0}] },
                                  @{title : @"4096 × 2160 (4k)", value : [NSValue valueWithSize:(NSSize){4096.0, 2160.0}] },
                                  @{title : @"4096 × 1716 (4k Cinemascope)", value : [NSValue valueWithSize:(NSSize){4096.0, 1716.0}] },
                                  //@"Custom"
                                  ];
    
    NSMenuItem* nativeItem = [[NSMenuItem alloc] initWithTitle:@"Native Resolution" action:@selector(selectVideoEncoder:) keyEquivalent:@""];
    [nativeItem setRepresentedObject:[NSValue valueWithSize:(NSSize){1.0, 1.0}] ];
    [self.prefsVideoDimensions.menu addItem:nativeItem];
    [self.prefsVideoDimensions.menu addItem:[NSMenuItem separatorItem]];

    [self addMenuItemsToMenu:self.prefsVideoDimensions.menu withArray:videoResolutions withSelector:@selector(selectVideoResolution:)];

    [self.prefsVideoDimensions.menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem* customItem = [[NSMenuItem alloc] initWithTitle:@"Custom" action:@selector(selectVideoEncoder:) keyEquivalent:@""];
    [customItem setRepresentedObject:[NSNull null]];
    [self.prefsVideoDimensions.menu addItem:customItem];
    
#pragma mark - Video Prefs Quality
    
    NSArray* qualityArray = @[
                              @{title : @"Minimum", value : @0.0} ,
                              @{title : @"Low", value : @0.25},
                              @{title : @"Normal", value : @0.5},
                              @{title : @"High", value : @0.75},
                              @{title : @"Maximum", value : @1.0}
                              ];

    [self addMenuItemsToMenu:self.prefsVideoQuality.menu withArray:qualityArray withSelector:@selector(selectVideoQuality:)];

#pragma mark - Video Prefs Aspect Ratio
    
    NSMenuItem* aspectItem = [[NSMenuItem alloc] initWithTitle:@"Native" action:@selector(selectVideoAspectRatio:) keyEquivalent:@""];
    [aspectItem setRepresentedObject:[NSNull null]];
    [self.prefsVideoAspectRatio.menu addItem:aspectItem];
    [self.prefsVideoAspectRatio.menu addItem:[NSMenuItem separatorItem]];

    // AVVideoScalingModeKey
    NSArray* aspectArray = @[
                              @{title : @"Resize", value : AVVideoScalingModeResize},
                              @{title : @"Aspect Resize", value : AVVideoScalingModeResizeAspect},
                              @{title : @"Aspect Fill", value : AVVideoScalingModeResizeAspectFill},
                              ];
    
    [self addMenuItemsToMenu:self.prefsVideoAspectRatio.menu withArray:aspectArray withSelector:@selector(selectVideoAspectRatio:)];
    
    [self validateVideoPrefsUI];
    [self buildVideoPreferences];
}

- (void) initAudioPrefs
{
    [self.prefsAudioFormat removeAllItems];
    [self.prefsAudioRate removeAllItems];
    [self.prefsAudioQuality removeAllItems];
    [self.prefsAudioBitrate removeAllItems];
    
#pragma mark - Audio Prefs Format

    NSArray* formatArray = @[
                           @{title : @"LinearPCM", value : @(kAudioFormatLinearPCM)} ,
                           @{title : @"Apple Lossless", value : @(kAudioFormatAppleLossless)},
                           @{title : @"AAC", value : @(kAudioFormatMPEG4AAC)},
                           @{title : @"MP3", value : @(kAudioFormatMPEGLayer3)},
                           ];
    
    [self addMenuItemsToMenu:self.prefsAudioFormat.menu withArray:formatArray withSelector:@selector(selectAudioFormat:)];

#pragma mark - Audio Prefs Rate
    
    NSMenuItem* recommendedItem = [[NSMenuItem alloc] initWithTitle:@"Recommended" action:@selector(selectAudioSamplerate:) keyEquivalent:@""];
    [recommendedItem setRepresentedObject:[NSNull null]];
    [self.prefsAudioRate.menu addItem:recommendedItem];
    [self.prefsAudioRate.menu addItem:[NSMenuItem separatorItem]];

    NSArray* rateArray = @[
//                              @{title : @"Recommended", value : [NSNull null]} ,
                              @{title : @"16.000 Khz", value : @16.000},
                              @{title : @"22.050 Khz", value : @22.050},
                              @{title : @"24.000 Khz", value : @24.000},
                              @{title : @"32.000 Khz", value : @32.000},
                              @{title : @"44.100 Khz", value : @44.100},
                              @{title : @"48.000 Khz", value : @48.000},
                              @{title : @"88.200 Khz", value : @88.200},
                              @{title : @"96.000 Khz", value : @96.0000},
                              ];

    [self addMenuItemsToMenu:self.prefsAudioRate.menu withArray:rateArray withSelector:@selector(selectAudioSamplerate:)];
    
#pragma mark - Audio Prefs Quality
    
    NSArray* qualityArray = @[
                              @{title : @"Minimum", value : @0.0} ,
                              @{title : @"Low", value : @0.25},
                              @{title : @"Normal", value : @0.5},
                              @{title : @"High", value : @0.75},
                              @{title : @"Maximum", value : @1.0}
                              ];

    [self addMenuItemsToMenu:self.prefsAudioQuality.menu withArray:qualityArray withSelector:@selector(selectAudioQuality:)];

#pragma mark - Audio Prefs Bitrate

    NSMenuItem* recommendedItem2 = [[NSMenuItem alloc] initWithTitle:@"Recommended" action:@selector(selectAudioBitrate:) keyEquivalent:@""];
    [recommendedItem2 setRepresentedObject:[NSNull null]];
    [self.prefsAudioBitrate.menu addItem:recommendedItem2];
    [self.prefsAudioBitrate.menu addItem:[NSMenuItem separatorItem]];

    NSArray* bitRateArray = @[
                           //@{title : @"Recommended", value : [NSNull null]} ,
                           @{title : @"24 Kbps", value : @24.0},
                           @{title : @"32 Kbps", value : @32},
                           @{title : @"48 Kbps", value : @38},
                           @{title : @"64 Kbps", value : @64},
                           @{title : @"80 Kbps", value : @80},
                           @{title : @"96 Kbps", value : @96},
                           @{title : @"112 Kbps", value : @112},
                           @{title : @"128 Kbps", value : @128},
                           @{title : @"160 Kbps", value : @160},
                           @{title : @"192 Kbps", value : @192},
                           @{title : @"224 Kbps", value : @224},
                           @{title : @"256 Kbps", value : @256},
                           @{title : @"320 Kbps", value : @320},
                           ];
    
    [self addMenuItemsToMenu:self.prefsAudioBitrate.menu withArray:bitRateArray withSelector:@selector(selectAudioBitrate:)];
}

#pragma mark - Prefs Helpers

- (void) addMenuItemsToMenu:(NSMenu*)aMenu withArray:(NSArray*)array withSelector:(SEL)selector
{
    for(NSDictionary* item in array)
    {
        NSMenuItem* menuItem = [[NSMenuItem alloc] initWithTitle:item[title] action:selector keyEquivalent:@""];
        [menuItem setRepresentedObject:item[value]];
        [aMenu addItem:menuItem];
    }
}

#pragma mark - Video Prefs Actions

- (IBAction)selectVideoEncoder:(id)sender
{
    NSLog(@"selected Video Encoder: %@", [sender representedObject]);
    
    [self validateVideoPrefsUI];
    [self buildVideoPreferences];
}

- (IBAction)selectVideoResolution:(id)sender
{
    NSLog(@"selected Video Resolution: %@", [sender representedObject]);
    
    [self validateVideoPrefsUI];
    [self buildVideoPreferences];

    // Did we get a custom size?
    if([sender representedObject] == [NSNull null])
    {
        self.prefsVideoDimensionsCustomWidth.enabled = YES;
        self.prefsVideoDimensionsCustomHeight.enabled = YES;
    }
    else
    {
        // Update the custom size UI with the appropriate values
        NSSize selectedSize = [[sender representedObject] sizeValue];
        self.prefsVideoDimensionsCustomWidth.floatValue = selectedSize.width;
        self.prefsVideoDimensionsCustomHeight.floatValue = selectedSize.height;
        
        self.prefsVideoDimensionsCustomWidth.enabled = NO;
        self.prefsVideoDimensionsCustomHeight.enabled = NO;
    }
}

- (IBAction)selectVideoQuality:(id)sender
{
    NSLog(@"selected Video Quality: %@", [sender representedObject]);

    [self validateVideoPrefsUI];
    [self buildVideoPreferences];
}

- (IBAction)selectVideoAspectRatio:(id)sender
{
    NSLog(@"selected Video Quality: %@", [sender representedObject]);

    [self validateVideoPrefsUI];
    [self buildVideoPreferences];
}

- (void) validateVideoPrefsUI
{
    // If we are on passthrough encoder, then we disable all our options
    if(self.prefsVideoCompressor.selectedItem.representedObject == [NSNull null])
    {
        // disable other ui
        self.prefsVideoAspectRatio.enabled = NO;
        self.prefsVideoDimensions.enabled = NO;
        self.prefsVideoQuality.enabled = NO;
        self.prefsVideoDimensionsCustomHeight.enabled = NO;
        self.prefsVideoDimensionsCustomWidth.enabled = NO;
    }
    // Enable everything, and let the following logic run:
    else
    {
        self.prefsVideoAspectRatio.enabled = YES;
        self.prefsVideoDimensions.enabled = YES;
        self.prefsVideoQuality.enabled = YES;
        self.prefsVideoDimensionsCustomHeight.enabled = YES;
        self.prefsVideoDimensionsCustomWidth.enabled = YES;
    
        // If we are on JPEG, enable quality
        NSDictionary* codedInfo = self.prefsVideoCompressor.selectedItem.representedObject;
        if( [codedInfo[@"CodecName"] containsString:@"JPEG"])
        {
            self.prefsVideoQuality.enabled = YES;
        }
        else
        {
            self.prefsVideoQuality.enabled = NO;
        }
    }
}

- (void) buildVideoPreferences
{
    
}

#pragma mark - Audio Prefs Actions


- (IBAction)selectAudioFormat:(id)sender
{
    NSLog(@"selected Audio Format: %@", [sender representedObject]);
}

- (IBAction)selectAudioSamplerate:(id)sender
{
    NSLog(@"selected Audio Sampleate: %@", [sender representedObject]);
}

- (IBAction)selectAudioQuality:(id)sender
{
    NSLog(@"selected Audio Quality: %@", [sender representedObject]);
}

- (IBAction)selectAudioBitrate:(id)sender
{
    NSLog(@"selected Audio Bitrate: %@", [sender representedObject]);
}


#pragma mark -

- (IBAction)openMovies:(id)sender
{
    // Open a movie or two
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    
    [openPanel setAllowsMultipleSelection:YES];
    [openPanel setAllowedFileTypes:@[@"mov", @"mp4", @"m4v"]];
    
    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result)
     {
         if (result == NSFileHandlingPanelOKButton)
         {
             for(NSURL* fileurl in openPanel.URLs)
             {
                 [self enqueueFileForTranscode:fileurl];
             }
         }
     }];
}
- (void) enqueueFileForTranscode:(NSURL*)fileURL
{
    NSString* lastPath = [fileURL lastPathComponent];
    NSString* lastPathExtention = [fileURL pathExtension];
    lastPath = [lastPath stringByAppendingString:@"_transcoded"];
    NSString* lastPath2 = [lastPath stringByAppendingString:@"_analyzed"];
    
    NSURL* destinationURL = [fileURL URLByDeletingLastPathComponent];
    destinationURL = [destinationURL URLByDeletingPathExtension];
    destinationURL = [[destinationURL URLByAppendingPathComponent:lastPath] URLByAppendingPathExtension:lastPathExtention];
    
    NSURL* destinationURL2 = [fileURL URLByDeletingLastPathComponent];
    destinationURL2 = [destinationURL2 URLByDeletingPathExtension];
    destinationURL2 = [[destinationURL2 URLByAppendingPathComponent:lastPath2] URLByAppendingPathExtension:lastPathExtention];
    
    // Pass 1 is our analysis pass, and our decode pass
    NSDictionary* transcodeOptions = @{kMetavisualTranscodeVideoSettingsKey : [NSNull null],
                                       kMetavisualTranscodeAudioSettingsKey : [NSNull null],
                                       };
    
    AnalysisAndTranscodeOperation* analysis = [[AnalysisAndTranscodeOperation alloc] initWithSourceURL:fileURL
                                                               destinationURL:destinationURL
                                                             transcodeOptions:transcodeOptions
                                                           availableAnalyzers:self.analyzerPlugins];
    
    // pass2 is depended on pass one being complete, and on pass1's analyzed metadata
    __weak AnalysisAndTranscodeOperation* weakAnalysis = analysis;
    
    analysis.completionBlock = (^(void)
    {
        // Retarded weak/strong pattern so we avoid retain loopl
        __strong AnalysisAndTranscodeOperation* strongAnalysis = weakAnalysis;
        
        NSDictionary* metadataOptions = @{kMetavisualAnalyzedVideoSampleBufferMetadataKey : strongAnalysis.analyzedVideoSampleBufferMetadata,
                                          kMetavisualAnalyzedAudioSampleBufferMetadataKey : strongAnalysis.analyzedAudioSampleBufferMetadata,
                                          kMetavisualAnalyzedGlobalMetadataKey : strongAnalysis.analyzedGlobalMetadata
                                          };

        MetadataWriterTranscodeOperation* pass2 = [[MetadataWriterTranscodeOperation alloc] initWithSourceURL:destinationURL destinationURL:destinationURL2 metadataOptions:metadataOptions];
        
        pass2.completionBlock = (^(void)
        {
            NSLog(@"Finished Transcode and Analysis");
        });
        
        [self.metadataQueue addOperation:pass2];

    });
    
    NSLog(@"Begin Transcode and Analysis");
          
          
    [self.transcodeQueue addOperation:analysis];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end
