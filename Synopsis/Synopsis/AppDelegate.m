//
//  AppDelegate.m
//  MetadataTranscoderTestHarness
//
//  Created by vade on 3/31/15.
//  Copyright (c) 2015 Synopsis. All rights reserved.
//

#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTVideoEncoderList.h>
#import <VideoToolbox/VTProfessionalVideoWorkflow.h>

#import "DropFilesView.h"
#import "LogController.h"
#import "AnalyzerPluginProtocol.h"

#import "AnalysisAndTranscodeOperation.h"
#import "MetadataWriterTranscodeOperation.h"

// Preferences Keys
const NSString* title = @"Title";
const NSString* value = @"Value";


@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet DropFilesView* dropFilesView;
@property (weak) IBOutlet NSVisualEffectView* effectView;

@property (atomic, readwrite, strong) NSOperationQueue* transcodeQueue;
@property (atomic, readwrite, strong) NSOperationQueue* metadataQueue;

@property (atomic, readwrite, strong) NSMutableArray* analyzerPlugins;
@property (atomic, readwrite, strong) NSMutableArray* analyzerPluginsInitializedForPrefs;
@property (weak) IBOutlet NSArrayController* prefsAnalyzerArrayController;

// Preferences
@property (weak) IBOutlet NSPopUpButton* prefsVideoCompressor;
@property (weak) IBOutlet NSPopUpButton* prefsVideoDimensions;
@property (weak) IBOutlet NSPopUpButton* prefsVideoQuality;
@property (weak) IBOutlet NSTextField* prefsVideoDimensionsCustomWidth;
@property (weak) IBOutlet NSTextField* prefsVideoDimensionsCustomHeight;
@property (weak) IBOutlet NSPopUpButton* prefsVideoAspectRatio;

// sent to kSynopsisTranscodeVideoSettingsKey
@property (atomic, readwrite, strong) NSDictionary* prefsVideoSettings;

@property (weak) IBOutlet NSPopUpButton* prefsAudioFormat;
@property (weak) IBOutlet NSPopUpButton* prefsAudioRate;
@property (weak) IBOutlet NSPopUpButton* prefsAudioQuality;
@property (weak) IBOutlet NSPopUpButton* prefsAudioBitrate;

// sent to kSynopsisTranscodeAudioSettingsKey
@property (atomic, readwrite, strong) NSDictionary* prefsAudioSettings;

@end

@implementation AppDelegate


//fix our giant memory leak which happened because we are probably holding on to Operations unecessarily now and not letting them go in our TableView's array of cached objects or some shit.


- (id) init
{
    self = [super init];
    if(self)
    {
        // Serial transcode queue
        self.transcodeQueue = [[NSOperationQueue alloc] init];
        self.transcodeQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount; //1, NSOperationQueueDefaultMaxConcurrentOperationCount
        
        // Serial metadata / passthrough writing queue
        self.metadataQueue = [[NSOperationQueue alloc] init];
        self.metadataQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount; //1, NSOperationQueueDefaultMaxConcurrentOperationCount
        
        self.analyzerPlugins = [NSMutableArray new];
        self.analyzerPluginsInitializedForPrefs = [NSMutableArray new];
    }
    return self;
}

- (void) awakeFromNib
{
    [self.effectView setState:NSVisualEffectStateActive];
    [self.window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
    [self.effectView setMaterial:NSVisualEffectMaterialDark];
    
    self.dropFilesView.dragDelegate = self;
    
    self.prefsAnalyzerArrayController.content = self.analyzerPluginsInitializedForPrefs;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    // Touch a ".synopsis" file to trick out embedded spotlight importer that there is a .synopsis file
    // We mirror OpenMeta's approach to allowing generic spotlight support via xattr's
    // But Yea
    [self initSpotlight];
    
    
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
                    // Weve sucessfully loaded our bundle, time to cache our class name so we can initialize a plugin per operation
                    // See (AnalysisAndTranscodeOperation
                    Class pluginClass = pluginBundle.principalClass;
                    NSString* classString = NSStringFromClass(pluginClass);
                    
                    if(classString)
                    {
                        [self.analyzerPlugins addObject:classString];
                        
                        [[LogController sharedLogController] appendSuccessLog:[NSString stringWithFormat:@"Loaded Plugin: %@", classString, nil]];
                        
                        [self.prefsAnalyzerArrayController addObject:[[pluginClass alloc] init]];
                        
                    }
                }
                else
                {
                    [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Error Loading Plugin : %@ : %@", [pluginsPath lastPathComponent], loadError, nil]];
                }
            }
            else
            {
                [[LogController sharedLogController] appendErrorLog:[NSString stringWithFormat:@"Error Preflighting Plugin : %@ : %@", [pluginsPath lastPathComponent], loadError, nil]];
            }
        }
    }
    
    [self initPrefs];
}

