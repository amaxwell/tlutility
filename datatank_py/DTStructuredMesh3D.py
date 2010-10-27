#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from DTStructuredGrid3D import DTStructuredGrid3D
import numpy as np

class DTStructuredMesh3D(object):
    """3D structured mesh object."""
    
    def __init__(self, values, grid=None):
        super(DTStructuredMesh3D, self).__init__()
        """Create a new 3D structured mesh.
        
        Arguments:
        values -- 3D array of values
        grid -- DTStructuredGrid3D object (defaults to unit grid) or the name of a previously saved grid
        
        Note that the values array must be ordered as (z, y, x) for compatibility
        with the grid and DataTank.
                
        """                   
        
        shape = np.shape(values)
        assert len(shape) == 3, "values array must be 3D"

        if isinstance(grid, basestring) == False:
            
            if grid == None:
                grid = DTStructuredGrid3D(range(shape[3]), range(shape[1]), range(shape[0]))
            
            assert shape == grid.shape(), "grid shape %s != value shape %s" % (grid.shape(), shape)
            
        self._grid = grid
        self._values = values
    
    def __dt_type__(self):
        return "3D Structured Mesh"
                
    def __str__(self):
        return self.__dt_type__() + ": " + str(self._grid)
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self._grid, name)
        datafile.write_anonymous(self._values, name + "_V")

if __name__ == '__main__':
    
    from DTDataFile import DTDataFile
    with DTDataFile("test/structured_mesh3d.dtbin", truncate=True) as df:
                
        grid = DTStructuredGrid3D(range(10), range(20), range(5))
        values = np.zeros(10 * 20 * 5)
        for i in xrange(len(values)):
            values[i] = i
            
        # DataTank indexes differently from numpy; the grid is z,y,x ordered
        values = values.reshape((5, 20, 10))
        
        mesh = DTStructuredMesh3D(values, grid=grid)
        df["3D mesh"] = mesh
    
        print mesh
        