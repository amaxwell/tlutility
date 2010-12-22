#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from DTRegion2D import DTRegion2D
import numpy as np

class DTStructuredGrid2D(object):
    """2D structured grid object."""
    
    def __init__(self, x, y, mask=None):
        super(DTStructuredGrid2D, self).__init__()
        """Create a new 2D structured grid.
        
        Arguments:
        x -- vector or 2D array of x values
        y -- vector or 2D array of y values
        
        Note: if a full 2D array is passed, it must be ordered as (y, x)
        for compatibility with DataTank.  When using vectors, this is handled
        automatically.
                
        """                   
                   
        if (len(np.shape(x)) == 1 and len(np.shape(y)) == 1):
            
            # If we pass in vectors, DataTank expects them to have a 2D shape,
            # which is kind of peculiar.  This does avoid expanding the full
            # arrays, though.
            
            self._x = np.zeros((1, len(x)), dtype=np.float32)
            self._y = np.zeros((len(y), 1), dtype=np.float32)
            
            self._x[0,:] = x
            self._y[:,0] = y
            
        else:
            assert np.shape(x) == np.shape(y)
            self._x = np.array(x, dtype=np.float32)
            self._y = np.array(y, dtype=np.float32)
            
        self._mask = mask if mask != None else np.array([], dtype=np.int32)
    
    def __dt_type__(self):
        return "2D Structured Grid"
        
    def shape(self):
        return np.shape(self._x)
        
    def bounding_box(self):
        return DTRegion2D(np.nanmin(self._x), np.nanmax(self._x), np.nanmin(self._y), np.nanmax(self._y))
        
    def __str__(self):
        return self.__dt_type__() + ": " + str(self.bounding_box())
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self.bounding_box(), name + "_bbox2D")
        datafile.write_anonymous(self._x, name + "_X")
        datafile.write_anonymous(self._y, name + "_Y")
        datafile.write_anonymous(self._mask, name)

if __name__ == '__main__':
    
    from DTDataFile import DTDataFile
    with DTDataFile("test/structured_grid2d.dtbin", truncate=True) as df:
                
        grid = DTStructuredGrid2D(range(10), range(20))
        df["grid"] = grid
    
        print grid
        #print "x=", grid._x
        #print "y=", grid._y
        #print "z=", grid._z
        