#pragma mark - Prefs

- (void) initSpotlight
{
    NSURL* spotlightFileURL = nil;
    NSURL* resourceURL = [[NSBundle mainBundle] resourceURL];
    
    spotlightFileURL = [resourceURL URLByAppendingPathComponent:@"spotlight.synopsis"];
    
    if([[NSFileManager defaultManager] fileExistsAtPath:[spotlightFileURL path]])
    {
        [[NSFileManager defaultManager] removeItemAtPath:[spotlightFileURL path] error:nil];
        
//        // touch the file, just to make sure
//        NSError* error = nil;
//        if(![[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate:[NSDate date]} ofItemAtPath:[spotlightFileURL path] error:&error])
//        {
//            NSLog(@"Error Initting Spotlight : %@", error);
//        }
    }
    
    {
        // See OpenMeta for details
        // Our spotlight trickery file will contain a set of keys we use

        // info_v002_synopsis_dominant_color_values = rgba
        NSDictionary* exampleValues = @{ @"info_v002_synopsis_dominant_color_values" : @[@0.0, @0.0, @0.0, @1.0], // Solid Black
                                         @"info_v002_synopsis_dominant_color_name" : @"Black",
                                         
                                         @"info_v002_synopsis_motion_vector_name" : @"Left",
                                         @"info_v002_synopsis_motion_vector_values" : @[@-1.0, @0.0]
                                        };
        
        [exampleValues writeToFile:[spotlightFileURL path] atomically:YES];
    }
}

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
        [encoderArrayWithTitles addObject:@{title:encoder[@"DisplayName"], value:encoder}];
    }
    
    //    NSDictionary* animationDictionary = @{ title : @"MPEG4 Video" , value: @{ @"CodecType" : [NSNumber numberWithInt:kCMVideoCodecType_MPEG4Video]}};
    //    [encoderArrayWithTitles addObject: animationDictionary];
    
    [self addMenuItemsToMenu:self.prefsVideoCompressor.menu withArray:encoderArrayWithTitles withSelector:@selector(selectVideoEncoder:)];
    
#pragma mark - Video Prefs Resolution
    
    NSMenuItem* nativeItem = [[NSMenuItem alloc] initWithTitle:@"Native Resolution" action:@selector(selectVideoResolution:) keyEquivalent:@""];
    [nativeItem setRepresentedObject:[NSValue valueWithSize:NSZeroSize] ];
    [self.prefsVideoDimensions.menu addItem:nativeItem];
    [self.prefsVideoDimensions.menu addItem:[NSMenuItem separatorItem]];
    
    NSArray* videoResolutions = @[
                                  @{title : @"640 x 480 (NTSC)", value : [NSValue valueWithSize:(NSSize){640.0, 480.0}] },
                                  @{title : @"768 x 576 (PAL)", value : [NSValue valueWithSize:(NSSize){786.0, 576.0}] },
                                  @{title : @"720 x 480 (480p)", value : [NSValue valueWithSize:(NSSize){720.0, 480.0}] },
                                  @{title : @"720 x 576 (576p)", value : [NSValue valueWithSize:(NSSize){720.0, 576.0}] },
                                  @{title : @"1280 x 720 (720p)", value : [NSValue valueWithSize:(NSSize){1280.0, 720.0}] },
                                  @{title : @"1920 x 1080 (1080p)", value : [NSValue valueWithSize:(NSSize){1920.0, 1080.0}] },
                                  @{title : @"2048 × 1080 (2k)", value : [NSValue valueWithSize:(NSSize){2048.0, 1080.0}] },
                                  @{title : @"2048 × 858 (2k Cinemascope)", value : [NSValue valueWithSize:(NSSize){2048.0, 858.0}] },
                                  @{title : @"3840 × 2160 (UHD)", value : [NSValue valueWithSize:(NSSize){3840.0, 2160.0}] },
                                  @{title : @"4096 × 2160 (4k)", value : [NSValue valueWithSize:(NSSize){4096.0, 2160.0}] },
                                  @{title : @"4096 × 1716 (4k Cinemascope)", value : [NSValue valueWithSize:(NSSize){4096.0, 1716.0}] },
                                  //@"Custom"
                                  ];
    
    [self addMenuItemsToMenu:self.prefsVideoDimensions.menu withArray:videoResolutions withSelector:@selector(selectVideoResolution:)];
    
    [self.prefsVideoDimensions.menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem* customItem = [[NSMenuItem alloc] initWithTitle:@"Custom" action:@selector(selectVideoEncoder:) keyEquivalent:@""];
    [customItem setRepresentedObject:[NSNull null]];
    [self.prefsVideoDimensions.menu addItem:customItem];
    
#pragma mark - Video Prefs Quality
    
    NSMenuItem* qualityItem = [[NSMenuItem alloc] initWithTitle:@"Not Applicable" action:@selector(selectVideoQuality:) keyEquivalent:@""];
    [qualityItem setRepresentedObject:[NSNull null]];
    [self.prefsVideoQuality.menu addItem:qualityItem];
    [self.prefsVideoQuality.menu addItem:[NSMenuItem separatorItem]];
    
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
                             @{title : @"Aspect Fill", value : AVVideoScalingModeResizeAspectFill},
                             @{title : @"Aspect Fit", value : AVVideoScalingModeResizeAspect},
                             @{title : @"Resize", value : AVVideoScalingModeResize},
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
    
    // If we are on passthrough encoder, then we disable all our options
    if(self.prefsVideoCompressor.selectedItem.representedObject == [NSNull null])
    {
        // disable other ui
        self.prefsVideoAspectRatio.enabled = NO;
        [self.prefsVideoAspectRatio selectItemAtIndex:0];
        
        self.prefsVideoDimensions.enabled = NO;
        [self.prefsVideoDimensions selectItemAtIndex:0];
        
        self.prefsVideoQuality.enabled = NO;
        [self.prefsVideoQuality selectItemAtIndex:0];
        
        self.prefsVideoDimensionsCustomHeight.enabled = NO;
        self.prefsVideoDimensionsCustomHeight.stringValue = @"";
        
        self.prefsVideoDimensionsCustomWidth.enabled = NO;
        self.prefsVideoDimensionsCustomWidth.stringValue = @"";
    }
    else
    {
        self.prefsVideoDimensions.enabled = YES;
        
        // If we are on JPEG, enable quality
        NSDictionary* codedInfo = self.prefsVideoCompressor.selectedItem.representedObject;
        if( [codedInfo[@"CodecName"] containsString:@"JPEG"])
        {
            self.prefsVideoQuality.enabled = YES;
            [self.prefsVideoQuality selectItemAtIndex:4];
        }
        else
        {
            self.prefsVideoQuality.enabled = NO;
            [self.prefsVideoQuality selectItemAtIndex:0];
        }
    }
    
    
    [self validateVideoPrefsUI];
    [self buildVideoPreferences];
}

