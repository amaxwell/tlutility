#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

class DTVector2D(object):
    """2D Vector object."""
    
    def __init__(self, x, y, u, v):
        super(DTVector2D, self).__init__()
        """Create a new 2D vector.
        
        Arguments:
        x -- x location
        y -- y location
        u -- x magnitude
        v -- y magnitude
        
        """
                    
        self.x = float(x)
        self.y = float(y)
        self.u = float(u)
        self.v = float(v)
        
    def __str__(self):
        return "%s (%f, %f, %f, %f)" % (self.__dt_type__(), self.x, self.y, self.u, self.v)
        
    def __repr__(self):
        return "(%f, %f, %f, %f)" % (self.x, self.y, self.u, self.v)
    
    def __dt_type__(self):
        return "2D Vector"
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous((self.x, self.y, self.u, self.v), name)
        
    @classmethod
    def from_data_file(self, datafile, name):
        
        (x, y, u, v) = datafile[name]
        return DTVector2D(x, y, u, v)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    
    with DTDataFile("vector2d.dtbin", truncate=True) as df:
        
        for x in xrange(3):
            df["Vector %d" % x] = DTVector2D(x, x, x * 2, x * 2.5)
