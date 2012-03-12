#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import numpy as np
from DTPath2D import DTPath2D

class DTPathValues2D(object):
    """2D Path Values object."""
    
    def __init__(self, path, values):
        super(DTPathValues2D, self).__init__()
        """Create a new 2D Path Values.
        
        Arguments:
        path -- DTPath2D object
        values -- list or vector of values corresponding to each point in the path
        
        Discussion:
        The inputs must have the same length.  Values will be packed to match the
        internal format of DTPath2D.
        
        """
        
        assert path != None and values != None, "DTPathValues2D: both path and values required"
        assert len(path) == len(values), "DTPathValues2D: inconsistent lengths: %s != %s" % (len(path), len(values))
        
        self._path = path
        packed_values = []
        # make slicing and appending to list work
        values = np.asarray(values).tolist()
        start = 0
        for subpath in path:
            packed_values.append(len(subpath))
            packed_values += values[start:start + len(subpath)]
            start += len(subpath)
        self._values = np.asarray(packed_values, dtype=np.double)
        
    def __iter__(self):
        """Iterate subpaths in order of addition as DTPath2D objects"""
        
        start = 1
        for subpath in self._path:
            next = start + len(subpath)
            yield(DTPathValues2D(subpath, self._values[start:next]))
            start = next + 1
        
    def __str__(self):
        s = super(DTPathValues2D, self).__str__() + " {\n"
        start = 1
        for idx, subpath in enumerate(self):
            s += "\n  Subpath %d (%d elements)\n" % (idx, len(subpath))
            for xy, z in zip(subpath._path.point_list(), self._values[start:start + len(subpath)]):
                s += "    (%s, value = %s)\n" % (xy, z)
            start += len(subpath) + 1
        s += "}\n"
        return s
    
    def __len__(self):
        total_length = 0
        for p in self:
            total_length += (len(p._path))
        return total_length

    def __dt_type__(self):
        return "2D Path Values"
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous(self._path, name)
        datafile.write_anonymous(self._values, name + "_V")

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile        
    
    with DTDataFile("path_values_2d.dtbin", truncate=True) as df:
        
        xvalues = (1, 2, 2, 1, 1)
        yvalues = (1, 1, 2, 2, 1)
        zvalues = range(len(yvalues))

        path = DTPath2D(xvalues, yvalues)
        pv = DTPathValues2D(path, zvalues)
        df["Path Values 1"] = pv
        
        print pv
        
        
