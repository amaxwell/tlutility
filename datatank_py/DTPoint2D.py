#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import numpy as np

class DTPoint2D(object):
    """2D Point object."""
    dt_type = ("2D Point",)
    
    def __init__(self, x, y):
        super(DTPoint2D, self).__init__()
        """Create a new 2D point.
        
        Arguments:
        x -- x value
        y -- y value
        
        """
                    
        self.x = float(x)
        self.y = float(y)
        
    def __str__(self):
        return "2D Point (%f, %f)" % (self.x, self.y)
        
    def __repr__(self):
        return "(%f, %f)" % (self.x, self.y)
    
    def __dt_type__(self):
        return DTPoint2D.dt_type[0]
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous((self.x, self.y), name)
        
    @classmethod
    def from_data_file(self, datafile, name):
        
        (x, y) = np.squeeze(datafile[name])
        return DTPoint2D(x, y)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    
    with DTDataFile("point2d.dtbin", truncate=True) as df:
        
        for x in xrange(10):
            df["Point %d" % x] = DTPoint2D(x, x)

    with DTDataFile("point2d.dtbin") as df:
        
        print df.dt_object_named("Point 1")
