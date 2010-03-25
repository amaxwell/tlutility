#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from __future__ import with_statement
import os
import numpy as np
from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTMesh2D import DTMesh2D
from datatank_py.DTBitmap2D import DTBitmap2D

def write_2dmeshes(file_path):
    
    output_file = DTDataFile(file_path)
    output_file.DEBUG = True
    
    # Create and save a single 2D Mesh.  The mesh_function is kind of
    # unnecessary since you can just multiply xx and yy directly, 
    # but it fits well with using a 2D function + grid in DataTank.
    def mesh_function(x, y):
        return np.cos(x) + np.cos(y)
    
    # return the step to avoid getting fouled up in computing it
    (x, dx) = np.linspace(-10, 10, 50, retstep=True)
    (y, dy) = np.linspace(-10, 10, 100, retstep=True)
    xx, yy = np.meshgrid(x, y)
    mesh = mesh_function(xx, yy)
    
    grid = (np.min(x), np.min(y), dx, dy)
    dtmesh = DTMesh2D(mesh, grid=grid)
    
    output_file["TestMesh"] = dtmesh
    output_file.close()
    
    # write to a separate file also
    with DTDataFile("mesh.dtbin", truncate=True) as mesh_file:
        mesh_file["TestMesh"] = dtmesh
    
    # use GDAL to load a 16 bit GeoTIFF file and display it as a 2D mesh
    with DTDataFile("mesh.dtbin") as mesh_file:
        try:
            mesh_file["Image from GDAL"] = DTBitmap2D("../examples/int16.tiff").mesh_from_channel()
        except Exception, e:
            print "failed to load or write image as mesh:", e    

def write_images(file_path):
            
    output_file = DTDataFile(file_path)
    output_file.DEBUG = True
    # write a single bitmap image (requires PIL)
    try:
        from PIL import Image
        image_path = None
        if os.path.exists("/Library/Desktop Pictures/Art/Poppies Blooming.jpg"):
            image_path = "/Library/Desktop Pictures/Art/Poppies Blooming.jpg"
        else:
            image_path = "/Library/Desktop Pictures/Nature/Earth Horizon.jpg"

        output_file["Image"] = DTBitmap2D(image_path)
    
        # add an alpha channel and save the new image
        image = Image.open(image_path)
        image.putalpha(200)
        output_file["ImageAlpha"] = DTBitmap2D(image)
        
    except Exception, e:
        print "failed to load or write image:", e

    output_file.close()
    
def write_arrays(file_path):
    
    output_file = DTDataFile(file_path)
    output_file.DEBUG = True
    
    # write a 1D array of shorts using the dictionary interface
    test_array = np.array(range(0, 10), dtype=np.int16)
    output_file["Test0"] = test_array
    
    read_array = output_file["Test0"]
    assert np.all(test_array == read_array), "failed 1D int16 array test"
    
    # write a Python list
    output_file.write([0, 10, 5, 7, 9], "TestPythonList")
    
    # write a single number
    value = 10.5
    output_file.write(value, "TestRealNumber")
    
    read_value = output_file["TestRealNumber"]
    assert value == read_value, "failed real number test"
    
    # write a 2D array of ints
    test_array = np.array(range(0, 10), dtype=np.int32)
    test_array = test_array.reshape((5, 2))
    output_file.write_array(test_array, "Test1", dt_type="Array")
    
    read_array = output_file["Test1"]
    assert np.all(test_array == read_array), "failed 2D int32 array test"
    
    # write a 2D array of doubles
    test_array = test_array.astype(np.float64)
    test_array /= 2.3
    output_file.write_array(test_array, "Test2", dt_type="Array")
    
    read_array = output_file["Test2"]
    assert np.all(test_array == read_array), "failed 2D double array test"
    
    # write a 3D array of floats
    test_array = np.array(range(0, 12), dtype=np.float)
    test_array = test_array.reshape(3, 2, 2)
    output_file.write_array(test_array, "Test3", dt_type="Array")
    
    read_array = output_file["Test3"]
    assert np.all(test_array == read_array), "failed 3D float array test"
    
    # write a list of floats
    test_array = np.array(range(0, 12), dtype=np.float32)
    output_file["Test4"] = test_array
    
    read_array = output_file["Test4"]
    assert np.all(test_array == read_array), "failed list of floats test"
    
    
    output_file.close()

def write_test(file_path):
    
    assert os.path.exists(file_path) is False, "delete file before running tests"
    
    # 
    # Note: I tried creating the file here and keeping it open while calling the
    # following functions, but that failed horribly and caused an inconsistent file.
    # Summary: having these open at the same time will cause problems.  Maybe I should
    # add a table of open files or something, and force subsequent access as read-only?
    #
        
    write_2dmeshes(file_path)
    write_images(file_path)
    write_arrays(file_path)
        
    output_file = DTDataFile(file_path, truncate=False)    
    output_file.DEBUG = True
    
    # write a time-varying 1D array (list of numbers)
    for idx in xrange(0, 10):
        time_test = np.array(range(idx, idx + 10), np.double)
        output_file.write(time_test, "TimeTest_%d" % (idx), time=idx * 2.)
    
    # write a single string
    string = "Test single string"
    output_file.write(string, "TestSingleString")
    assert string == output_file["TestSingleString"], "failed string test"

    # write a time-varying string with Unicode characters
    for idx in xrange(0, 10):
        output_file.write_string(u"Χριστός : time index %d" % (idx), "StringTest_%d" % (idx), time=idx * 2.)
        
    string_list = ["First String", "Second String", "Third String"]
    output_file.write(string_list, "TestStringList")
        
    # write a time-varying 2D point collection
    for idx in xrange(0, 10):
        point_test = np.array(range(idx, idx + 10), np.double)
        point_test = point_test.reshape((point_test.size / 2, 2))
        output_file.write_array(point_test, "PointTest_%d" % (idx), dt_type="2D Point Collection", time=idx * 2.)
            
    output_file.close()   

def read_test(file_path):
    
    f = DTDataFile(file_path)
    f.DEBUG = True
    print f
    for name in f:
        # Call this to make sure the variables are actually read, since that will
        # potentially have numerous side effects.  Printing this is overwhelming.
        ignored = f[name]
        
    f.close()
        
if __name__ == '__main__':
    
    if os.path.exists("test.dtbin"):
        os.remove("test.dtbin")
    write_test("test.dtbin")
    read_test("test.dtbin")
    read_test("mesh.dtbin")