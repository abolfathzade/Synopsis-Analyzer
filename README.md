
# Synopsis Analyzer/Transcoder

![alt tag](https://dl.dropboxusercontent.com/u/42612525/SynopsisRTF/SynopsisAnalyzer.jpg)

### Overview

Synopsis is video analysis and transcoding tool, as well as a metadata format for embeddeding advanced analyzed metadata within .MOV and (in testing) .MP4 video files. 

Please note Synopsis Analyzer (and related tools and frameworks) are under heavy development. Things are changing fast.

### Synopsis Analyzer features:

* Multithreaded batch video transcoding
* Hardware accelerated vidoe decode and encode for supported codecs.
* Presets for encoding settings
* Optional Analysis stage during transcode
* Export analsysis files to JSON sidecar or embed into supported video container formats.
* Supports 3rd party analysis plugins that implement the Synopsis Plugin standard.

### Included video analysis following metadata:

* Cinematic Shot Type tagging for search
* Object recognition
* Feature vectors for similarity and sorting.
* Dominant Color and Histograms similarity and sorting,
* Perceptual hashing for perceptual similarity and sorting
* Visual Saliency (areas of visual interest) (beta)
* Motion amount, direction, and smoothness for every frame, and globally, for similarity and sorting.

### Workflow Opporunities:

**Archival**: 
* Analyze your media archive, optionally transcoding to an appropriate archival video format like H.264.
* Run spotlight queries locally by hand, or programatically to find media based on analyzed features.
* Export analyzed metadata to your SQL database, to run queries on your own database schema on the web.

**Design & Branding**:
* Analyze content and optionally transcode to an appropriate playback video format like ProRes, MotionJpeg or Apple Intermediate.
* Develop procedural designs and templates to add logos, text and graphics to content while maintaining the focus (saliency) of the original image.
* Develop motion graphics and transitions that are aware of the underlying content.

**Editing**:
* Analyze content and optionally transcode to an appropriate playback video format like ProRes, MotionJpeg or Apple Intermediate.
* Search and filter clips based on dominant color, motion, and histogram similarity.
* Develop software and rules to procedurally edit video based on the underlying content.

**Performance & VJing**:
* Analyze content and optionally transcode to an appropriate playback video format like ProRes, MotionJpeg or Apple Intermediate and eventually HAP.
* Automatic clip filtering based on your currently playing content, color palette and motion.
* Sort clips by motion, color, features, content, style.
* Video effects that follow content, choose their color scheme, and react to the clips you play without slowing down your performance by running computationally expensive and slow analysis in realtime.

### Extending Features:

Synopsis Analysis is plugin based, allowing developers to easily extend and experiment analyzing video and caching results for future use.

See the DesignDiscussion wiki for more information about possible modules and direction of development.

### Development Notes

**Current Requirements**:
* Mac OS X 10.10 or higher
* XCode 8 or higher

**Dependencies**
* Synopsis.framework (included in submodule)
* * Tensorflow 1.1 +
* * OpenCV 3.2 +

**Compilation Guideline**

Please ensure that your git checkout includes all submodules - downloading an archive from the webpage does not include submodules. 

Please see the Compilation Guide for Synopsis.framework in the Synopsis Wiki - once you can properly build the Framework building Synopsis Analyzer should be straightforward.


