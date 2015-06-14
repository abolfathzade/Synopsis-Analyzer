/* Copyright (c) 2013 the authors listed at the following URL, and/or
the authors of referenced articles or incorporated external code:
http://en.literateprograms.org/Median_cut_algorithm_(C_Plus_Plus)?action=history&offset=20080309133934

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Retrieved from: http://en.literateprograms.org/Median_cut_algorithm_(C_Plus_Plus)?oldid=12754
*/

#include <limits>
#include <queue>
#include <algorithm>
#include "MedianCut.h"
#include <iostream>
using namespace std;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wold-style-cast"

namespace MedianCut {
	
	Block::Block(Point* _points, int _pointsLength)
	{
		this->points = _points;
		this->pointsLength = _pointsLength;
		for(int i=0; i < NUM_DIMENSIONS; i++)
		{
			minCorner.x[i] = std::numeric_limits<float>::min();
			maxCorner.x[i] = std::numeric_limits<float>::max();
		}
	}
	Point * Block::getPoints()
	{
		return points;
	}
	
	int Block::numPoints() const
	{
		return pointsLength;
	}
	int Block::longestSideIndex() const
	{
		int m = maxCorner.x[0] - minCorner.x[0];
		int maxIndex = 0;
		for(int i=1; i < NUM_DIMENSIONS; i++)
		{
			int diff = maxCorner.x[i] - minCorner.x[i];
			if (diff > m)
			{
				m = diff;
				maxIndex = i;
			}
		}
		return maxIndex;
	}
	int Block::longestSideLength() const
	{
		int i = longestSideIndex();
		return maxCorner.x[i] - minCorner.x[i];
	}
	int Block::volume() const
	{
		Point diff;
		for ( int i=0; i<NUM_DIMENSIONS; i++ )
		{
			diff.x[i] = maxCorner.x[i]-minCorner.x[i];
		}
		int volume = diff.x[0];
		for ( int i=1; i<NUM_DIMENSIONS; i++ )
		{
			volume *= diff.x[i];
		}
		return volume;
	}
	bool Block::operator<(const Block& rhs) const
	{
		return this->longestSideLength() < rhs.longestSideLength();
	}
	void Block::shrink()
	{
		int i,j;
		for(j=0; j<NUM_DIMENSIONS; j++)
		{
			minCorner.x[j] = maxCorner.x[j] = points[0].x[j];
		}
		for(i=1; i < pointsLength; i++)
		{
			for(j=0; j<NUM_DIMENSIONS; j++)
			{
				minCorner.x[j] = min(minCorner.x[j], points[i].x[j]);
				maxCorner.x[j] = max(maxCorner.x[j], points[i].x[j]);
			}
		}
		// recalculate points?
		
	}
	std::list<std::pair<Point,unsigned int> > medianCut(MedianCut::Point* image, int numPoints, unsigned int desiredSize)
	{
		std::priority_queue<Block> blockQueue;
		Block initialBlock(image, numPoints);
		initialBlock.shrink();
		blockQueue.push(initialBlock);
		while (blockQueue.size() < desiredSize && blockQueue.top().numPoints() > 1)
		{
			Block longestBlock = blockQueue.top();
			
			blockQueue.pop();
			MedianCut::Point * begin  = longestBlock.getPoints();
			MedianCut::Point * median = longestBlock.getPoints() + (longestBlock.numPoints()+1)/2;
			MedianCut::Point * end    = longestBlock.getPoints() + longestBlock.numPoints();
			switch(longestBlock.longestSideIndex())
			{
				case 0: std::nth_element(begin, median, end, CoordinatePointComparator<0>()); break;
				case 1: std::nth_element(begin, median, end, CoordinatePointComparator<1>()); break;
				case 2: std::nth_element(begin, median, end, CoordinatePointComparator<2>()); break;
			}
			
			Block block1(begin, (int)(median-begin)), block2(median, (int)(end-median));
			block1.shrink();
			block2.shrink();
			blockQueue.push(block1);
			blockQueue.push(block2);
		}
		std::list<std::pair<MedianCut::Point, unsigned int> > result;
		while(!blockQueue.empty())
		{
			Block block = blockQueue.top();
			blockQueue.pop();
			MedianCut::Point * points = block.getPoints();
			
			//int volume = block.volume();
			//cout<<"block "<<result.size()<<": volume "<<volume<<" longest side "<<block.longestSideLength()<<" count "<<block.numPoints()<<endl;
			
			float sum[NUM_DIMENSIONS] = {0};
			for(int i=0; i < block.numPoints(); i++)
			{
				for(int j=0; j < NUM_DIMENSIONS; j++)
				{
					sum[j] += points[i].x[j];
				}
			}
			
			MedianCut::Point averagePoint;
			for(int j=0; j < NUM_DIMENSIONS; j++)
			{
				averagePoint.x[j] = (float)(sum[j] / block.numPoints());
			}
			
			result.push_back(make_pair(averagePoint,block.numPoints()));
		}
		return result;
	}
	
}

#pragma clang diagnostic pop

