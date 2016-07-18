
#Synopsis Analyzer/Transcoder

![alt tag](https://github.com/Synopsis/Synopsis/blob/master/Synopsis/Synopsis/Icon-512.png)


Synopsis is video analysis and transcoding tool, as well as a metadata format for embeddeding advanced analyzed metadata withing MOV and MP4 video files. 

Synopsis is aimed at Interactive, Realtime, Performance and Installation advertising, arts and technologies.

This repository hosts a Synopsis Multimedia Analyser and Transcoder implementation written for Mac OS X.

Synopsis Analysis is plugin based, allowing developers to easily extend and experiment analyzing video and caching results for future use.

###Currently, Synopsis can analysize video and embed the following metadata:

* Per Frame Average Color (via OpenCV)
* Per Frame Dominant Color (via OpenCV)
* Per Frame Tracked Points (via OpenCV)
* Per Frame Motion Amount (via OpenCV)
* Per Frame Image Description (via DeepBelief)
* Global Average Color (via OpenCV)
* Global Dominant Colors (via OpenCV)

###Currently In Development:

* Per Frame Motion Direction (via OpenCV Optical Flow)
* Global Motion Direction (via OpenCV Optical Flow)
* Per Frame Image Description via Inception (via Tensorflow)
* Global Image Description via Inception (via Tensorflow)
* Per Frame Image Style Description (via Tensorflow)
* Global Image Style Description (via Tensorflow)

See the DesignDiscussion wiki for more information about possible modules and direction of development.
