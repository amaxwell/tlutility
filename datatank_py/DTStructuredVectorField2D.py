#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from DTStructuredGrid2D import DTStructuredGrid2D
import numpy as np

class DTStructuredVectorField2D(object):
    """2D structured vector field object."""
    
    def __init__(self, u, v, grid=None):
        super(DTStructuredVectorField2D, self).__init__()
        """Create a new 2D structured vector field.
        
        Arguments:
        u -- 2D array of values
        v -- 2D array of values
        grid -- DTStructuredGrid2D object (defaults to unit grid) or the name of a previously saved grid
        
        Note that the u, v arrays must be ordered as (y, x) for compatibility
        with the grid and DataTank.
                        
        """                   
        
        shape = np.shape(u)
        assert len(shape) == 2, "values array must be 2D"
        assert np.shape(u) == np.shape(v), "inconsistent array shapes"

        if isinstance(grid, basestring) == False:
            
            if grid == None:
                grid = DTStructuredGrid2D(range(shape[1]), range(shape[0]))
            
            assert shape == grid.shape(), "grid shape %s != value shape %s" % (grid.shape(), shape)
            
        self._grid = grid
        self._u = u
        self._v = v
    
    def __dt_type__(self):
        return "2D Structured Vector Field"
                
    def __str__(self):
        return self.__dt_type__() + ": " + str(self._grid)
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self._u, name + "_VX")
        datafile.write_anonymous(self._v, name + "_VY")
        datafile.write_anonymous(self._grid, name)

if __name__ == '__main__':
    
    from DTDataFile import DTDataFile
    with DTDataFile("test/structured_vector_field2d.dtbin", truncate=True) as df:
                
        grid = DTStructuredGrid2D(range(20), range(10))
        # must order value arrays as z, y, x for compatibility with the grid
        u = np.ones((10, 20))
        v = np.ones((10, 20))
        mesh = DTStructuredVectorField2D(u, v, grid=grid)
        df["2D vector field"] = mesh
    
        print mesh
