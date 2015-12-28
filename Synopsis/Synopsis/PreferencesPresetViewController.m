//
//  PreferencesPresetViewController.m
//  Synopsis
//
//  Created by vade on 12/26/15.
//  Copyright (c) 2015 metavisual. All rights reserved.
//

#import "PreferencesPresetViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTVideoEncoderList.h>
#import <VideoToolbox/VTProfessionalVideoWorkflow.h>

#import "PresetGroup.h"

// Preferences Keys
const NSString* title = @"Title";
const NSString* value = @"Value";


@interface PreferencesPresetViewController ()  <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (weak) IBOutlet NSBox* presetInfoContainerBox;

@property (weak) IBOutlet NSOutlineView* presetOutlineView;

@property (weak) IBOutlet NSView* overviewContainerView;
@property (weak) IBOutlet NSTextField* overviewTitleTextField;
@property (weak) IBOutlet NSTextField* overviewDescriptionTextField;

// Preferences Video
@property (weak) IBOutlet NSView* videoContainerView;
@property (weak) IBOutlet NSButton* useVideoCheckButton;
@property (weak) IBOutlet NSPopUpButton* prefsVideoCompressor;
@property (weak) IBOutlet NSPopUpButton* prefsVideoDimensions;
@property (weak) IBOutlet NSPopUpButton* prefsVideoQuality;
@property (weak) IBOutlet NSTextField* prefsVideoDimensionsCustomWidth;
@property (weak) IBOutlet NSTextField* prefsVideoDimensionsCustomHeight;
@property (weak) IBOutlet NSPopUpButton* prefsVideoAspectRatio;
@property (atomic, readwrite, strong) NSDictionary* prefsVideoSettings; // sent to kSynopsisTranscodeVideoSettingsKey

// Preferences Audio
@property (weak) IBOutlet NSView* audioContainerView;
@property (weak) IBOutlet NSButton* useAudioCheckButton;
@property (weak) IBOutlet NSPopUpButton* prefsAudioFormat;
@property (weak) IBOutlet NSPopUpButton* prefsAudioRate;
@property (weak) IBOutlet NSPopUpButton* prefsAudioQuality;
@property (weak) IBOutlet NSPopUpButton* prefsAudioBitrate;
@property (atomic, readwrite, strong) NSDictionary* prefsAudioSettings; // sent to kSynopsisTranscodeAudioSettingsKey

// Preferences Analysis
@property (weak) IBOutlet NSView* analysisContainerView;
@property (weak) IBOutlet NSButton* useAnalysisCheckButton;


// Outline View Data source
@property (atomic, readwrite, strong) PresetGroup* standardPresets;
@property (atomic, readwrite, strong) PresetGroup* customPresets;

@property (atomic, readwrite, strong) PresetObject* selectedPreset;

@end

@implementation PreferencesPresetViewController

- (id) initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if(self)
    {
        self.selectedPreset = nil;
        self.standardPresets = [[PresetGroup alloc] initWithTitle:@"Standard Presets"];
        self.customPresets = [[PresetGroup alloc] initWithTitle:@"Custom Presets"];
        
        // set up some basic presets
        PresetObject* passthrough = [[PresetObject alloc] initWithTitle:@"Passthrough" audioSettings:nil videoSettings:nil analyzerSettings:nil useAudio:YES useVideo:YES useAnalysis:YES];
        
        PresetObject* passthroughVideoOnly = [[PresetObject alloc] initWithTitle:@"Passthrough Video" audioSettings:nil videoSettings:nil analyzerSettings:nil useAudio:NO useVideo:YES useAnalysis:YES];
        
        PresetObject* appleIntermediateLinearPCM = [[PresetObject alloc] initWithTitle:@"Apple Intermediate Only"
                                                                         audioSettings:nil
                                                                         videoSettings:@{AVVideoCodecKey:@"icod"}
                                                                      analyzerSettings:nil
                                                                              useAudio:NO
                                                                              useVideo:YES
                                                                           useAnalysis:YES];
        
        PresetGroup* passthroughGroup = [[PresetGroup alloc] initWithTitle:@"Passthrough"];
        passthroughGroup.children = @[passthrough, passthroughVideoOnly];
        
        self.standardPresets.children = @[passthroughGroup, appleIntermediateLinearPCM];

        return self;
    }
    
    return nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.presetOutlineView.dataSource = self;
    self.presetOutlineView.delegate = self;

    [self initPrefs];
}

#pragma mark -

