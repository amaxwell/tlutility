#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

class DTPoint2D(object):
    """2D Point object."""
    
    def __init__(self, x, y):
        super(DTPoint2D, self).__init__()
        """Create a new 2D point.
        
        Arguments:
        x -- x value
        y -- y value
        
        """
                    
        self.x = float(x)
        self.y = float(y)
    
    def __dt_type__(self):
        return "2D Point"
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous((self.x, self.y), name)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    
    with DTDataFile("point2d.dtbin", truncate=True) as df:
        
        for x in xrange(10):
            df["Point %d" % x] = DTPoint2D(x, x)
