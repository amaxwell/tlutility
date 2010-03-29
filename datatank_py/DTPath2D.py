#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import numpy as np

def _max_bounding_box(a, b):
    (xmin_a, xmax_a, ymin_a, ymax_b) = a
    (xmin_b, xmax_b, ymin_b, ymax_b) = b
    return (np.nanmin(xmin_a, xmin_b), np.nanmax(xmax_a, xmax_b), np.nanmin(ymin_a, ymin_b), np.nanmax(ymax_a, ymax_b))
    
def _bounding_box(xvalues, yvalues):        
    return (np.nanmin(xvalues), np.nanmax(xvalues), np.nanmin(yvalues), np.nanmax(yvalues))

class DTPath2D(object):
    """2D Path object."""
    
    def __init__(self, xvalues, yvalues):
        super(DTPath2D, self).__init__()
        """Create a new 2D Path.
        
        Arguments:
        xvalues -- array of x values
        yvalues -- array of y values
        
        Pass None or an empty array for points to get an empty collection
        that can be added to with add_point().
        
        """
        
        # A polygon class.  The data array has one of two formats
        # 2xN with a packed loop format.
        # 4xN that saves every line segment.
        # 
        # Layout is
        # [ 0 x1 .... xN 0 x1 ... xM ...]
        # [ N y1 .... yN M y1 ... yM ...]
        # This allows multiple loops to be saved in a single array.
        
        assert xvalues != None and yvalues != None, "both x and y arrays are required"
        assert len(xvalues) == len(yvalues), "inconsistent lengths"        
        self._bounding_box = _bounding_box(xvalues, yvalues)
        self._xvalues = np.insert(np.array(xvalues).astype(np.double), 0, 0)
        self._yvalues = np.insert(np.array(yvalues).astype(np.double), 0, len(yvalues))
            
    def bounding_box(self):
        return self._bounding_box
    
    def add_loop(self, xvalues, yvalues):
        assert len(xvalues) == len(yvalues), "inconsistent lengths"
        self._bounding_box = _max_bounding_box(self._bounding_box, _bounding_box(xvalues, yvalues))
        xvalues = np.insert(xvalues, 0, 0)
        yvalues = np.insert(yvalues, 0, len(yvalues))
        self._xvalues = np.append(self._xvalues, xvalues)
        self._yvalues = np.append(self._yvalues, yvalues)
        
    def __str__(self):
        s = "{\n"
        for x, y in zip(self._xvalues, self._yvalues):
            s += "(%s, %s)\n" % (x, y)
        s += "}\n"
        return s
    
    def dt_type(self):
        return "2D Path"
        
    def dt_write(self, datafile, name):
        datafile.write_anonymous(self.bounding_box(), name + "_bbox2D")
        datafile.write_anonymous(np.dstack((self._xvalues, self._yvalues)), name)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    
    with DTDataFile("path_2d.dtbin", truncate=True) as df:
        
        xvalues = (1, 2, 2, 1, 1)
        yvalues = (1, 1, 2, 2, 1)

        df["Path 1"] = DTPath2D(xvalues, yvalues)
        
        xvalues = np.array(xvalues) * 2
        yvalues = np.array(yvalues) * 2
        df["Path 2"] = DTPath2D(xvalues, yvalues)
        
        xvalues = np.linspace(0, 10, num=100)
        yvalues = np.sin(xvalues)
        xvalues = np.append(xvalues, np.flipud(xvalues))
        xvalues = np.append(xvalues, xvalues[0])
        yvalues = np.append(yvalues, -yvalues)
        yvalues = np.append(yvalues, yvalues[0])
        df["Path 3"] = DTPath2D(xvalues, yvalues)
        
        
