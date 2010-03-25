#!/usr/bin/env python
# -*- coding: utf-8 -*-

import numpy as np

class DTMesh2D(object):
    """2D Mesh object."""
    
    def __init__(self, values, grid=None):
        super(DTMesh2D, self).__init__()
        """Create a new 2D mesh.
        
        Arguments:
        values -- 2D array of values
        grid -- (xmin, ymin, dx, dy) or None for unit grid
        
        """
        
        # 2D mesh is floating point, either single or double precision
        if values.dtype in (np.int8, np.uint8, np.int16, np.uint16):
            values = values.astype(np.float32)
            
        self._values = values
        self._grid = grid if grid != None else (0, 0, 1, 1)
    
    def dt_type(self):
        return "2D Mesh"
        
    def dt_write(self, datafile, name):
        
        (xmin, ymin, dx, dy) = self._grid 
        xmax = xmin + self._values.shape[1] * float(dx)
        ymax = ymin + self._values.shape[0] * float(dy)

        # will be converted to double arrays
        bbox = (xmin, xmax, ymin, ymax)

        datafile.write_anonymous(bbox, name + "_bbox2D")
        datafile.write_anonymous(self._grid, name + "_loc")
        datafile.write_anonymous(self._values, name)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    
    output_file = DTDataFile("dt_write_test.dtbin", truncate=True)
    output_file.DEBUG = True
    # Create and save a single 2D Mesh.  The mesh_function is kind of
    # unnecessary since you can just multiply xx and yy directly, 
    # but it fits well with using a 2D function + grid in DataTank.
    def mesh_function(x, y):
        return np.cos(x) + np.cos(y)
    
    # return the step to avoid getting fouled up in computing it
    (x, dx) = np.linspace(-10, 10, 50, retstep=True)
    (y, dy) = np.linspace(-10, 10, 100, retstep=True)
    xx, yy = np.meshgrid(x, y)
    mesh = mesh_function(xx, yy)
    
    grid = (np.min(x), np.min(y), dx, dy)
    dtmesh = DTMesh2D(mesh, grid=grid)
    output_file["Test dt_write 2D Mesh"] = dtmesh
    
    output_file.close()