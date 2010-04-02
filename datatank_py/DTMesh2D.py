#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

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
    
    def __dt_type__(self):
        return "2D Mesh"
        
    def __dt_write__(self, datafile, name):
        
        #
        # 1. Write bounding box as DTRegion2D as "name" + "_bbox2D"
        #    This is a double array with corners ordered (xmin, xmax, ymin, ymax)
        # 2. Write grid using WriteNoSize as "name" + "_loc"
        #    This is a double array with (xmin, ymin, dx, dy)
        # 3. Write mask (ignored for now)
        # 4. Write values as array "name"
        # 5. Write name and type for DataTank
        #
        
        (xmin, ymin, dx, dy) = self._grid 
        xmax = xmin + self._values.shape[1] * float(dx)
        ymax = ymin + self._values.shape[0] * float(dy)

        # will be converted to double arrays
        bbox = (xmin, xmax, ymin, ymax)

        datafile.write_anonymous(bbox, name + "_bbox2D")
        datafile.write_anonymous(self._grid, name + "_loc")
        datafile.write_anonymous(self._values, name)
