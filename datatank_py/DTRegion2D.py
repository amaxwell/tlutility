#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

class DTRegion2D(object):
    """2D region object."""
    
    def __init__(self, xmin=0, xmax=0, ymin=0, ymax=0):
        super(DTRegion2D, self).__init__()
        """Create a new 2D region (box).
        
        Arguments:
        xmin -- left side x
        xmax -- right side x
        ymin -- bottom y
        ymax -- top y
        
        Arguments are converted to double precision.
        
        """
                    
        self._xmin = float(xmin)
        self._ymin = float(ymin)
        self._xmax = float(xmax)
        self._ymax = float(ymax)
    
    def __dt_type__(self):
        return "2D Region"
        
    def __str__(self):
        return str((self._xmin, self._xmax, self._ymin, self._ymax))
        
    def __dt_write__(self, datafile, name):
        datafile.write_anonymous((self._xmin, self._xmax, self._ymin, self._ymax), name)

if __name__ == '__main__':
    
    from datatank_py.DTDataFile import DTDataFile
    with DTDataFile("region_2d.dtbin", truncate=True) as df:
        
        region = DTRegion2D()
        df["Empty region"] = region
        
        region = DTRegion2D(0, 10, 0, 10)
        df["10 unit region"] = region
    
        print region

