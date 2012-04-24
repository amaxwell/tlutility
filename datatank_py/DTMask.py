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
        
        # in Python order (zyx), same as a mesh values array
        mask_values = np.array(mask_values, dtype=np.bool)
        mask_shape = list(mask_values.shape)
        
        # switch to DataTank order for indexing compatibility
        mask_shape.reverse()
        mask_values = mask_values.reshape(mask_shape)
        
        # set nonexistent dims to unity for compatibility with DataTank
        self._m = mask_shape[0]
        self._n = mask_shape[1] if len(mask_shape) > 1 else 1
        self._o = mask_shape[2] if len(mask_shape) > 2 else 1
        
        m = self._m
        n = self._n
        o = self._o
        
        # This costs us some memory, but it's a big gain for large masks
        # since the iteration/comparison of numpy arrays is really slow,
        # and it seems to spend a lot of time in PyObject_HashNotImplemented.
        flat_mask = mask_values.flatten().tolist()
        iv0 = []
        iv1 = []
        location = 0
        for k in xrange(o):
            for j in xrange(n):
                ijk = j * m + k * n * m
                until = ijk + m
                while ijk < until:
                    # find the first entry that contains a zero
                    while ijk < until and flat_mask[ijk] == 0:
                        ijk += 1
                    start = ijk
                    if ijk < until:
                        # look for the end
                        while ijk < until and flat_mask[ijk] != 0:
                            ijk += 1
                        
                        iv0.append(start)
                        iv1.append(ijk - 1)
                        location += 1       
        
        if len(iv0):
            self._intervals = np.zeros((2, len(iv0)), dtype=np.int32)
            self._intervals[0,:] = iv0
            self._intervals[1,:] = iv1
        else:
            self._intervals = np.array([], np.int32)
        # row/column mismatch (remember that intervals is always 2 x N)
        self._intervals = self._intervals.swapaxes(0, 1)
        
    def __dt_type__(self):
        # ??? not sure if this is correct
        return "Mask"
        
    def m(self):
        return self._m
        
    def n(self):
        return self._n
        
    def o(self):
        return self._o
        
    def __str__(self):
        return super(DTMask, self).__str__()
        
    def __dt_write__(self, datafile, name):
        dims = [self._m, self._n]
        if self._o > 1:
            dims.append(self._o)

        datafile.write_anonymous(np.array(dims, dtype=np.int32), name + "_dim")
        datafile.write_anonymous(self._intervals, name)
        
    def mask_array(self):
        """Returns a full uint8 mask array in the original mask shape"""
        dims = [self._m, self._n]
        if self._o > 1:
            dims.append(self._o)
        mask_array = np.zeros(dims, dtype=np.uint8).flatten()
        if len(mask_array) == 0:
            return mask_array.reshape(dims)
        for start, end in zip(self._intervals[:,0], self._intervals[:,1]):
            for j in xrange(start,end + 1):
                mask_array[j] = True

        dims.reverse()
        return mask_array.reshape(dims)
        
    @classmethod
    def from_data_file(self, datafile, name):
        """Instantiates a DTMask from a DTDataFile with the given variable name"""
        intervals = datafile[name]
                
        # return None if there is no mask
        if intervals == None or len(intervals) == 0:
            return None
            
        dims = datafile[name + "_dim"].tolist()
        if len(dims) == 2:
            dims.append(0)
        mask = DTMask(np.array([]))
        mask._intervals = intervals
        mask._m = dims[0]
        mask._n = dims[1]
        mask._o = dims[2]
        
        return mask

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    from datatank_py.DTMesh2D import DTMesh2D
    from datatank_py.DTStructuredGrid3D import DTStructuredGrid3D
    from datatank_py.DTStructuredMesh2D import DTStructuredMesh2D
    from datatank_py.DTStructuredGrid2D import DTStructuredGrid2D

    with DTDataFile("test/mask.dtbin", truncate=True) as df:
        
        mesh_array = np.ones((100,))
        for i in xrange(mesh_array.size):
            mesh_array[i] = i
        mesh_array = mesh_array.reshape((20, 5))
        mask_array = np.zeros((mesh_array.size,), dtype=np.int32)
        for i in xrange(mask_array.size):
            mask_array[i] = 1 if i % 2 else 0
        mask_array = mask_array.reshape(mesh_array.shape)
        
        df["Even-odd mesh"] = DTMesh2D(mesh_array, mask=DTMask(mask_array))
        
        def mesh_function(x, y):
             return np.cos(x) + np.cos(y)
        
        # return the step to avoid getting fouled up in computing it
        (x, dx) = np.linspace(-10, 10, 80, retstep=True)
        (y, dy) = np.linspace(-20, 20, 120, retstep=True)
        xx, yy = np.meshgrid(x, y)
        mesh = mesh_function(xx, yy)
        
        grid = (np.min(x), np.min(y), dx, dy)
                
        mask_array = np.zeros(mesh.shape, dtype=np.int8)
        mask_array[np.where(mesh < 1)] = 1
        mask = DTMask(mask_array)
        
        new_mask = mask.mask_array()
        assert new_mask.shape == mask_array.shape, "shape %s != %s" % (new_mask.shape, mask_array.shape)
        assert np.sum(new_mask - mask_array) == 0, "inconsistent mask array computed"

        grid2ds = DTStructuredGrid2D(x, y, mask=mask)
        df["Holy sgrid"] = grid2ds
        df["Holy smesh"] = DTStructuredMesh2D(mesh, grid=grid2ds)

        dtmesh = DTMesh2D(mesh, grid=grid, mask=mask)
        df["Holy mesh"] = dtmesh
        
        m, n, o = (10, 8, 6)
        mask_array = np.ones(m * n * o)
        for i in xrange(mask_array.size):
            mask_array[i] = 1 if i % 2 else 0
            
        # mask dimension order should be consistent with array value order
        mask_array = mask_array.reshape((o, n, m))
        mask = DTMask(mask_array)
        
        new_mask = mask.mask_array()
        assert new_mask.shape == mask_array.shape, "shape %s != %s" % (new_mask.shape, mask_array.shape)
        assert np.sum(new_mask - mask_array) == 0, "inconsistent mask array computed"
        
        grid = DTStructuredGrid3D(range(m), range(n), range(o), mask=mask)
        df["3D grid masked"] = grid

