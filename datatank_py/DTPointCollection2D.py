#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import numpy as np

class DTPointCollection2D(object):
    """2D Point collection object."""
    
    def __init__(self, points, xvalues=None, yvalues=None):
        super(DTPointCollection2D, self).__init__()
        """Create a new 2D point collection.
        
        Arguments:
        points -- array of (x, y) points as 2 X N array
        xvalues -- array of x values; points must be None
        yvalues -- array of y values; points must be None
        
        Pass None or an empty array for points to get an empty collection
        that can be added to with add_point().
        
        """
        
        # Create a new point collection as either
        #     DTPointCollection2D(array)
        # or
        #     DTPointCollection2D(array,vector)
        # the array needs to be allocated as (2,N), where N = number of points.
        # 
        # If you don't know beforehand the size of the array, use the
        # IncreaseSize(...) and TruncateSize(...) functions to resize the array.
        # 
        # The array is layed out as:
        # array(0,j) = x coordinate of point j, array(1,j) = y coordinate of point j.
        
        if xvalues != None or yvalues != None:
            assert xvalues != None and yvalues != None, "both x and y arrays are required"
            assert len(xvalues) == len(yvalues), "inconsistent lengths"
            self._xvalues = np.array(xvalues).astype(np.double)
            self._yvalues = np.array(yvalues).astype(np.double)
        elif points != None and np.size(points):
            assert xvalues == None and yvalues == None, "pass either points or separate x/y arrays"
            assert points.shape[0] == 2, "incorrect shape"
            self._xvalues = points[0,:].astype(np.double)
            self._yvalues = points[1,:].astype(np.double)
        else:
            assert xvalues == None and yvalues == None, "pass either points or separate x/y arrays"
            self._xvalues = np.array([], dtype=np.double)
            self._yvalues = np.array([], dtype=np.double)
            
    def bounding_box(self):
        if self._xvalues == None or np.size(self._xvalues) == 0:
            return (0, 0, 0, 0)
        return (min(self._xvalues), max(self._xvalues), min(self._yvalues), max(self._yvalues))
        
    def add_point(self, point):
        self._xvalues = np.concatenate((self._xvalues, (point.x,)))
        self._yvalues = np.concatenate((self._yvalues, (point.y,)))
        
    def __str__(self):
        s = "{\n"
        for x, y in zip(self._xvalues, self._yvalues):
            s += "(%s, %s)\n" % (x, y)
        s += "}\n"
        return s
    
    def dt_type(self):
        return "2D Point Collection"
        
    def dt_write(self, datafile, name):
        datafile.write_anonymous(self.bounding_box(), name + "_bbox2D")
        datafile.write_anonymous(np.dstack((self._xvalues, self._yvalues)), name)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    from datatank_py.DTPoint2D import DTPoint2D
    
    with DTDataFile("point_collection_2d.dtbin", truncate=True) as df:
        
        collection = DTPointCollection2D(None)
        for x in xrange(0, 100):
            collection.add_point(DTPoint2D(x, x * x / 100.))

        df["Point collection 1"] = collection
        
        points = np.vstack(([1, 2, 3, 4, 5], [1, 2, 3, 4, 5]))
        df["Point collection 2"] = DTPointCollection2D(points)
        
        xvals = (10, 20, 30, 40, 50)
        yvals = xvals
        df["Point collection 3"] = DTPointCollection2D(None, xvalues=xvals, yvalues=yvals)
