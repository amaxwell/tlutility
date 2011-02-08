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
import sys
from DTProgress import DTProgress

class _DTBitmap2D(type):
    def __call__(cls, *args, **kwargs):
        
        obj = None
        path_or_image = args[0] if len(args) else None
        if path_or_image is None:
            cls = DTBitmap2D
            obj = cls.__new__(cls, *args, **kwargs)
            obj.__init__(*args, **kwargs)
        else:
            if isinstance(path_or_image, basestring):
                try:
                    cls = _DTGDALBitmap2D
                    obj = cls.__new__(cls, *args, **kwargs)
                    obj.__init__(*args, **kwargs)
                except Exception, e:
                    sys.stderr.write("Failed to create GDAL representation: %s\n" % (e))
                    obj = None

            if obj == None:
                try:
                    cls = _DTPILBitmap2D
                    obj = cls.__new__(cls, *args, **kwargs)
                    obj.__init__(*args, **kwargs)
                except Exception, e:
                    sys.stderr.write("Failed to create PIL representation: %s\n" % (e))
                    obj = None

        return obj

        
class DTBitmap2D(object):
    """Base implementation for DTBitmap2D.
        
    Arguments:
    path_or_image -- a path to an image file or a PIL image object
    
    Returns:
    A DTBitmap2D object that implements dt_type and dt_write
    
    The argument now defaults to None.  In that case, you'll get back
    an object that implements dt_write, but you are responsible for
    filling in its attributes.  These are:
      • grid -- optional, of the form [x0, y0, dx, dy]
      • red, green, blue -- required for RGB image only
      • gray -- required for grayscale image only
      • alpha -- optional
    Each must be a 2D numpy array, and you are responsible for ensuring
    a consistent shape and proper dimension.  This is basically 
    equivalent to the way DTSource constructs a DTBitmap2D.  Note that 
    DataTank only supports 8 bit and 16 bit images.
    
    If a PIL image is provided, it will be used as-is, and the grid
    will be a unit grid with origin at (0, 0).  If a path is provided,
    DTBitmap2D will try to use GDAL to load the image and extract its
    components, as well as any spatial referencing included with the
    image.  If GDAL fails for any reason, PIL will be used as a fallback.
    
    The object returned is actually a private subclass, and should not
    be relied on.  It will implement the dt_write protocol, so can be
    saved to a DTDataFile.  It also implements mesh_from_channel, whicn
    can be used to extract a given bitmap plane as a DTMesh2D object:
    
    >>> from datatank_py.DTBitmap2D import DTBitmap2D
    >>> img = DTBitmap2D("int16.tiff")
    >>> img.mesh_from_channel()
    <datatank_py.DTMesh2D.DTMesh2D object at 0x101a7a1d0>
    >>> img = DTBitmap2D("rgb_geo.tiff")
    >>> img.mesh_from_channel(channel="red")
    <datatank_py.DTMesh2D.DTMesh2D object at 0x10049ab90>
    
    Note that DTBitmap2D does not attempt to be lazy at loading data; it
    will read the entire image into memory as soon as you instantiate it.
            
    """
    __metaclass__ = _DTBitmap2D
    CHANNEL_NAMES = ("red", "green", "blue", "alpha", "gray")
            
    def __init__(self):
        super(DTBitmap2D, self).__init__()
        self.grid = (0, 0, 1, 1)
        for n in DTBitmap2D.CHANNEL_NAMES:
            setattr(self, n, None)
    
    def __dt_type__(self):
        return "2D Bitmap"
        
    def dtype(self):
        for x in DTBitmap2D.CHANNEL_NAMES:
            v = getattr(self, x)
            if v != None:
                return v.dtype
        return None
        
    def channel_count(self):
        if self.gray != None:
            return 2 if self.alpha != None else 1
        return 4 if self.alpha != None else 3
        
    def has_alpha(self):
        nchan = self.channel_count()
        return nchan == 2 or nchan == 4
        
    def is_gray(self):
        return self.channel_count() < 3
        
    def pil_image(self):
        # #!/usr/bin/env python
        # 
        # from datatank_py.DTBitmap2D import DTBitmap2D
        # from datatank_py.DTDataFile import DTDataFile
        # 
        # if __name__ == '__main__':
        # 
        #     df = DTDataFile("bitmap.dtbin")
        #     bitmap = DTBitmap2D.from_data_file(df, "bitmap")
        #     print bitmap
        # 
        #     img = bitmap.pil_image()
        #     print img
        #     img.save("bitmaptest.png")
        def __transform(values):
            values = np.flipud(values)
            return values.tostring()
        if self.is_gray():
            mode = "L"
            raw_mode = "L"
            data = __transform(self.gray)
            size = np.flipud(self.gray.shape)
            if self.has_alpha():
                raw_mode = "LA"
                data += __transform(self.alpha)
        else:
            mode = "RGB"
            raw_mode = "RGB"
            size = np.flipud(self.red.shape)
            data = __transform(self.red)
            data += __transform(self.green)
            data += __transform(self.blue)
            if self.has_alpha():
                raw_mode += "A"
                data += __transform(self.alpha)
            raw_mode += ";L"
        print "mode=%s, size=%s" % (raw_mode, size)
        if Image != None:
            return Image.fromstring(mode, size, data, "raw", raw_mode, 0, -1)
        return None
        
    def mesh_from_channel(self, channel="gray"):
        import datatank_py.DTMesh2D
        return datatank_py.DTMesh2D.DTMesh2D(getattr(self, channel), grid=self.grid)
        
    def __dt_write__(self, datafile, name):
        
        suffix = "16" if self.dtype() in (np.uint16, np.int16) else ""
        assert self.dtype() not in (np.float64, np.float32), "DataTank does not support floating-point images"
        
        for channel_name in DTBitmap2D.CHANNEL_NAMES:
            values = getattr(self, channel_name)
            if values != None:
                channel_name = channel_name.capitalize() + suffix
                datafile.write_anonymous(values, "_".join((name, channel_name)))
            
        datafile.write_anonymous(self.grid, name)
        
    @classmethod
    def from_data_file(self, datafile, name):
        
        bitmap = DTBitmap2D()
        bitmap.grid = datafile[name]
        for suffix in ("", "16"):
            for channel_name in DTBitmap2D.CHANNEL_NAMES:
                dt_channel_name = "%s_%s%s" % (name, channel_name.capitalize(), suffix)
                values = datafile[dt_channel_name]
                if values != None:
                    setattr(bitmap, channel_name, values)
        return bitmap