- (IBAction)selectVideoResolution:(id)sender
{
    NSLog(@"selected Video Resolution: %@", [sender representedObject]);
    
    // If we are on the first (Native) resolution
    if (self.prefsVideoDimensions.indexOfSelectedItem == 0)
    {
        [self.prefsVideoAspectRatio selectItemAtIndex:0];
        // Enable 'Native'
        [[self.prefsVideoAspectRatio itemAtIndex:0] setEnabled:YES];
        self.prefsVideoAspectRatio.enabled = NO;
    }
    else
    {
        // Disable the native aspect ratio choice, and select aspect fill by default
        self.prefsVideoAspectRatio.enabled = YES;
        // Disable 'Native'
        [[self.prefsVideoAspectRatio itemAtIndex:0] setEnabled:NO];
        [self.prefsVideoAspectRatio selectItemAtIndex:2];
    }
    
    // if our video resolution is custom
    if(self.prefsVideoDimensions.selectedItem.representedObject == [NSNull null])
    {
        self.prefsVideoDimensionsCustomWidth.enabled = YES;
        self.prefsVideoDimensionsCustomHeight.enabled = YES;
    }
    else
    {
        // Update the custom size UI with the appropriate values
        NSSize selectedSize = [self.prefsVideoDimensions.selectedItem.representedObject sizeValue];
        self.prefsVideoDimensionsCustomWidth.floatValue = selectedSize.width;
        self.prefsVideoDimensionsCustomHeight.floatValue = selectedSize.height;
        
        self.prefsVideoDimensionsCustomWidth.enabled = NO;
        self.prefsVideoDimensionsCustomHeight.enabled = NO;
    }
    
    [self validateVideoPrefsUI];
    [self buildVideoPreferences];
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

#pragma mark - Video Prefs Validation

- (void) validateVideoPrefsUI
{
    
}

- (void) buildVideoPreferences
{
    NSMutableDictionary* videoSettingsDictonary = [NSMutableDictionary new];
    
    // get our fourcc from our compressor UI represented object and convert it to a string
    id compressorDict = self.prefsVideoCompressor.selectedItem.representedObject;
    
    // If we are passthrough, we set out video prefs to nil and bail early
    if(compressorDict == [NSNull null])
    {
        self.prefsVideoSettings = nil;
        return;
    }
    
    // Otherwise introspect our codec dictionary
    if([compressorDict isKindOfClass:[NSDictionary class]])
    {
        NSNumber* codecType = compressorDict[@"CodecType"];
        FourCharCode fourcc = (FourCharCode)[codecType intValue];
        NSString* fourCCString = NSFileTypeForHFSTypeCode(fourcc);
        
        // remove ' so "'jpeg'" becomes "jpeg" for example
        fourCCString = [fourCCString stringByReplacingOccurrencesOfString:@"'" withString:@""];
        
        videoSettingsDictonary[AVVideoCodecKey] = fourCCString;
    }
    // if we have a dimension, custom or other wise, get it
    id sizeValue = self.prefsVideoDimensions.selectedItem.representedObject;
    
    // Custom Size for NULL entry
    if(sizeValue == [NSNull null])
    {
        videoSettingsDictonary[AVVideoWidthKey] =  @(self.prefsVideoDimensionsCustomWidth.floatValue);
        videoSettingsDictonary[AVVideoHeightKey] =  @(self.prefsVideoDimensionsCustomHeight.floatValue);
        
        // If we have a non native size, we need the aspect key
        videoSettingsDictonary[AVVideoScalingModeKey] = self.prefsVideoAspectRatio.selectedItem.representedObject;
    }
    else if([sizeValue isKindOfClass:[NSValue class]])
    {
        NSSize videoSize = [self.prefsVideoDimensions.selectedItem.representedObject sizeValue];
        
        // Native size for NSZeroSize
        if(!NSEqualSizes(videoSize, NSZeroSize))
        {
            videoSettingsDictonary[AVVideoWidthKey] =  @(videoSize.width);
            videoSettingsDictonary[AVVideoHeightKey] =  @(videoSize.height);
            
            // If we have a non native size, we need the aspect key
            videoSettingsDictonary[AVVideoScalingModeKey] = self.prefsVideoAspectRatio.selectedItem.representedObject;
        }
    }
    
    // if we have a quality, get it,
    id qualityValue = self.prefsVideoQuality.selectedItem.representedObject;
    
    if(qualityValue != [NSNull null])
    {
        if([qualityValue isKindOfClass:[NSNumber class]])
        {
            NSDictionary* videoCompressionOptionsDictionary = @{AVVideoQualityKey : qualityValue};
            videoSettingsDictonary[AVVideoCompressionPropertiesKey] =  videoCompressionOptionsDictionary;
        }
    }
    
    self.prefsVideoSettings = [videoSettingsDictonary copy];
    
    NSLog(@"Calculated Video Settings : %@", self.prefsVideoSettings);
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

#pragma mark - Analyzer Prefs

- (void) buildAnalyzerPrefUI
{
    //    // Init an analyzer plugin and build a UI for it.
    //    for(id analyzer in self.analyzerPluginsInitializedForPrefs)
    //    {
    //
    //    }
}


#pragma mark -

- (IBAction)openMovies:(id)sender
{
    // Open a movie or two
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    
    [openPanel setAllowsMultipleSelection:YES];
    
    // TODO
    [openPanel setAllowedFileTypes:[AVMovie movieTypes]];
    //    [openPanel setAllowedFileTypes:@[@"mov", @"mp4", @"m4v"]];
    
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
    NSDictionary* transcodeOptions = @{kSynopsisTranscodeVideoSettingsKey : (self.prefsVideoSettings) ? self.prefsVideoSettings : [NSNull null],
                                       kSynopsisTranscodeAudioSettingsKey : [NSNull null],
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
                                    
                                    NSDictionary* metadataOptions = @{kSynopsisAnalyzedVideoSampleBufferMetadataKey : strongAnalysis.analyzedVideoSampleBufferMetadata,
                                                                      kSynopsisAnalyzedAudioSampleBufferMetadataKey : strongAnalysis.analyzedAudioSampleBufferMetadata,
                                                                      kSynopsisAnalyzedGlobalMetadataKey : strongAnalysis.analyzedGlobalMetadata
                                                                      };
                                    
                                    MetadataWriterTranscodeOperation* pass2 = [[MetadataWriterTranscodeOperation alloc] initWithSourceURL:destinationURL destinationURL:destinationURL2 metadataOptions:metadataOptions];
                                    
                                    pass2.completionBlock = (^(void)
                                                             {
                                                                 [[LogController sharedLogController] appendSuccessLog:@"Finished Transcode and Analysis"];
                                                             });
                                    
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [[NSNotificationCenter defaultCenter]  postNotificationName:kSynopsisNewTranscodeOperationAvailable object:pass2];
                                    });
                                    
                                    [self.metadataQueue addOperation:pass2];
                                    
                                });
    
    [[LogController sharedLogController] appendVerboseLog:@"Begin Transcode and Analysis"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]  postNotificationName:kSynopsisNewTranscodeOperationAvailable object:analysis];
    });
    
    
    [self.transcodeQueue addOperation:analysis];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

#pragma mark - Drop File Helper

- (void) handleDropedFiles:(NSArray *)fileURLArray
{
    for(NSURL* url in fileURLArray)
    {
        [self enqueueFileForTranscode:url];
    }
}


@end
