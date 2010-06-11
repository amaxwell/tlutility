#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from DTRegion3D import DTRegion3D
import numpy as np

class DTStructuredGrid3D(object):
    """3D structured grid object."""
    
    def __init__(self, x, y, z):
        super(DTStructuredGrid3D, self).__init__()
        """Create a new 3D structured grid.
        
        Arguments:
        x -- vector or 3D array of x values
        y -- vector or 3D array of y values
        z -- vector or 3D array of z values
                
        """                   
                   
        if (len(np.shape(x)) == 1 and len(np.shape(y)) == 1 and len(np.shape(z)) == 1):
            
            # DataTank fails to read if we just save the vectors, unfortunately,
            # so we need to expand to the full array.  This is lame.
            
            self._x = np.zeros((len(x), len(y), len(z)), dtype=np.double)
            self._y = np.zeros((len(x), len(y), len(z)), dtype=np.double)
            self._z = np.zeros((len(x), len(y), len(z)), dtype=np.double)
            
            # There may be a one-liner to do this with array slicing and broadcasting,
            # but I wasted too much time trying to find it.  This is copied from 
            # DTStructuredGrid3D.cpp, so it should work.
            
            for xi, xv in enumerate(x):
                for zi in xrange(len(z)):
                    for yi in xrange(len(y)):
                        self._x[xi,yi,zi] = xv
            
            for yi, yv in enumerate(y):
                for zi in xrange(len(z)):
                    for xi in xrange(len(x)):
                        self._y[xi,yi,zi] = yv
            
            for zi, zv in enumerate(z):
                for yi in xrange(len(y)):
                    for xi in xrange(len(x)):
                        self._z[xi,yi,zi] = zv
            
        else:
            assert np.shape(x) == np.shape(y)
            assert np.shape(x) == np.shape(z)
            assert np.shape(y) == np.shape(z)
            self._x = np.array(x, dtype=np.double)
            self._y = np.array(y, dtype=np.double)
            self._z = np.array(z, dtype=np.double)
    
    def __dt_type__(self):
        return "3D Structured Grid"
        
    def shape(self):
        return np.shape(self._x)
        
    def bounding_box(self):
        return DTRegion3D(np.min(self._x), np.max(self._x), np.min(self._y), np.max(self._y), np.min(self._z), np.max(self._z))
        
    def mask(self):
        return np.array([], dtype=np.int32)
        
    def __str__(self):
        return self.__dt_type__() + ": " + str(self.bounding_box())
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self.bounding_box(), name + "_bbox3D")
        datafile.write_anonymous(self._x, name + "_X")
        datafile.write_anonymous(self._y, name + "_Y")
        datafile.write_anonymous(self._z, name + "_Z")
        datafile.write_anonymous(self.mask(), name)

if __name__ == '__main__':
    
    from DTDataFile import DTDataFile
    with DTDataFile("structured_grid3d.dtbin", truncate=True) as df:
                
        grid = DTStructuredGrid3D(range(5), range(4), range(3))
        df["grid"] = grid
    
        print grid
        #print "x=", grid._x
        #print "y=", grid._y
        #print "z=", grid._z
        