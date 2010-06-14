#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import numpy as np

class DTMask(object):
    """Mask object."""
    
    def __init__(self, mask_values):
        super(DTMask, self).__init__()
        """Create a new mask.
        
        Arguments:
        mask_values -- array of ones and zeroes, covering the full extent of
        the array to be masked.
        
        """
        
        # treat array indexes as the same as in DT, for now
        mask_values = np.array(mask_values, dtype=np.bool)
        mask_shape = mask_values.shape
        
        self._m = mask_shape[0]
        self._n = mask_shape[1] if len(mask_shape) > 1 else 1
        self._o = mask_shape[2] if len(mask_shape) > 2 else 1
        
        m = self._o
        n = self._n
        o = self._m
        
        flat_mask = mask_values.flatten()
        how_many_intervals = 0
        for k in xrange(o):
            for j in xrange(n):
                ijk = j * m + k * n
                until = ijk + m
                while ijk < until:
                    # find the first entry that contains a zero
                    while ijk < until and flat_mask[ijk] == False:
                        ijk += 1
                    if ijk < until:
                        # look for the end
                        while ijk < until and flat_mask[ijk] == True:
                            ijk += 1
                        how_many_intervals += 1
        
        self._intervals = np.zeros((2, how_many_intervals), dtype=np.int32) if how_many_intervals > 0 else np.array([], np.int32)
        location = 0
        for k in xrange(o):
            for j in xrange(n):
                ijk = j * m + k * n
                until = ijk + m
                while ijk < until:
                    # find the first entry that contains a zero
                    while ijk < until and flat_mask[ijk] == False:
                        ijk += 1
                    
                    start = ijk
                    if ijk < until:
                        # look for the end
                        while ijk < until and flat_mask[ijk] == True:
                            ijk += 1
                        
                        self._intervals[0, location] = start
                        self._intervals[1, location] = ijk - 1
                        location += 1                
        
    def __dt_type__(self):
        # ??? not sure if this is correct
        return "Mask"
        
    def __str__(self):
        return super(DTMask, self).__str__()
        
    def __dt_write__(self, datafile, name):
        dims = [self._m, self._n]
        if self._o > 1:
            dims.append(self._o)
        dims.reverse()
        # row/column mismatch (remember that intervals is always 2 x N)
        intervals = self._intervals.swapaxes(0, 1)
        datafile.write_anonymous(np.array(dims, dtype=np.int32), name + "_dim")
        datafile.write_anonymous(intervals, name)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    from datatank_py.DTMesh2D import DTMesh2D
    with DTDataFile("test/mask.dtbin", truncate=True) as df:
        
        def mesh_function(x, y):
            return np.cos(x) + np.cos(y)
            
        mesh_array = np.ones((100,))
        for i in xrange(mesh_array.size):
            mesh_array[i] = i
        mesh_array = mesh_array.reshape((20, 5))
        mask_array = np.zeros((mesh_array.size,), dtype=np.int32)
        for i in xrange(mask_array.size):
            mask_array[i] = 1 if i % 2 else 0
        mask_array = mask_array.reshape(mesh_array.shape)
        
        df["Even-odd mesh"] = DTMesh2D(mesh_array, mask=DTMask(mask_array))
        
        # return the step to avoid getting fouled up in computing it
        (x, dx) = np.linspace(-10, 10, 20, retstep=True)
        (y, dy) = np.linspace(-10, 10, 20, retstep=True)
        xx, yy = np.meshgrid(x, y)
        mesh = mesh_function(xx, yy)

        grid = (np.min(x), np.min(y), dx, dy)
        
        mask_array = np.zeros(mesh.shape)
        mask_array[np.where(mesh < 1)] = 1
        mask = DTMask(mask_array)
        print mesh.shape, mesh.size
        print mask_array.shape, mask_array.size
        dtmesh = DTMesh2D(mesh, grid=grid, mask=mask)
        df["Masked mesh"] = dtmesh
        