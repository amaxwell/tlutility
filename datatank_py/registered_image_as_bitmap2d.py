#!/usr/bin/env python

import os
import numpy as np
from osgeo import gdal
from osgeo.gdalconst import GA_ReadOnly
from datatank_py.DTDataFile import DTDataFile
from time import clock

if __name__ == '__main__':
    
    input_file = DTDataFile("Input.dtbin")
    image_path = input_file["Image Path"]
    input_file.close()
    
    start_time = clock()
    errors = []
    
    if image_path:
        image_path = os.path.expanduser(image_path)
    if image_path is None or os.path.exists(image_path) is False:
        errors.append("\"%s\" does not exist" % (image_path))
    
    dataset = None if image_path is None else gdal.Open(str(image_path), GA_ReadOnly)
    if dataset is None:
        # set an error and bail out; DataTank doesn't appear to use this, but displays
        # stderr output instead, so print them also
        errors.append("Unable to open as an image file")
        with DTDataFile("Output.dtbin", truncate=True) as output_file:
            output_file["ExecutionErrors"] = errors
            output_file["ExecutionTime"] = clock() - start_time
            exit(1)

    (xmin, dx, rot1, ymax, rot2, dy) = dataset.GetGeoTransform()
    mesh = dataset.ReadAsArray()
    ymin = ymax + dy * mesh.shape[-1]
    grid = (xmin, ymin, dx, abs(dy))
    suffix = "16" if mesh.dtype in (np.int16, np.uint16) else ""
                    
    with DTDataFile("Output.dtbin", truncate=True) as output_file:
        
        # The normal write_array doesn't help with composite types,
        # so we have to drop to the low-level string writing in order
        # to avoid naming this "Var" and relying on DTDataFile to change
        # the name to "Seq_Var" (since we need the name "Var" later).
        output_file._write_string("2D Bitmap", "Seq_Var")
        output_file["ExecutionTime"] = clock() - start_time
        
        # e.g., (3, 900, 1440) for an RGB
        if len(mesh.shape) == 3:

            channel_count = mesh.shape[0]
            name_map = {}
            
            if channel_count == 2:
                # Gray + Alpha
                name_map = {0:"Gray", 1:"Alpha"}

            elif channel_count == 3:
                # RGB (tested with screenshot)
                name_map = {0:"Red", 1:"Green", 2:"Blue"}

            elif channel_count == 4:
                # RGBA
                name_map = {0:"Red", 1:"Green", 2:"Blue", 3:"Alpha"}

            for idx in name_map:
                channel = np.flipud(mesh[idx,:])
                output_file["Var_" + name_map[idx] + suffix] = channel

        elif len(mesh.shape) == 2:

            # Gray (tested with int16)
            output_file["Var_Gray"] = np.flipud(mesh) 
            
        else:
            errors.append("Unhandled mesh shape: %s" % (mesh.shape))
        
        print output_file.variable_names()
        # Here again, we have to use low-level writing to avoid a name
        # conflict, since the high-level methods will write a "Seq_Var"
        # to expose the variable (and conflict with the previous name).
        output_file._write_array(grid, "Var")
                        
        # need to save a StringList of execution errors as Seq_ExecutionErrors
        if len(errors):
            output_file["ExecutionErrors"] = errors
