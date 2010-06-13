#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from DTStructuredGrid3D import DTStructuredGrid3D
import numpy as np

class DTStructuredVectorField3D(object):
    """3D structured vector field object."""
    
    def __init__(self, u, v, w, grid=None):
        super(DTStructuredVectorField3D, self).__init__()
        """Create a new 3D structured vector field.
        
        Arguments:
        u -- 3D array of values
        v -- 3D array of values
        w -- 3D array of values
        grid -- DTStructuredGrid3D object (defaults to unit grid) or the name of a previously saved grid
                
        """                   
        
        shape = np.shape(u)
        assert len(shape) == 3, "values array must be 3D"
        assert np.shape(u) == np.shape(v), "inconsistent array shapes"
        assert np.shape(u) == np.shape(w), "inconsistent array shapes"
        assert np.shape(v) == np.shape(w), "inconsistent array shapes"

        if isinstance(grid, basestring) == False:
            
            if grid == None:
                grid = DTStructuredGrid3D(range(shape[3]), range(shape[1]), range(shape[0]))
            
            assert shape == grid.shape(), "grid shape %s != value shape %s" % (grid.shape(), shape)
            
        self._grid = grid
        self._u = u
        self._v = v
        self._w = w
    
    def __dt_type__(self):
        return "3D Structured Vector Field"
                
    def __str__(self):
        return self.__dt_type__() + ": " + str(self._grid)
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self._u, name + "_VX")
        datafile.write_anonymous(self._v, name + "_VY")
        datafile.write_anonymous(self._w, name + "_VZ")
        datafile.write_anonymous(self._grid, name)

if __name__ == '__main__':
    
    from DTDataFile import DTDataFile
    with DTDataFile("structured_vector_field3d.dtbin", truncate=True) as df:
                
        grid = DTStructuredGrid3D(range(10), range(20), range(5))
        # must order value arrays as z, y, x for compatibility with the grid
        u = np.ones((5, 20, 10))
        v = np.ones((5, 20, 10))
        w = np.ones((5, 20, 10))
        mesh = DTStructuredVectorField3D(u, v, w, grid=grid)
        df["3D vector field"] = mesh
    
        print mesh
        