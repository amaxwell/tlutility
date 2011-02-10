#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import sys
from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTBitmap2D import DTBitmap2D

if __name__ == '__main__':
    
    input_file = DTDataFile("Input.dtbin")
    bitmap = DTBitmap2D.from_data_file(input_file, "2D Bitmap")
    projection_name = input_file["Projection"]
    input_file.close()
    
    if bitmap == None or projection_name == None:
        sys.stderr.write("failed to read variables")
        exit(1)
    
    try:
        bitmap.write_geotiff("Output.tiff", projection_name)
    except Exception, e:
        sys.stderr.write("Saving GeoTIFF failed: %s" % (e))
        exit(1)

            