class _DTGDALBitmap2D(DTBitmap2D):
    """Private subclass that wraps up the GDAL logic."""
    def __init__(self, image_path):
        
        super(_DTGDALBitmap2D, self).__init__()
        
        # NB: GDAL craps out if you pass a unicode object as a path
        if isinstance(image_path, unicode):
            image_path = image_path.encode(sys.getfilesystemencoding())
            
        dataset = gdal.Open(image_path, GA_ReadOnly)
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
            
            mesh = np.flipud(mesh)

            # we only have one band anyway on this path, so see if we have an indexed image,
            band = dataset.GetRasterBand(1)
            ctab = band.GetRasterColorTable()
            if ctab != None:
                                
                # indexed images have to be expanded to RGB, and this is pretty slow
                progress = DTProgress()
                
                red = np.zeros(mesh.size, dtype=np.uint8)
                green = np.zeros(mesh.size, dtype=np.uint8)
                blue = np.zeros(mesh.size, dtype=np.uint8)
                
                # hash lookup is faster than array lookup by index and
                # faster than calling GetColorEntry for each pixel
                cmap = {}
                for color_index in xrange(min(256, ctab.GetCount())):
                    cmap[int(color_index)] = [np.uint8(x) for x in ctab.GetColorEntry(int(color_index))]
                
                for raster_index, color_index in enumerate(mesh.flatten()):
                    try:
                        (red[raster_index], green[raster_index], blue[raster_index], ignored) = cmap[int(color_index)]
                    except Exception, e:
                        # if not in table, leave as zero
                        pass
                    progress.update_percentage(raster_index / float(mesh.size))

                self.red = np.reshape(red, mesh.shape)
                self.green = np.reshape(green, mesh.shape)
                self.blue = np.reshape(blue, mesh.shape)

                    
            else:
                # Gray (tested with int16)
                self.gray = mesh
            
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
        
class _DTPILBitmap2D(DTBitmap2D):
    """Private subclass that wraps up the PIL logic."""
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
                
