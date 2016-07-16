//
//  MedianCutOpenCV.cpp
//  Synopsis
//
//  Created by vade on 7/15/16.
//  Copyright © 2016 metavisual. All rights reserved.
//

#include "MedianCutOpenCV.hpp"

#include <queue>
#include <algorithm>

#include "CIEDE2000.h"



namespace MedianCutOpenCV
{
    ColorCube::ColorCube(cv::Vec3f* vecOfcolors,int nColors, bool useDeltaE)
    {
        useCIEDE2000 = useDeltaE;
        
        numColors = nColors;

        colors = vecOfcolors;
        float min = std::numeric_limits<float>::min();
        float max = std::numeric_limits<float>::max();
        minColor = cv::Vec3f(min, min, min);
        maxColor = cv::Vec3f(max, max, max);

        shrink();

    }

    ColorCube::ColorCube(cv::Mat image, bool useDeltaE)
    {
        // todo:: assert depth = 3 or whatever...
        // todo:: assert colorspace is LAB if we use CIEDE2000?
        
        useCIEDE2000 = useDeltaE;
        
        cv::Mat imageReshaped;
        
        // unroll the image and then make a vector of colors from it
        numColors = image.rows * image.cols;
        
        colors = image.ptr<cv::Vec3f>(0);
        
        float min = std::numeric_limits<float>::min();
        float max = std::numeric_limits<float>::max();
        minColor = cv::Vec3f(min, min, min);
        maxColor = cv::Vec3f(max, max, max);
        
        shrink();
    }
    
    ColorCube::ColorCube(cv::UMat image, bool useCIEDE2000)
    {
        ColorCube(image.getMat(cv::ACCESS_READ), useCIEDE2000);
    }
        
    // This is Euclidean based on color
    void ColorCube::shrink()
    {
        minColor = maxColor = colors[0];

        if(useCIEDE2000)
        {
            double lastMinDelta = DBL_MAX;
            double lastMaxDelta = DBL_MIN;
            for(int i = 1; i < numColors; i++ )
            {
                double mindelta = CIEDE2000::CIEDE2000(minColor, colors[i]);
                double maxdelta = CIEDE2000::CIEDE2000(maxColor, colors[i]);
                
                if( mindelta < lastMinDelta)
                {
                    minColor = colors[i];
                    lastMinDelta = mindelta;
                }
                
                if( maxdelta > lastMaxDelta)
                {
                    maxColor = colors[i];
                    lastMaxDelta = maxdelta;
                }
            }
        }
        else
        {
            for(int i = 1; i < numColors; i++ )
            {
                for(int j = 0; j < 3; j++ )
                {
                    minColor[j] = fmin(minColor[j], colors[i][j]);
                    maxColor[j] = fmax(maxColor[j], colors[i][j]);
                }
            }
        }
    }
    
    // Call Shrink prior to this having
    int ColorCube::longestSideIndex() const
    {
        int m = maxColor[0] - minColor[0];
        int maxIndex = 0;
        for(int i=1; i < 3; i++)
        {
            int diff = maxColor[i] - minColor[i];
            if (diff > m)
            {
                m = diff;
                maxIndex = i;
            }
        }

        return maxIndex;
    }
    
    int ColorCube::longestSideLength() const
    {
        int i = longestSideIndex();
        return maxColor[i] - minColor[i];
    }
    
    int ColorCube::volume() const
    {
        cv::Vec3f diff;
        for ( int i = 0; i < 3; i++ )
        {
            diff[i] = maxColor[i] - minColor[i];
        }
        
        int volume = diff[0];
        
        for ( int i = 1; i < 3; i++ )
        {
            volume *= diff[i];
        }
        
        return volume;
    }

    
    bool ColorCube::operator < (const ColorCube& other) const
    {
        // Euclidiean?
        if(useCIEDE2000)
        {
            float delta =  CIEDE2000::CIEDE2000(maxColor, other.maxColor) ;
            
            return ( delta >= 0 );
        }
        else
            return ( longestSideLength() < other.longestSideLength() );

    }

    std::list< std::pair<cv::Vec3f,unsigned int> > medianCut(cv::UMat image, unsigned int desiredSize, bool useCIEDE2000)
    {
        return medianCut(image.getMat(cv::ACCESS_READ), desiredSize, useCIEDE2000);
    }
    
    std::list< std::pair<cv::Vec3f,unsigned int> > medianCut(cv::Mat image, unsigned int desiredSize, bool useCIEDE2000)
    {
        std::priority_queue<ColorCube> colorCubeQueue;

        ColorCube initialColorCube(image, useCIEDE2000);
        
        colorCubeQueue.push(initialColorCube);
        
        while (colorCubeQueue.size() < desiredSize && colorCubeQueue.top().numColors > 1)
        {
            // Pop our first color cube off the stack
            ColorCube currentColor = colorCubeQueue.top();

            colorCubeQueue.pop();

            // number of colors we have
            long numColors = currentColor.numColors;
            
            long half = (numColors + 1) / 2;
            
            auto firstColor = currentColor.colors;
            auto middleColor = currentColor.colors + half;
            auto lastColor = currentColor.colors + numColors;
            
            // Euclidean ?
            switch(currentColor.longestSideIndex())
            {
                case 0: std::nth_element(firstColor, middleColor, lastColor, CoordinateColorComparator<0>()); break;
                case 1: std::nth_element(firstColor, middleColor, lastColor, CoordinateColorComparator<1>()); break;
                case 2: std::nth_element(firstColor, middleColor, lastColor, CoordinateColorComparator<2>()); break;
            }
            

            ColorCube lowerColors(firstColor, (int)(middleColor - firstColor), useCIEDE2000);
            ColorCube higherColors(middleColor, (int)(lastColor - middleColor), useCIEDE2000);

            colorCubeQueue.push(lowerColors);
            colorCubeQueue.push(higherColors);
        }

        std::list<std::pair<cv::Vec3f, unsigned int> > result;
        while(!colorCubeQueue.empty())
        {
            ColorCube currentColorCube = colorCubeQueue.top();
            colorCubeQueue.pop();
            
            float sum[3] = {0};
            for(int i = 0; i < currentColorCube.numColors; i++)
            {
                for(int j=0; j < 3; j++)
                {
                    sum[j] += currentColorCube.colors[i][j];
                }
            }
            
            cv::Vec3f averagePoint;
            for(int j=0; j < 3; j++)
            {
                averagePoint[j] = (float)(sum[j] / currentColorCube.numColors);
            }
            
            if(useCIEDE2000)
            {
                // find closest color in the color cube to our average;
                double delta = DBL_MAX;
                cv::Vec3f closestColor;
                for(int i = 0; i < currentColorCube.numColors; i++)
                {
                    double currentDelta = CIEDE2000::CIEDE2000(averagePoint, currentColorCube.colors[i]);
                    if(currentDelta < delta)
                    {
                        delta = currentDelta;
                        closestColor = currentColorCube.colors[i];
                    }
                }
                
                result.push_back( std::make_pair( closestColor, currentColorCube.numColors ) );
            }
            else
            {
                result.push_back( std::make_pair( averagePoint, currentColorCube.numColors ) );
            }
        }
        
        return result;

    }

    

}