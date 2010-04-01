#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from __future__ import with_statement
import numpy as np

class DTPointValueCollection2D(object):
    """2D Point Value collection object."""
    
    def __init__(self, points, values):
        super(DTPointValueCollection2D, self).__init__()
        """Create a new 2D point value collection.
        
        Arguments:
        points -- DTPointCollection2D object
        values -- values corresponding to each point
        
        Point collection and values may be empty, but not None.
        
        """
        
        assert points != None and values != None, "points and values are required"
        assert len(points) == len(values), "inconsistent lengths"
        self._points = points
        self._values = np.array(values, dtype=np.double)
            
    def bounding_box(self):
        return self._points.bounding_box()
        
    def add_point_value(self, point, value):
        self._points.add_point(point)
        self._values = np.append(self._values, value)
    
    def __iter__(self):
        for i in xrange(len(self)):
            x, y = self._points[i]
            yield (x, y, self._values[i])
        
    def __len__(self):
        return len(self._values)
   
    def __getitem__(self, idx):
        return (self._points[idx][0], self._points[idx][1], self._values[idx])     
        
    def __str__(self):
        s = "{\n"
        for x, y, v in self:
            s += "(%s, %s, %s)\n" % (x, y, v)
        s += "}\n"
        return s
    
    def dt_type(self):
        return "2D Point Value Collection"
        
    def dt_write(self, datafile, name):
        datafile.write_anonymous(self._values, name + "_V")
        datafile.write_anonymous(self._points, name)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    from datatank_py.DTPointCollection2D import DTPointCollection2D
    from datatank_py.DTPoint2D import DTPoint2D
    
    with DTDataFile("point_value_collection_2d.dtbin", truncate=True) as df:
        
        points = DTPointCollection2D([], [])
        for x in xrange(100):
            points.add_point(DTPoint2D(x, x * x / 100.))

        df["Point value collection 1"] = DTPointValueCollection2D(points, range(0, 100))
        
        xvals = np.array((10, 20, 30, 40, 50))
        yvals = xvals
        pv = DTPointValueCollection2D(DTPointCollection2D(xvals, yvals), xvals * xvals)
        df["Point value collection 2"] = pv
        
        print pv
