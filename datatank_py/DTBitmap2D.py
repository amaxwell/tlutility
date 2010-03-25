#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

try:
    from PIL import Image
except Exception, e:
    pass
try:
    from osgeo import gdal
    from osgeo.gdalconst import GA_ReadOnly
except Exception, e:
    pass
import numpy as np

class _DTBitmap2D(object):
    """docstring for DTBitmap2D"""
    
    CHANNEL_NAMES = ("red", "green", "blue", "alpha", "gray")
            
    def __init__(self):
        super(_DTBitmap2D, self).__init__()
        self.grid = (0, 0, 1, 1)
        for n in _DTBitmap2D.CHANNEL_NAMES:
            setattr(self, n, None)
    
    def dt_type(self):
        return "2D Bitmap"
        
    def dtype(self):
        for x in _DTBitmap2D.CHANNEL_NAMES:
            v = getattr(self, x)
            if v != None:
                return v.dtype
        return None
        
    def mesh_from_channel(self, channel="gray"):
        import datatank_py.DTMesh2D
        return datatank_py.DTMesh2D.DTMesh2D(getattr(self, channel), grid=self.grid)
        
    def dt_write(self, datafile, name):
        
        suffix = "16" if self.dtype() in (np.uint16, np.int16) else ""
        assert self.dtype() not in (np.float64, np.float32), "DataTank does not support floating-point images"
        
        for channel_name in _DTBitmap2D.CHANNEL_NAMES:
            values = getattr(self, channel_name)
            if values != None:
                channel_name = channel_name.capitalize() + suffix
                datafile.write_anonymous(values, "_".join((name, channel_name)))
            
        datafile.write_anonymous(self.grid, name)

class _DTGDALBitmap2D(_DTBitmap2D):
    """docstring for DTGDALBitmap2D"""
    def __init__(self, image_path):
        
        super(_DTGDALBitmap2D, self).__init__()
                
        dataset = gdal.Open(str(image_path), GA_ReadOnly)
        (xmin, dx, rot1, ymax, rot2, dy) = dataset.GetGeoTransform()
        mesh = dataset.ReadAsArray()
        ymin = ymax + dy * dataset.RasterYSize
        self.grid = (xmin, ymin, dx, abs(dy))
        
        # e.g., (3, 900, 1440) for an RGB
        if len(mesh.shape) == 3:

            channel_count = mesh.shape[0]
            name_map = {}
            
            if channel_count == 2:
                # Gray + Alpha
                name_map = {0:"gray", 1:"alpha"}

            elif channel_count == 3:
                # RGB (tested with screenshot)
                name_map = {0:"red", 1:"green", 2:"blue"}

            elif channel_count == 4:
                # RGBA
                name_map = {0:"red", 1:"green", 2:"blue", 3:"alpha"}

            for idx in name_map:
                channel = np.flipud(mesh[idx,:])
                setattr(self, name_map[idx], channel)

        elif len(mesh.shape) == 2:

            # Gray (tested with int16)
            self.gray = np.flipud(mesh)
            
        del dataset

def _array_from_image(image):
    """Convert a PIL image to a numpy ndarray.
    
    Arguments:
    image -- a PIL image instance
    
    Returns:
    a numpy ndarray or None if an error occurred
    
    """
    
    array = None
    if image.mode.startswith(("I", "F")):
        
        def _parse_mode(mode):
            # Modes aren't very well documented, and I see results that
            # differ from the documentation.  They seem to follow this:
            # http://www.pythonware.com/library/pil/handbook/decoder.htm
            suffix = mode.split(";")[-1]
            np_type = ""
            if suffix != mode:
                mode_size = ""
                mode_fmt = ""
                for c in suffix:
                    if c.isdigit():
                        mode_size += c
                    else:
                        mode_fmt += c
                if mode_fmt.startswith("N") is False:
                    # big-endian if starts with B, little otherwise
                    np_type += ">" if mode_fmt.startswith("B") else "<"
                if mode_fmt.endswith("S"):
                    # signed int
                    np_type += "i"
                else:
                    # float or unsigned int
                    np_type += "f" if mode.endswith("F") else "u"
                # convert to size in bytes
                np_type += str(int(mode_size) / 8)
            elif mode == "F":
                np_type = "f4"
            elif mode == "I":
                np_type = "i4"
            else:
                return None
            return np.dtype(np_type)
        
        dt = _parse_mode(image.mode)
        if dt is None:
            print "unable to determine image bit depth and byte order for mode \"%s\"" % (image.mode)
        else:
            try:
                # fails for signed int16 images produced by GDAL, but works with unsigned
                array = np.fromstring(image.tostring(), dtype=dt)
                array = array.reshape((image.size[1], image.size[0]))
            except Exception, e:
                print "image.tostring() failed for image with mode \"%s\" (PIL error: %s)" % (image.mode, str(e))
        
    else:    
        # doesn't seem to work reliably for GDAL-produced 16 bit GeoTIFF
        array = np.asarray(image)
    
    return array
        
class _DTPILBitmap2D(_DTBitmap2D):
    """docstring for DTPILBitmap2D"""
    def __init__(self, image_or_path):
        
        super(_DTPILBitmap2D, self).__init__()
        
        image = Image.open(image_or_path) if isinstance(image_or_path, basestring) else image_or_path
        
        array = _array_from_image(image)
        assert array is not None, "unable to convert the image to a numpy array"
        assert array.dtype in (np.int16, np.uint16, np.uint8, np.int8, np.bool), "unsupported bit depth"
                
        if image.mode in ("1", "P", "L", "LA") or image.mode.startswith(("F", "I")):

            # Convert binary image of dtype=bool to uint8, although this is probably
            # a better candidate for a or use as a mask.
            if image.mode == "1":
                print "warning: converting binary image to uint8"
                # TODO: this crashes when I test it with a binary TIFF, but it looks like a
                # bug in numpy or PIL.  Strangely, it doesn't crash if I copy immediately after
                # calling asarray above.
                array = array.copy().astype(np.uint8)
                array *= 255

            if image.mode in ("1", "L", "P") or image.mode.startswith(("F", "I")):
                self.gray = np.flipud(array)
            else:
                assert image.mode == "LA", "requires gray + alpha image"
                self.gray = np.flipud(array[:,0])
                self.alpha = np.flipud(array[:,1])

        elif image.mode in ("RGB", "RGBA"):

            self.red = np.flipud(array[:,:,0])
            self.green = np.flipud(array[:,:,1])
            self.blue = np.flipud(array[:,:,2])
            if image.mode == "RGBA":
                self.alpha = np.flipud(array[:,:,3])
        
        del image
                
def DTBitmap2D(path_or_image):
    
    obj = None
    if isinstance(path_or_image, basestring):
        try:
            obj = _DTGDALBitmap2D(path_or_image)
        except Exception, e:
            print "Failed to create GDAL representation:", e
            obj = None
    
    if obj == None:
        try:
            obj = _DTPILBitmap2D(path_or_image)
        except Exception, e:
            print "Failed to create PIL representation:", e
            obj = None
            
    return obj
