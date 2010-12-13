#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import numpy as np
from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTMesh2D import DTMesh2D
        
if __name__ == '__main__':
    
    output_file = DTDataFile("dg_mesh_test.dtbin", truncate=True)
    output_file.DEBUG = True
    
    # Create and save a single 2D Mesh.  The mesh_function is kind of
    # unnecessary since you can just multiply xx and yy directly, 
    # but it fits well with using a 2D function + grid in DataTank.
    def mesh_function(x, y, t):
        return np.cos(x / float(t+1) * 10) + np.cos(y + t)
    
    # return the step to avoid getting fouled up in computing it
    (x, dx) = np.linspace(-10, 10, 50, retstep=True)
    (y, dy) = np.linspace(-10, 10, 100, retstep=True)
    xx, yy = np.meshgrid(x, y)
    grid = (np.min(x), np.min(y), dx, dy)    
    
    # time indexes must start at 0
    for idx, time in enumerate(np.arange(0, 20, 2, dtype=np.double)):
        mesh = mesh_function(xx, yy, time)
        dtmesh = DTMesh2D(mesh, grid=grid)
        output_file.write(dtmesh, "Test Mesh_%d" % (idx), time=time)
        
    output_file.close()
