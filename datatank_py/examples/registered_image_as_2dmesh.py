#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import os
import numpy as np
from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTBitmap2D import DTBitmap2D
from time import clock

if __name__ == '__main__':
    
    #
    # This program replaces a standard DataTank External Program module
    # in C++.  Note that it must be executable (chmod 755 in Terminal)
    # and gdal and numpy are required.
    #
    # It takes as input a file path, then loads an image from it, using
    # GDAL to determine the raster origin and pixel size.  The image is
    # then saved as a 2D Mesh object.  Integer 8 and 16-byte images are
    # converted to 32-bit floats. 
    #
    
    input_file = DTDataFile("Input.dtbin")
    image_path = input_file["Image Path"]
    input_file.close()
    
    start_time = clock()
    errors = []
    
    if image_path:
        image_path = os.path.expanduser(image_path)
    if image_path is None or os.path.exists(image_path) is False:
        errors.append("\"%s\" does not exist" % (image_path))
    
    img = DTBitmap2D(image_path)
    if img is None:
        # set an error and bail out; DataTank doesn't appear to use this, but displays
        # stderr output instead, so print them also
        errors.append("Unable to open as an image file")
        with DTDataFile("Output.dtbin", truncate=True) as output_file:
            output_file["ExecutionErrors"] = errors
            output_file["ExecutionTime"] = clock() - start_time
            exit(1)
                        
    with DTDataFile("Output.dtbin", truncate=True) as output_file:
        
        output_file["ExecutionTime"] = clock() - start_time
        output_file["Var"] = img.mesh_from_channel()
                        
        # need to save a StringList of execution errors as Seq_ExecutionErrors
        if len(errors):
            output_file["ExecutionErrors"] = errors