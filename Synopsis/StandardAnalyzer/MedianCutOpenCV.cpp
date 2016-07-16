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
    ColorCube::ColorCube(std::vector<cv::Vec3f> vecOfcolors, bool useDeltaE)
    {
        useCIEDE2000 = useDeltaE;

        colors = vecOfcolors;
        minColor = cv::Vec3f(std::numeric_limits<float>::min());
        maxColor = cv::Vec3f(std::numeric_limits<float>::max());

        shrink();

    }

    ColorCube::ColorCube(cv::Mat image, bool useDeltaE)
    {
        useCIEDE2000 = useDeltaE;
        
        cv::Mat imageReshaped;
        
        // unroll the image and then make a vector of colors from it
        imageReshaped = image.reshape(1, image.rows * image.cols);
        
        for(int i = 0; i < imageReshaped.rows; i++)
        {
            float l = imageReshaped.at<float>(i,0);
            float a = imageReshaped.at<float>(i,1);
            float b = imageReshaped.at<float>(i,2);
            
            cv::Vec3f color = cv::Vec3f(l, a, b);

            colors.push_back( color );
        }
        
        imageReshaped.release();
        
        minColor = cv::Vec3f(std::numeric_limits<float>::min());
        maxColor = cv::Vec3f(std::numeric_limits<float>::max());
        
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
            for(int i = 1; i < colors.size(); i++ )
            {
                double mindelta = CIEDE2000::CIEDE2000(minColor, colors[i]);
                double maxdelta = CIEDE2000::CIEDE2000(maxColor, colors[i]);
                
                if( mindelta < 0)
                {
                    minColor = colors[i];
                }
                
                if( maxdelta > 0)
                {
                    maxColor = colors[i];
                }
            }
        }
        else
        {
            for(int i = 1; i < colors.size(); i++ )
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
        
        while (colorCubeQueue.size() < desiredSize && colorCubeQueue.top().colors.size() > 1)
        {
            // Pop our first color cube off the stack
            ColorCube currentColor = colorCubeQueue.top();

            colorCubeQueue.pop();

            // number of colors we have
            long numColors = currentColor.colors.size();
            
            long half = (numColors + 1) / 2;
            
//            cv::Vec3f firstColor = currentColor.colors[0];
//            cv::Vec3f middleColor = currentColor.colors[half];
//            cv::Vec3f lastColor = currentColor.colors[ numColors - 1];

            auto firstColor = currentColor.colors.begin();
            auto middleColor = currentColor.colors.begin() + half;
            auto lastColor = currentColor.colors.end();
            
            // Euclidean ?
            switch(currentColor.longestSideIndex())
            {
                case 0: std::nth_element(firstColor, middleColor, lastColor, CoordinateColorComparator<0>()); break;
                case 1: std::nth_element(firstColor, middleColor, lastColor, CoordinateColorComparator<1>()); break;
                case 2: std::nth_element(firstColor, middleColor, lastColor, CoordinateColorComparator<2>()); break;
            }
            
            std::vector<cv::Vec3f> lowerColorsVec(currentColor.colors.begin(), currentColor.colors.begin() + half);
            std::vector<cv::Vec3f> upperColorsVec(currentColor.colors.begin() + half, currentColor.colors.end());

            ColorCube lowerColors(lowerColorsVec, useCIEDE2000);
            ColorCube higherColors(upperColorsVec, useCIEDE2000);

            colorCubeQueue.push(lowerColors);
            colorCubeQueue.push(higherColors);
        }

        std::list<std::pair<cv::Vec3f, unsigned int> > result;
        while(!colorCubeQueue.empty())
        {
            ColorCube currentColorCube = colorCubeQueue.top();
            colorCubeQueue.pop();

        
            //int volume = block.volume();
            //cout<<"block "<<result.size()<<": volume "<<volume<<" longest side "<<block.longestSideLength()<<" count "<<block.numPoints()<<endl;
            
            float sum[3] = {0};
            for(int i = 0; i < currentColorCube.colors.size(); i++)
            {
                for(int j=0; j < 3; j++)
                {
                    sum[j] += currentColorCube.colors[i][j];
                }
            }
            
            cv::Vec3f averagePoint;
            for(int j=0; j < 3; j++)
            {
                averagePoint[j] = (float)(sum[j] / currentColorCube.colors.size());
            }
            
            result.push_back(std::make_pair(averagePoint, currentColorCube.colors.size()));
        }
        
        return result;

    }

    

}