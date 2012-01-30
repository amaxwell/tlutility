#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import os, sys
from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTMesh2D import DTMesh2D
from time import time

from osgeo import gdal
from osgeo import osr
from osgeo.gdalconst import GDT_Float32
import numpy as np
                     
if __name__ == '__main__':
    
    input_file = DTDataFile("Input.dtbin")
    mesh = DTMesh2D.from_data_file(input_file, "Mesh")
    projection_name = input_file["Projection"].encode("utf-8")
    # may be None if no mask present
    mask_value = input_file["Mask value"] 
    input_file.close()
    
    if mesh == None or projection_name == None:
        sys.stderr.write("failed to read variables")
        exit(1)
        
    values = mesh.values().astype(np.float32)

    if mesh.mask() != None:
        if mask_value == None:
            sys.stderr.write("mesh has a mask")
            exit(1)
        values = np.where(mesh.mask() != 0, values, mask_value)
            
    # transform in DTBitmap2D
    values = np.flipud(values)

    # transform in DTDataFile
    shape = list(values.shape)
    shape.reverse()
    values = values.reshape(shape, order="C")
    
    (raster_x, raster_y) = values.shape
    
    # base transform
    grid = mesh.grid()
    (xmin, dx, rot1, ymax, rot2, dy) = (0, 0, 0, 0, 0, 0)
    xmin = grid[0]
    dx = grid[2]
    dy = grid[3]
    ymax = grid[1] + abs(dy) * raster_y

    # 2D mesh only has a single output band
    band_count = 1
    geotiff = gdal.GetDriverByName("GTiff")

    dst = geotiff.Create("Output.tiff", raster_x, raster_y, bands=band_count, eType=GDT_Float32)
    
    # Recall that dx and dy are signed, with positive upwards;
    # this is bizarre, but http://www.gdal.org/gdal_tutorial.html
    # shows it also.
    dst.SetGeoTransform((xmin, dx, rot1, ymax, rot2, -abs(dy)))
    dst_srs = osr.SpatialReference()
    dst_srs.SetFromUserInput(projection_name)
    dst.SetProjection(dst_srs.ExportToWkt())
    
    band = dst.GetRasterBand(1)
    
    # make sure I didn't screw this up somewhere...
    assert values.dtype == np.float32
    data = values.tostring()
    band.WriteRaster(0, 0, dst.RasterXSize, dst.RasterYSize, data, buf_xsize=dst.RasterXSize, buf_ysize=dst.RasterYSize, buf_type=band.DataType)
        
    dst = None