- (void) initPrefs
{
    [self initVideoPrefs];
    [self initAudioPrefs];
    
    // update UI / hack since we dont have validator code yet
    [self selectVideoEncoder:self.prefsVideoCompressor.selectedItem];
    [self selectAudioFormat:self.prefsAudioFormat.selectedItem];
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
    
    NSMenuItem* passthroughItem = [[NSMenuItem alloc] initWithTitle:@"Passthrough" action:@selector(selectAudioFormat:) keyEquivalent:@""];
    [passthroughItem setRepresentedObject:[NSNull null]];
    [self.prefsAudioFormat.menu addItem:passthroughItem];
    [self.prefsAudioFormat.menu addItem:[NSMenuItem separatorItem]];
    
    NSArray* formatArray = @[
                             @{title : @"LinearPCM", value : @(kAudioFormatLinearPCM)} ,
                             @{title : @"Apple Lossless", value : @(kAudioFormatAppleLossless)},
                             @{title : @"AAC", value : @(kAudioFormatMPEG4AAC)},
                             //                             @{title : @"MP3", value : @(kAudioFormatMPEGLayer3)},
                             ];
    
    [self addMenuItemsToMenu:self.prefsAudioFormat.menu withArray:formatArray withSelector:@selector(selectAudioFormat:)];
    
#pragma mark - Audio Prefs Rate
    
    NSMenuItem* recommendedItem = [[NSMenuItem alloc] initWithTitle:@"Recommended" action:@selector(selectAudioSamplerate:) keyEquivalent:@""];
    [recommendedItem setRepresentedObject:[NSNull null]];
    [self.prefsAudioRate.menu addItem:recommendedItem];
    [self.prefsAudioRate.menu addItem:[NSMenuItem separatorItem]];
    
    NSArray* rateArray = @[
                           //                              @{title : @"Recommended", value : [NSNull null]} ,
                           @{title : @"16.000 Khz", value : @(16000.0)},
                           @{title : @"22.050 Khz", value : @(22050.0)},
                           @{title : @"24.000 Khz", value : @(24000.0)},
                           @{title : @"32.000 Khz", value : @(32000.0)},
                           @{title : @"44.100 Khz", value : @(44100.0)},
                           @{title : @"48.000 Khz", value : @(48000.0)},
                           @{title : @"88.200 Khz", value : @(88200.0)},
                           @{title : @"96.000 Khz", value : @(960000.0)},
                           ];
    
    [self addMenuItemsToMenu:self.prefsAudioRate.menu withArray:rateArray withSelector:@selector(selectAudioSamplerate:)];
    
#pragma mark - Audio Prefs Quality
    
    NSArray* qualityArray = @[
                              @{title : @"Minimum", value : @(AVAudioQualityMin)} ,
                              @{title : @"Low", value : @(AVAudioQualityLow)},
                              @{title : @"Normal", value : @(AVAudioQualityMedium)},
                              @{title : @"High", value : @(AVAudioQualityHigh)},
                              @{title : @"Maximum", value : @(AVAudioQualityMax)}
                              ];
    
    [self addMenuItemsToMenu:self.prefsAudioQuality.menu withArray:qualityArray withSelector:@selector(selectAudioQuality:)];
    
#pragma mark - Audio Prefs Bitrate
    
    NSMenuItem* recommendedItem2 = [[NSMenuItem alloc] initWithTitle:@"Recommended" action:@selector(selectAudioBitrate:) keyEquivalent:@""];
    [recommendedItem2 setRepresentedObject:[NSNull null]];
    [self.prefsAudioBitrate.menu addItem:recommendedItem2];
    [self.prefsAudioBitrate.menu addItem:[NSMenuItem separatorItem]];
    
    NSArray* bitRateArray = @[
                              //@{title : @"Recommended", value : [NSNull null]} ,
                              @{title : @"16 Kbps", value : @(16000)},
                              @{title : @"24 Kbps", value : @(24000)},
                              @{title : @"32 Kbps", value : @(32000)},
                              @{title : @"48 Kbps", value : @(38000)},
                              @{title : @"64 Kbps", value : @(64000)},
                              @{title : @"80 Kbps", value : @(80000)},
                              @{title : @"96 Kbps", value : @(96000)},
                              @{title : @"112 Kbps", value : @(112000)},
                              @{title : @"128 Kbps", value : @(128000)},
                              @{title : @"160 Kbps", value : @(160000)},
                              @{title : @"192 Kbps", value : @(192000)},
                              @{title : @"224 Kbps", value : @(224000)},
                              @{title : @"256 Kbps", value : @(256000)},
                              @{title : @"320 Kbps", value : @(320000)},
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
        NSDictionary* codecInfo = self.prefsVideoCompressor.selectedItem.representedObject;
        if( [codecInfo[@"CodecName"] containsString:@"JPEG"])
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
    if(compressorDict == [NSNull null] || compressorDict == nil)
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
    
    // If we are on passthrough encoder, then we disable all our options
    if(self.prefsAudioFormat.selectedItem.representedObject == [NSNull null])
    {
        // disable other ui
        self.prefsAudioBitrate.enabled = NO;
        [self.prefsAudioBitrate selectItemAtIndex:0];
        
        self.prefsAudioQuality.enabled = NO;
        [self.prefsAudioQuality selectItemAtIndex:0];
        
        self.prefsAudioRate.enabled = NO;
        [self.prefsAudioRate selectItemAtIndex:0];
    }
    else
    {
        // if we have linear linear PCM (uncompressed) we dont enable bitrate / quality
        
        if([self.prefsAudioFormat.selectedItem.representedObject isEqual: @(kAudioFormatLinearPCM)])
        {
            self.prefsAudioBitrate.enabled = NO;
            self.prefsAudioQuality.enabled = NO;
            self.prefsAudioRate.enabled = YES;
        }
        else
        {
            self.prefsAudioBitrate.enabled = YES;
            self.prefsAudioQuality.enabled = YES;
            self.prefsAudioRate.enabled = YES;
        }
    }
    
    [self validateAudioPrefsUI];
    [self buildAudioPreferences];
}

- (IBAction)selectAudioSamplerate:(id)sender
{
    NSLog(@"selected Audio Sampleate: %@", [sender representedObject]);
    [self validateAudioPrefsUI];
    [self buildAudioPreferences];
}

- (IBAction)selectAudioQuality:(id)sender
{
    NSLog(@"selected Audio Quality: %@", [sender representedObject]);
    [self validateAudioPrefsUI];
    [self buildAudioPreferences];
}

- (IBAction)selectAudioBitrate:(id)sender
{
    NSLog(@"selected Audio Bitrate: %@", [sender representedObject]);
    [self validateAudioPrefsUI];
    [self buildAudioPreferences];
}

#pragma mark - Audio Prefs

- (void) validateAudioPrefsUI
{
}


// Todo: Number of channels?
- (void) buildAudioPreferences
{
    NSMutableDictionary* audioSettingsDictonary = [NSMutableDictionary new];
    
    // get our fourcc from our compressor UI represented object and convert it to a string
    id audioFormat = self.prefsAudioFormat.selectedItem.representedObject;
    
    // If we are passthrough, we set out video prefs to nil and bail early
    if(audioFormat == [NSNull null] || audioFormat == nil)
    {
        self.prefsAudioSettings = nil;
        return;
    }
    
    // Standard keys
    audioSettingsDictonary[AVFormatIDKey] = audioFormat;
    audioSettingsDictonary[AVSampleRateKey] = self.prefsAudioRate.selectedItem.representedObject;
    
    // for now, we let our encoder match source - this is handled in our transcoder
    audioSettingsDictonary[AVNumberOfChannelsKey] = [NSNull null];
    
    switch ([audioFormat intValue])
    {
        case kAudioFormatLinearPCM:
        {
            // Add LinearPCM required keys
            audioSettingsDictonary[AVLinearPCMBitDepthKey] = @(16);
            audioSettingsDictonary[AVLinearPCMIsBigEndianKey] = @(NO);
            audioSettingsDictonary[AVLinearPCMIsFloatKey] = @(NO);
            audioSettingsDictonary[AVLinearPCMIsNonInterleavedKey] = @(NO);
            
            break;
        }
        case kAudioFormatAppleLossless:
        case kAudioFormatMPEG4AAC:
        {
            //            audioSettingsDictonary[AVEncoderAudioQualityKey] = self.prefsAudioQuality.selectedItem.representedObject;
            audioSettingsDictonary[AVEncoderBitRateKey] = self.prefsAudioBitrate.selectedItem.representedObject;
            audioSettingsDictonary[AVSampleRateConverterAlgorithmKey] = AVSampleRateConverterAlgorithm_Normal;
            audioSettingsDictonary[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_Constant;
            
        }
        default:
            break;
    }
    
    self.prefsAudioSettings = [audioSettingsDictonary copy];
    
    NSLog(@"Calculated Audio Settings : %@", self.prefsAudioSettings);
    
}

#pragma mark - Outline View Delegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    NSTableCellView* view = (NSTableCellView*)[outlineView makeViewWithIdentifier:@"Preset" owner:self];

    if([item isKindOfClass:[PresetGroup class]])
    {
        PresetGroup* itemGroup = (PresetGroup*)item;
        view.textField.stringValue = itemGroup.title;
        view.imageView.image = [NSImage imageNamed:@"ic_folder_white"];
    }
    else if ([item isKindOfClass:[PresetObject class]])
    {
        PresetObject* presetItem = (PresetObject*)item;

        view.textField.stringValue = presetItem.title;
        view.imageView.image = [NSImage imageNamed:@"ic_insert_drive_file_white"];
    }
    else if([item isKindOfClass:[NSNumber class]])
    {
        NSNumber* itemNumber = (NSNumber*)item;
        
        switch (itemNumber.integerValue)
        {
            case 0:
            {
                view.textField.stringValue = @"Audio Settings";
                view.imageView.image = [NSImage imageNamed:@"ic_volume_up_white"];
                break;
            }
            case 1:
            {
                view.textField.stringValue = @"Video Settings";
                view.imageView.image = [NSImage imageNamed:@"ic_local_movies_white"];
                break;
            }
            case 2:
            {
                view.textField.stringValue = @"Analysis Settings";
                view.imageView.image = [NSImage imageNamed:@"ic_info_white"];
                break;
            }
            default:
                break;
        }
    }
    
    return view;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    [self.videoContainerView removeFromSuperview];
    [self.audioContainerView removeFromSuperview];
    [self.analysisContainerView removeFromSuperview];
    [self.overviewContainerView removeFromSuperview];
    
    if([item isKindOfClass:[PresetObject class]])
    {
        
        [self.presetInfoContainerBox addSubview:self.overviewContainerView];
        
        self.overviewContainerView.frame = self.presetInfoContainerBox.bounds;
        
        [self configureOverviewContainerViewFromPreset:(PresetObject*)item];
        
        return YES;
    }
    
    if([item isKindOfClass:[NSNumber class]])
    {
        NSNumber* index = (NSNumber*)item;
        switch (index.integerValue)
        {
            case 0:
            {
                [self.presetInfoContainerBox addSubview:self.audioContainerView];
                self.audioContainerView.frame = self.presetInfoContainerBox.bounds;

                [self configureAudioSettingsFromPreset:self.selectedPreset];
                break;
            }
            case 1:
            {
                [self.presetInfoContainerBox addSubview:self.videoContainerView];
                self.videoContainerView.frame = self.presetInfoContainerBox.bounds;
                
                [self configureVideoSettingsFromPreset:self.selectedPreset];
                break;
            }
            case 2:
            {
                [self.presetInfoContainerBox addSubview:self.analysisContainerView];
                self.analysisContainerView.frame = self.presetInfoContainerBox.bounds;
                
                [self configureAnalysisSettingsFromPreset:self.selectedPreset];
                break;
            }
            default:
                break;
        }

        return YES;
    }
    
    return NO;
}

#pragma mark - Container View Helpers

- (void) configureOverviewContainerViewFromPreset:(PresetObject*)preset
{
    self.selectedPreset = preset;
    
    self.overviewDescriptionTextField.stringValue = self.selectedPreset.description;
}

- (void) configureAudioSettingsFromPreset:(PresetObject*)preset
{
    
}

- (void) configureVideoSettingsFromPreset:(PresetObject*)preset
{
    
}

- (void) configureAnalysisSettingsFromPreset:(PresetObject*)preset
{
    
}


#pragma mark - Outline View Data Source

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    // if item is nil, its our "root" item
    // we have 2 sources, built in and custom presets
    if(item == nil)
    {
        return 2;
    }
    else if([item isKindOfClass:[PresetGroup class]])
    {
        PresetGroup* itemGroup = (PresetGroup*)item;
        return itemGroup.children.count;
    }
    else if ([item isKindOfClass:[PresetObject class]])
    {
        // audio, video, analysis
        return 3;
    }
    else if ([item isKindOfClass:[NSNumber class]])
    {
        return 0;
    }
  
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    // root item
    if(item == nil)
    {
        if (index == 0)
        {
            return self.standardPresets;
        }
        if(index == 1)
        {
            return self.customPresets;
        }
    }
    
    else if([item isKindOfClass:[PresetGroup class]])
    {
        PresetGroup* itemGroup = (PresetGroup*)item;
        return itemGroup.children[index];
    }
    
    else if ([item isKindOfClass:[PresetObject class]])
    {
        // return an NSNumber object that is the index
        // 0 = audio, 1 = video, 2 = analysis;
        return [NSNumber numberWithInteger:index];
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if(item == nil || [item isKindOfClass:[PresetGroup class]] || [item isKindOfClass:[PresetObject class]])
        return YES;
    
    return NO;
}

- (NSArray*) allPresets
{
    return [[self.standardPresets.children arrayByAddingObjectsFromArray:self.customPresets.children] copy];
}

@end
