#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from DTRegion2D import DTRegion2D
from DTMask import DTMask
import numpy as np

class DTTriangularMesh2D(object):
    """2D triangular mesh object."""
    
    def __init__(self, grid, values):
        super(DTTriangularMesh2D, self).__init__()
        """Create a new 2D triangular mesh.
        
        Arguments:
        grid -- DTTriangularGrid2D object
        values -- vector or list of values
                
        """            
                           
        values = np.squeeze(values)
        assert grid.number_of_points() == len(values)
        self._grid = grid
        self._values = values
    
    def __dt_type__(self):
        return "2D Triangular Mesh"
        
    def bounding_box(self):
        return self._grid.bounding_box()
        
    def __str__(self):
        return self.__dt_type__() + ":\n  grid = " + str(self._grid)
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self._values, name + "_V")
        datafile.write_anonymous(self._grid, name)
        
    @classmethod
    def from_data_file(self, datafile, name):
        
        name = datafile.resolve_name(name)
        values = datafile[name + "_V"]
        grid = datafile[name]
        assert values != None, "DTTriangularMesh2D: no such variable %s in %s" % (name + "_V", datafile.path())
        assert grid != None, "DTTriangularMesh2D: no such variable %s in %s" % (name, datafile)
        return DTStructuredMesh2D(grid, values)

