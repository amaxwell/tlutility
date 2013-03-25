#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

class DTPointValue2D(object):
    """2D Point Value object."""
    
    def __init__(self, x, y, value):
        super(DTPointValue2D, self).__init__()
        """Create a new 2D point value.
        
        Arguments:
        x -- x value
        y -- y value
        value -- value
        
        """
                    
        self.x = float(x)
        self.y = float(y)
        self.value = float(value)
        
    def __str__(self):
        return "2D Point Value ((%f, %f) : %f)" % (self.x, self.y, self.value)
        
    def __repr__(self):
        return "(%f, %f, %f)" % (self.x, self.y, self.value)
    
    def __dt_type__(self):
        return "2D Point Value"
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous((self.x, self.y, self.value), name)
        
    @classmethod
    def from_data_file(self, datafile, name):
        
        (x, y, z) = datafile[name]
        return DTPointValue2D(x, y, z)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    
    with DTDataFile("pointvalue2d.dtbin", truncate=True) as df:
        
        for x in xrange(10):
            df["Point value %d" % x] = DTPointValue2D(x, x, x / 10.)
