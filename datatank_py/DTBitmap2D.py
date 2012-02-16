#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

try:
    from PIL import Image
except Exception, e:
    Image = None
    pass
try:
    from osgeo import gdal, osr
    # throw instead of printing to stderr
    gdal.UseExceptions()
    osr.UseExceptions()
    from osgeo.gdalconst import GA_ReadOnly, GDT_UInt16, GDT_Byte
except Exception, e:
    gdal = None
    osr = None
    pass
import numpy as np
import sys
from DTProgress import DTProgress

class _DTBitmap2D(type):
    """Metaclass of DTBitmap2D which implements __call__ in order to
    return a private subclass based on input arguments.  First argument 
    is a path or PIL image, or None.  Returns None if PIL and GDAL fail, 
    which may or may not be correct.
    """
    def __call__(cls, *args, **kwargs):
        
        obj = None
        path_or_image = args[0] if len(args) else None
        if path_or_image is None:
            cls = DTBitmap2D
            obj = cls.__new__(cls, *args, **kwargs)
            obj.__init__(*args, **kwargs)
        else:
            # a string must be a path, so try GDAL first
            if isinstance(path_or_image, basestring):
                try:
                    cls = _DTGDALBitmap2D
                    obj = cls.__new__(cls, *args, **kwargs)
                    obj.__init__(*args, **kwargs)
                except Exception, e:
                    sys.stderr.write("Failed to create GDAL representation: %s\n" % (e))
                    obj = None
            
            # if GDAL failed or we had a PIL image, try PIL
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
        
    Provides implementation of DTPyWrite for all subclasses, and
    can be instantiated directly to use as a container.
            
    """
    
    __metaclass__ = _DTBitmap2D
    CHANNEL_NAMES = ("red", "green", "blue", "alpha", "gray")
            
    def __init__(self, path_or_image=None):
        """Initializes a new DTBitmap2D object.
        
        Arguments:
        path_or_image -- a path to an image file or a PIL image object

        Returns:
        An object that implements DTPyWrite.  It maybe DTBitmap2D or one
        of the private subclasses.  Don't rely on the class for anything.

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

        Note that DTBitmap2D does not attempt to be lazy at loading data; it
        will read the entire image into memory as soon as you instantiate it.
        
        """
        super(DTBitmap2D, self).__init__()
        self.grid = (0, 0, 1, 1)
        self.nodata = None
        for n in DTBitmap2D.CHANNEL_NAMES:
            setattr(self, n, None)
    
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
        """Attempt to convert a raw image to a PIL Image object
        
        Returns:
        A PIL Image, or None if PIL can't be loaded or if the conversion failed.
        Only tested with 8-bit images, but gray/gray+alpha and RGB/RGBA
        have all been tested.
        
        """
        
        if Image == None:
            return None
            
        if self.is_gray():
            mode = "L"
            raw_mode = mode
            channels = [self.gray]
            if self.has_alpha():
                mode = "LA"
                raw_mode = "LA;L"
                channels.append(self.alpha)
        else:
            mode = "RGB"
            raw_mode = mode
            channels = [self.red, self.green, self.blue]
            if self.has_alpha():
                mode = "RGBA"
                raw_mode += "A"
                channels.append(self.alpha)
            raw_mode += ";L"
        
        size = np.flipud(channels[0].shape)
        data = np.hstack(channels).tostring()
        return Image.fromstring(mode, size, data, "raw", raw_mode, 0, -1)
        
    def mesh_from_channel(self, channel="gray"):
        """Extract a given bitmap plane as a DTMesh2D object.
        
        Arguments:
        channel -- defaults to gray, but may be one of (red, green, blue, gray, alpha)
        
        Returns:
        A 2D Mesh object, which uses the grid of the image.

        >>> from datatank_py.DTBitmap2D import DTBitmap2D
        >>> img = DTBitmap2D("int16.tiff")
        >>> img.mesh_from_channel()
        <datatank_py.DTMesh2D.DTMesh2D object at 0x101a7a1d0>
        >>> img = DTBitmap2D("rgb_geo.tiff")
        >>> img.mesh_from_channel(channel="red")
        <datatank_py.DTMesh2D.DTMesh2D object at 0x10049ab90>
        
        """
        
        from datatank_py.DTMesh2D import DTMesh2D
        from datatank_py.DTMask import DTMask
        values = getattr(self, channel)
        mask = None
        if self.nodata != None:
            mask_array = np.zeros(values.shape, dtype=np.int8)
            mask_array[np.where(values != self.nodata)] = 1
            mask = DTMask(mask_array)
        return DTMesh2D(values, grid=self.grid, mask=mask)
        
    def raster_size(self):
        """Size in pixels, 2-tuple ordered as (horizontal, vertical)."""
        shape = self.gray.shape if self.is_gray() else self.red.shape
        return tuple(reversed(shape))
        
    def write_geotiff(self, output_path, projection_name):
        """Save a DTBitmap2D as a GeoTIFF file.
        
        Arguments:
        output_path -- A file path; all parent directories must exist.
        projection_name -- The spatial reference system to associate with
        the file being save.  For example, EPSG:4326 and WGS84 are both
        valid.  See the documentation for OSRSpatialReference::SetFromUserInput
        at http://www.gdal.org/ogr/classOGRSpatialReference.html        
        for more specific details.
        
        Returns:
        Nothing.
        
        Note that exceptions will be raised if the DTBitmap2D is not valid
        (has no data), or if any GDAL functions fail.  This method has only
        been tested with 8-bit images, but gray/rgb/alpha images work as
        expected.
        
        """
        
        assert osr != None and gdal != None, "GDAL not available"
        
        # gdal doesn't like unicode objects...
        output_path = output_path.encode(sys.getfilesystemencoding())
        projection_name = projection_name.encode("utf-8")
        
        channel_names = DTBitmap2D.CHANNEL_NAMES
        band_count = self.channel_count()
        assert band_count > 0, "No channels to save"

        (raster_x, raster_y) = self.raster_size()

        # base spatial transform
        grid = self.grid
        (xmin, dx, rot1, ymax, rot2, dy) = (0, 0, 0, 0, 0, 0)
        xmin = grid[0]
        dx = grid[2]
        dy = grid[3]
        ymax = grid[1] + abs(dy) * raster_y

        geotiff = gdal.GetDriverByName("GTiff")
        assert self.dtype() in (np.uint8, np.uint16), "Unhandled bit depth %s" % (self.dtype())
        etype = GDT_Byte if self.dtype() == np.uint8 else GDT_UInt16
        dst = geotiff.Create(output_path, raster_x, raster_y, bands=band_count, eType=etype)
        assert dst, "Unable to create destination dataset at %s" % (output_path)

        # Recall that dx and dy are signed, with positive upwards;
        # this is bizarre, but http://www.gdal.org/gdal_tutorial.html
        # shows it also.
        dst.SetGeoTransform((xmin, dx, rot1, ymax, rot2, -abs(dy)))
        dst_srs = osr.SpatialReference()
        
        # This accepts a variety of inputs, notably EPSG and PROJ.4,
        # as well as NAD27, NAD83, WGS84, WGS72.
        dst_srs.SetFromUserInput(projection_name)
        dst.SetProjection(dst_srs.ExportToWkt())

        if band_count == 1:
            name_map = {0:"gray"} 
        elif band_count == 2:
            name_map = {0:"gray", 1:"alpha"}
        elif band_count == 3:
            name_map = {0:"red", 1:"green", 2:"blue"}
        else:
            name_map = {0:"red", 1:"green", 2:"blue", 3:"alpha"}

        for band_index in name_map:
            band = dst.GetRasterBand(band_index + 1)

            values = getattr(self, name_map[band_index])
            
            values = np.flipud(values)
            # reverse transforms applied in DTDataFile
            shape = list(values.shape)
            shape.reverse()
            data = values.reshape(shape, order="C").tostring()
            
            band.WriteRaster(0, 0, dst.RasterXSize, dst.RasterYSize, data, buf_xsize=dst.RasterXSize, buf_ysize=dst.RasterYSize, buf_type=band.DataType)
        
        dst = None
        
    def __dt_type__(self):
            return "2D Bitmap"

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
        """Create a new instance from a DTDataFile by name.
        
        Arguments:
        datafile -- An open DTDataFile instance
        name -- The name of the DTBitmap2D object in the file (including any time index)
        
        Returns:
        A new DTBitmap2D instance.
        
        """
        
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
        image_path = image_path.encode(sys.getfilesystemencoding())
            
        dataset = gdal.Open(image_path, GA_ReadOnly)
        (xmin, dx, rot1, ymax, rot2, dy) = dataset.GetGeoTransform()
        
        channel_count = dataset.RasterCount
        bands = []
        self.nodata = None
        for band_index in range(1, channel_count + 1):
            band = dataset.GetRasterBand(band_index)
            if self.nodata == None:
                self.nodata = band.GetNoDataValue()
            if band == None:
                break
            bands.append(band)
            
        ymin = ymax + dy * dataset.RasterYSize
        self.grid = (xmin, ymin, dx, abs(dy))
                
        # RGB or RGBA
        if channel_count in (3, 4):

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
                band = bands[idx]
                channel = band.ReadAsArray()
                channel = np.flipud(channel)
                setattr(self, name_map[idx], channel)

        elif channel_count == 1:
            
            # we only have one band anyway on this path, so see if we have an indexed image,
            band = bands[0]
            mesh = band.ReadAsArray()

            mesh = np.flipud(mesh)
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
                
        else:
            sys.stderr.write("Unable to decode an image with %d raster bands" % (channel_count))
            
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
            sys.stderr.write("Warning: DTBitmap2D.py unable to determine image bit depth and byte order for mode \"%s\"\n" % (image.mode))
        else:
            try:
                # fails for signed int16 images produced by GDAL, but works with unsigned
                array = np.fromstring(image.tostring(), dtype=dt)
                array = array.reshape((image.size[1], image.size[0]))
            except Exception, e:
                sys.stderr.write("Warning: DTBitmap2D.py image.tostring() failed for image with mode \"%s\" (PIL error: %s)\n" % (image.mode, str(e)))
        
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
                sys.stderr.write("Warning: DTBitmap2D.py converting binary image to uint8\n")
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

