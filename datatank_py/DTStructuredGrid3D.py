#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from DTRegion3D import DTRegion3D
from DTMask import DTMask
import numpy as np

class DTStructuredGrid3D(object):
    """3D structured grid object."""
    
    def __init__(self, x, y, z, mask=None):
        super(DTStructuredGrid3D, self).__init__()
        """Create a new 3D structured grid.
        
        Arguments:
        x -- vector or 3D array of x values
        y -- vector or 3D array of y values
        z -- vector or 3D array of z values
        
        Note: if a full 3D array is passed, it must be ordered as (z, y, x)
        for compatibility with DataTank.  When using vectors, this is handled
        automatically.
                
        """       
        
        sx = np.shape(x)
        sy = np.shape(y)
        sz = np.shape(z)
                   
        if (len(sx) == 1 and len(sy) == 1 and len(sz) == 1):
            
            # If we pass in vectors, DataTank expects them to have a 3D shape,
            # which is kind of peculiar.  This does avoid expanding the full
            # arrays, though.
            
            self._x = np.zeros((1, 1, len(x)), dtype=np.float32)
            self._y = np.zeros((1, len(y), 1), dtype=np.float32)
            self._z = np.zeros((len(z), 1, 1), dtype=np.float32)
            
            self._x[0,0,:] = x
            self._y[0,:,0] = y
            self._z[:,0,0] = z
            self._logical_shape = (len(z), len(y), len(x))
            
        else:
            assert len(sx) == 3
            assert len(sy) == 3
            assert len(sz) == 3
            # Shapes are not required to be identical, and will not be if initializing
            # from a DTDataFile that was saved by DataTank in vector form with singleton
            # dimensions.
            self._x = np.array(x, dtype=np.float32)
            self._y = np.array(y, dtype=np.float32)
            self._z = np.array(z, dtype=np.float32)
            self._logical_shape = (sz[0], sy[1], sx[2])
            
        self._mask = mask if mask != None else np.array([], dtype=np.int32)
    
    def __dt_type__(self):
        return "3D Structured Grid"
        
    def shape(self):
        """Returns logical shape of grid, not underlying array or vector"""
        return self._logical_shape
        
    def bounding_box(self):
        return DTRegion3D(np.nanmin(self._x), np.nanmax(self._x), np.nanmin(self._y), np.nanmax(self._y), np.nanmin(self._z), np.nanmax(self._z))
        
    def slice_xy(self, zero_based_slice_index):
        """Slice the grid based on index in the Z dimension."""
        from DTStructuredGrid2D import DTStructuredGrid2D
        if np.shape(self._x)[0] == 1:
            assert np.shape(self._y)[0] == 1, "inconsistent x and y shapes"
            x = np.squeeze(self._x)
            y = np.squeeze(self._y)
            return DTStructuredGrid2D(x, y)
        else:
            x = self._x[zero_based_slice_index,:,:]
            y = self._y[zero_based_slice_index,:,:]
            return DTStructuredGrid2D(x, y)
        
    def __str__(self):
        return self.__dt_type__() + ":\n  Bounding Box: " + str(self.bounding_box()) + "\n  Shape: " + str(self.shape())
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self.bounding_box(), name + "_bbox3D")
        datafile.write_anonymous(self._x, name + "_X")
        datafile.write_anonymous(self._y, name + "_Y")
        datafile.write_anonymous(self._z, name + "_Z")
        datafile.write_anonymous(self._mask, name)
        
    @classmethod
    def from_data_file(self, datafile, name):
        
        # bbox is computed dynamically, so ignore it
        x = datafile[name + "_X"]
        y = datafile[name + "_Y"]
        z = datafile[name + "_Z"]
        
        mask = DTMask.from_data_file(datafile, name)
        return DTStructuredGrid3D(x, y, z, mask=mask)
        
if __name__ == '__main__':
    
    from DTDataFile import DTDataFile
    with DTDataFile("test/structured_grid3d.dtbin", truncate=True) as df:
                
        grid = DTStructuredGrid3D(range(10), range(20), range(5))
        df["grid"] = grid
    
        print grid
        print grid.slice_xy(0)
        

