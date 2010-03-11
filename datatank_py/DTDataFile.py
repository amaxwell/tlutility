#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""Pure python script for generating binary files for DataTank.  The 
internal details of the file format were determined from DTSource:

http://www.visualdatatools.com/DTSource.html

This script is a mixture of functionality from several objects in
DTSource, including DTDataFile, and DTStorage, with other parts
taken as needed from the Write() implementation of various objects.
The intent is not to duplicate all of the functionality of DTSource,
but allow saving the results of computations in objects that are
easily readable by DataTank.  High-level objects such as meshes
and images can be handled specially as needed, but they're really
just specially-named collections of DTArray objects.

The API is strongly centered around what I need for DataTank, and
I've explicitly avoided trying to overdesign this by adding lots of
classes.  I'd probably drop this entirely in favor of SWIG bindings
for DTSource, or maybe even Python modules wrapping the C++ classes,
but I don't have time to do that myself.

DTSource is released under a BSD license, available at

http://www.visualdatatools.com/DTSource/license.html

Any bugs in this script are not attributable to DTSource, and
suggestions, comments, and patches should be sent to the maintainer
by e-mail: amaxwell AT mac DOT com

This script is released under a BSD license, as follows:

This software is Copyright (c) 2010
Adam Maxwell. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

- Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in
the documentation and/or other materials provided with the
distribution.

- Neither the name of Adam Maxwell nor the names of any
contributors may be used to endorse or promote products derived
from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

"""

import sys, os
from struct import Struct
import numpy as np

if sys.byteorder != "little":
    print "warning: saving big-endian files has not been tested"

def _ensure_array(obj):
    """Convert list or tuple to numpy array.

    This doesn't work as desired for scalars, which end up as a 0-D array
    (correctly, but we need an array of length 1 to write to DTDataFile).

    """
    if isinstance(obj, np.ndarray):
        return obj
    else:
        return np.array(obj, dtype=np.double)

# the last component is the time index (if present)
def _basename_of_variable(varname):
    """Get the base name of a variable, without the time index.
    
    Given a variable "FooBar_10", the last component is the time index (if present),
    so we want to strip the "_10".  This does no error checking.  You should not be
    passing in a variable whose name starts with "Seq_"; this is for user-generated
    names, not the internal names for DataTank.
    
    """
    
    comps = varname.split("_")

    # handle variables that aren't time-varying
    if len(comps) == 1:
        return varname
    
    # this is kind of a heuristic; assume anything that is all digits is a time index
    return "_".join(comps[:-1]) if comps[-1].isdigit() else varname

def _type_string_from_dtarray_type(var_type):
    """Returns an appropriate prefix and width-based type.
    
    Arguments:
    var_type -- an integer type used in the C++ DTDataFile
    
    Returns:
    a string type suitable for np.dtype(), or None if the type couldn't be determined
    
    This is mainly useful for passing to routines that allow byte-swapping,
    since you can prefix it with < or > as needed to construct a numpy.dtype.
    
    """
    
    if var_type == 1:
        data_type = "f8" # DTDataFile_Double
    elif var_type == 2:
        data_type = "f4" # DTDataFile_Single
    elif var_type == 8:
        data_type = "i4" # DTDataFile_Signed32Int
    elif var_type == 9:
        data_type = "u2" # DTDataFile_UnsignedShort
    elif var_type == 10:
        data_type = "i2" # DTDataFile_Short
    elif var_type == 11:
        data_type = "u1" # DTDataFile_Unsigned8Char
    elif var_type == 12:
        data_type = "i1" # DTDataFile_Signed8Char
    else:
        data_type = None
        
    return data_type
    
def _dtarray_type_and_size_from_object(obj):
    """Determine C++ DTDataFile type and size for an object.
    
    Arguments:
    obj -- a string or numpy array
    
    Returns:
    Integer type and size (array_type, size_in_bytes).
    (None, None) is returned in case of an error.
    
    NB: np.float is not supported because I'm not sure of the size yet.
    Also, np.int actually ends up as np.int64, at least on Snow Leopard,
    and there's no DTArray type for that.  Maybe truncation is an option
    for int, but I'd rather raise an exception.
    
    """

    # TODO: figure out size of np.float
    
    if isinstance(obj, str) or isinstance(obj, unicode):
        return (20, 1)
    elif isinstance(obj, np.ndarray):
        array = obj
        if array.dtype in (np.float64, np.double):
            dt_array_type = 1 # DTDataFile_Double
            element_size = 8
        elif array.dtype in (np.float32,):
            dt_array_type = 2 # DTDataFile_Single
            element_size = 4
        elif array.dtype in (np.int32,):
            dt_array_type = 8 # DTDataFile_Signed32Int
            element_size = 4
        elif array.dtype in (np.uint16, np.ushort):
            dt_array_type = 9 # DTDataFile_UnsignedShort
            element_size = 2
        elif array.dtype in (np.int16, np.short):
            dt_array_type = 10 # DTDataFile_Short
            element_size = 2
        elif array.dtype in (np.uint8, np.ubyte):
            dt_array_type = 11 # DTDataFile_Unsigned8Char
            element_size = 1
        elif array.dtype in (np.int8, np.byte):
            dt_array_type = 12 # DTDataFile_Signed8Char
            element_size = 1
        
        return (dt_array_type, element_size)

    # default case is an error
    print "unable to determine DT type for object %s" % (type(obj))
    return (None, None)

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
            
class DTDataFile(object):
    """This class roughly corresponds to the C++ DTDataFile class.
    
    Higher-level access is provided for some objects (e.g., PIL image),
    but it is primarily for writing arrays and strings.  In fact, all
    DataTank stores is arrays and strings, with naming conventions to
    define how they're interpreted.
    
    You should not have multiple DTDataFile instances open for the same
    file on disk, or your file's state will get trashed.
    
    Reading values is fairly easy, and DTDataFile provides a 
    dictionary-style interface to the variables.  For example,
    assuming that a variable named "Array_One" exists:
    
    >>> f = DTDataFile("a.dtbin")
    >>> v = f["Array_One"]
    
    Setting is similar, but you're at the mercy of the type conversion
    as in the write() method, and you can't specify a time:
    
    >>> import numpy as np
    >>> f = DTDataFile("a.dtbin")
    >>> f["My array"] = np.zeros((2, 2))
    >>> f["My array"]
    array([[ 0.,  0.],
           [ 0.,  0.]])
           
    Note that if you try to set the same variable name again,
    an exception will be thrown.  Don't do that.
    
    You can also iterate a DTDataFile directly, and each iteration
    returns a variable name.  Variable names are unordered, as in
    hashing collections.
    
    DTDataFile supports the with statement in Python 2.5 and 2.6,
    so you can use this idiom to ensure resources are cleaned up:
    >>> with DTDataFile("foo.dtbin", truncate=True) as df:
    ...     df.write_2dmesh_one(mesh, 0, 0, dx, dy, "FooBar")
    
    """
    
    def __init__(self, file_path, truncate=False):
        """Creates a new DTDataFile instance.
        
        Arguments:
        file_path -- absolute or relative path
        truncate -- whether to truncate the file if it exists
        
        The default mode is to append to a file, creating it if
        it doesn't already exist.  Passing True for truncate will
        entirely clear the file's content.
        
        """
        
        super(DTDataFile, self).__init__()
        self._file_path = file_path
        self._file = open(file_path, "wb+" if truncate else "ab+")
        self._length = os.path.getsize(file_path)
        self._name_offset_map = {}
        self._swap = None
        self._little_endian = None
        self._struct = None
        self.DEBUG = False
    
    def _read_object_header_at_offset(self, offset):
        """Read DTDataFileStructure at the specified offset in the file.
        
        Arguments:
        offset -- integer byte position in the underlying file
        
        Returns:
        A tuple (block_length, var_type, m, n, o, name_length)
        
        This is a Python version of the C++ DTDataFileStructure,
        where m, n, and o are the dimension sizes.  Note that
        block_length includes the length of this object header,
        and name_length includes a nul character.
        
        """

        assert offset + self._struct.size <= self._length, "offset exceeds file length"
        self._file.seek(offset)
        bytes_read = self._file.read(self._struct.size)
        if len(bytes_read) != self._struct.size:
            return None
        return self._struct.unpack(bytes_read)
    
    def _read_in_content(self):
        """Read or update the variable list from disk.
        
        Builds a dictionary of variable name --> offset, where offset is suitable for
        passing to _read_object_header_at_offset.  Also records the endianness of the
        file and determines an appropriate header structure.
        
        This method walks the entire file on-disk, so it may be expensive to compute
        for large files.
        
        """
        
        self._name_offset_map = {}
        # ensure we have a consistent file
        self._file.flush()
        self._file.seek(0)
        # all headers are the same length
        default_file_header = "DataTank Binary File LE\0"
        
        if self._length:
            assert self._length >= len(default_file_header), "invalid file"
            
            header = self._file.read(len(default_file_header))
            if header == "DataTank Binary File LE\0":
                self._little_endian = True
                self._swap = False if sys.byteorder == "little" else True
            else:
                self._little_endian = False
                self._swap = True if sys.byteorder == "little" else False
        
            # DTDataFileStructure: long long followed by 5 ints
            # http://docs.python.org/library/struct.html
            format = "<qiiiii" if self._little_endian else ">qiiiii"
            self._struct = Struct(format)
        
        # avoid this for empty files
        while self._length:
            
            block_start = self._file.tell()            
            (block_length, var_type, m, n, o, name_length) = self._read_object_header_at_offset(block_start)

            # remove the trailing \0 so we have a normal Python string
            name = self._file.read(name_length)[:-1]
            self._name_offset_map[name] = block_start
            
            # could do a consistency check here to make sure we came out even?
            next_block = block_start + block_length
            if next_block >= self._length:
                break
            
            self._file.seek(next_block)
    
    def _reload_content_if_needed(self):
        """Ensures the name-offset dictionary is current.
        
        Called before reading variable names or accessing values.  This is
        a no-op if file size has not changed; any rewrites to content that
        do not change length are ignored, so you can call this as often as
        needed without taking a big hit.
        
        """
        
        current_size = os.path.getsize(self._file_path)
        if (len(self._name_offset_map) == 0 and current_size > 0) or self._length != current_size:
            
            # This check is here to ensure that the optimization strategy is working properly.
            # If we see lots of spurious reload messages, something is likely haywire.
            if self.DEBUG:
                reasons = []
                if len(self._name_offset_map) == 0:
                    reasons.append("Empty offset map (current size = %d)" % (current_size))
                if self._length != os.path.getsize(self._file_path):
                    reasons.append("length %d != actual size %d" % (self._length, current_size))
                print "reloading content:", " ".join(reasons)
            self._read_in_content()
    
    def close(self):
        """Close the underlying file object.
        
        Further access to variables and names is not possible at this point
        and will raise an exception.
        
        """
        
        self._file.close()
        # could use as a sentinel to allow reopening
        self._file = None
        self._name_offset_map = {}
        
    def variable_names(self):
        """Unsorted list of variable names."""

        self._reload_content_if_needed()
        return self._name_offset_map.keys()

    def variable_named(self, name):
        """Procedural API for getting a value from disk.
        
        Arguments:
        name -- the variable name as user-visible in the file (without the trailing nul)
        
        Returns:
        A string, scalar, or numpy array.
        
        This returns values as strings, scalars, or numpy arrays.  No attempt is made to
        convert a given array to its abstract type (so you can retrieve each plane of a
        2D Bitmap object by name, but not as a PIL image).
        
        """
        
        self._reload_content_if_needed()

        if name not in self._name_offset_map:
            return None
        
        block_start = self._name_offset_map[name]
        (block_length, var_type, m, n, o, name_length) = self._read_object_header_at_offset(block_start)
        
        data_start = block_start + self._struct.size + name_length
        self._file.seek(data_start)
        
        # DTDataFile_String
        if var_type == 20:
            bytes_read = self._file.read(block_length - self._struct.size - name_length).strip("\0")
            return unicode(bytes_read, "utf-8")

        # everything else is a DTArray type
        data_type = _type_string_from_dtarray_type(var_type)
        assert data_type is not None, "unhandled DTArray type"
                    
        # don't need to include the byte order unless it's not host-ordered
        if self._swap:
            byte_order = "<" if self._little_endian else ">"
            data_type = byte_order + data_type
        
        element_count = m * n * o
        values = np.fromfile(self._file, dtype=np.dtype(data_type), count=element_count)
        assert values.size == element_count, "unable to read all data"
        
        # handle scalar values specially
        if m == 1 and n == 1 and o == 1:
            return values[0]
        
        # ignore trailing dimensions == 1    
        shape = [m]
        if n > 1 or o > 1:
            shape.append(n)
        if o > 1:
            shape.append(o)
            
        # see the array writing code
        shape.reverse()
        
        # TODO: will this actually convert to host byte order?
        if self._swap:
            values = values.astype(np.dtype(data_type[1:]))   
            
        return values.reshape(shape)        
        
    def __iter__(self):
        # unordered iteration
        return self.variable_names().__iter__()
        
    def __getitem__(self, key):
        # support for dictionary-style getting
        return self.variable_named(key)
    
    def __enter__(self):
        # support for with statement
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        # support for with statement
        self.close()
        return False
        
    def __str__(self):
        """Basic description of the object and its size."""
        string = super(DTDataFile, self).__str__()
        self._reload_content_if_needed()
        string += "\n\tPath: %s\n\tSize: %s bytes\n\tCount: %s variables" % (os.path.abspath(self._file_path), self._length, len(self.variable_names()))
        return string
        
    def _check_and_write_header(self):
        """Checks for dtbin header and writes it if the file is empty.
    
        The output file must be open for binary reading and writing.
        On return, the file position will be restored or at end-of-file
        if a new file.
    
        """
    
        # TODO: test on big-endian system
        file_header = "DataTank Binary File LE\0" if sys.byteorder == "little" else "DataTank Binary File BE\0"
        assert self._file.mode.endswith("b+"), "file must be opened with wb+ or ab+"
    
        previous_offset = self._file.tell()
        if previous_offset >= len(file_header):
            # Appending to a previously written file, so make sure the variable map is up-to-date.
            # TODO: This will get expensive unless I track file length in the write... methods.
            self._reload_content_if_needed()
            self._file.seek(previous_offset)
        else:
            # setting up a new file, so choose native byte order
            assert previous_offset == 0, "file is missing dtbinary header"
            self._file.write(file_header)
            self._file.flush()
            # DTDataFileStructure: long long followed by 5 ints
            # http://docs.python.org/library/struct.html
            if sys.byteorder == "little":
                format = "<qiiiii" 
                self._little_endian = True
            else:
                format = ">qiiiii"
                self._little_endian = False
            self._struct = Struct(format)

    def _write_string(self, string, name):
        """Writes a single string to the output file.
        
        Arguments:
        string -- the value to write
        name -- the user-visible name of the string variable

        This is the lowest-level string writing interface, and is for internal use.
        If the string is a unicode instance, characters are encoded 
        as UTF-8, since DataTank seems to handle that correctly.

        """

        assert name not in self._name_offset_map, "variable name already exists"

        self._check_and_write_header()
        block_start = self._file.tell()

        if isinstance(string, unicode):
            string = string.encode("utf-8")
            
        DTDataFile_String = 20
        # header struct length + (name and null) + (value and null)
        block_length = self._struct.size + len(name) + 1 + len(string) + 1
        file_struct = self._struct.pack(block_length, DTDataFile_String, len(string) + 1, 1, 1, len(name) + 1)
        self._file.write(file_struct)
        self._file.write(name + "\0")
        self._file.write(string + "\0")
        
        # update file length and variable map manually
        self._file.flush()
        self._length = self._file.tell()
        self._name_offset_map[name] = block_start

    def _write_array(self, array, name):
        """Write an array to the given file object.
        
        Arguments:
        array -- a numpy.ndarray, list or tuple
        name -- the user-visible name of the array variable

        This is the lowest-level array writing interface, and is for internal use.
        Writes an array object and header to a .dtbin file.  Handles up to 3 dimensions.
        Arrays are not visible in DataTank unless an additional name is written.
        Python lists and tuples are converted to double-precision arrays, but scalars
        must be converted beforehand.

        """

        assert name not in self._name_offset_map, "variable name already exists"

        self._check_and_write_header()    
        block_start = self._file.tell()

        array = _ensure_array(array)
        assert len(array.shape) > 0, "zero dimension array is not allowed"
        assert len(array.shape) <= 3, "maximum of 3 dimensions is supported"

        # Reshaping with order="F" for FORTRAN doesn't work as I think it should, but
        # flattening and manually reshaping it works as expected, using C ordering.
        shape = list(array.shape)
        shape.reverse()
        array = np.reshape(array.flatten(), shape, order="C")

        # map ndarray type to DTArray type and record element size in bytes
        (dt_array_type, element_size) = _dtarray_type_and_size_from_object(array)
            
        # look up a type to pass to np.array.tofile(), mainly so we can swap bytes
        data_type = _type_string_from_dtarray_type(dt_array_type)
        assert data_type is not None, "unhandled DTArray type"

        # don't need to change the byte order unless it's not host-ordered
        if self._swap:
            # TODO: see if this actually works, since tofile doesn't allow byte swapping
            print "WARNING: byte-swapped writing has not been tested"
            byte_order = "<" if self._little_endian else ">"
            data_type = byte_order + data_type
            array = array.astype(np.dtype(data_type))
            
        assert dt_array_type is not None, "unknown array type: " + str(array.dtype)

        shape = array.shape
        m = shape[0]
        n = 1
        o = 1
        if len(shape) > 1:
            n = shape[1]
        if len(shape) > 2:
            o = shape[2]

        block_length = self._struct.size + len(name) + 1 + array.size * element_size
        file_struct = self._struct.pack(block_length, dt_array_type, m, n, o, len(name) + 1)

        # write the header
        self._file.write(file_struct)
        # write the variable name
        self._file.write(name + "\0")
        # write the variable values as raw binary
        array.tofile(self._file)
        
        # update file length and variable map manually
        self._file.flush()
        self._length = self._file.tell()
        self._name_offset_map[name] = block_start  
            
    def write_array(self, array, name, dt_type=None, time=None):
        """Write an array with optional time dependence.
        
        Arguments:
        array -- a numpy array, list, or tuple
        name -- user-visible name of the array variable
        dt_type -- string type used by DataTank
        time -- time value if this variable is time-varying
        
        If this is a time-varying array and no values have been written, this will
        add a string to expose it in DataTank using the dt_type parameter, which
        is a DataTank type such as "Array" or "NumberList."  The time parameter is
        a double-precision floating point value, relative to DataTank's time slider.

        Note that if time dependence is used, the caller is responsible for appending
        "_N" to the variable, where N is an integer >= 0 and strictly increasing 
        with time.  A contrived example follows:
        
        >>> import numpy as np
        >>> f = DTDataFile("foo.dtbin")
        >>> for idx in xrange(0, 10):
        ...     point_test = np.array(range(idx, idx + 10), np.double)
        ...     point_test = point_test.reshape((point_test.size / 2, 2))
        ...     tp = "2D Point Collection"
        ...     tm = idx * 2.
        ...     f.write_array(point_test, "Points_%d" % (idx), dt_type=tp, time=tm)
        
        Note that the actual variable type is "2D Point Collection," and the caller
        is responsible for setting the array shape correctly.  This should work for any
        array-based object in DataTank.
        
        """
    
        assert dt_type, "you must supply a dt_type parameter to write_array"
        
        # Expose the time series; dt_type is something like "Array" or "NumberList"
        base_name = "Seq_" + _basename_of_variable(name)
        if time and base_name not in self.variable_names():
            self._write_string(dt_type, base_name)
        elif time is None:
            self._write_string(dt_type, base_name)
            
        # caller is responsible for appending _index as needed for time series
        self._write_array(array, name)

        if time:
            self._write_array(np.array((time,), dtype=np.double), name + "_time")

    def write_string(self, string, name, time=None):
        """Write a string with time dependence.
        
        Arguments:
        string -- the value to save
        name -- the user-visible name of the string variable
        time -- time value if this variable is time-varying
        
        If this is the first time this string has been written, this method will
        add a string to expose it in DataTank.  The time parameter is a 
        double-precision floating point value, relative to DataTank's time slider.

        Note that if time dependence is used, the caller is responsible for appending
        "_N" to the variable, where N is an integer >= 0 and strictly increasing 
        with time.  A call might look like this:
        
        >>> import datetime
        >>> f = DTDataFile("foo.dtbin")
        >>> for idx in xrange(0, 10):
        ...     s = datetime.now().isoformat()
        ...     f.write_array(s, "PointTest_%d" % (idx), time=idx * 2.)
                
        """
        
        # Expose a time series of type String
        base_name = "Seq_" + _basename_of_variable(name)
        if time and base_name not in self.variable_names():
            self._write_string("String", base_name)
        elif time is None:
            self._write_string("String", base_name)
             
        # caller is responsible for appending _index as needed for time series
        self._write_string(string, name)

        if time:
            self._write_array(np.array((time,), dtype=np.double), name + "_time")

    def write(self, obj, name, dt_type=None, time=None):
        """Write a single value to a file object by name.
        
        Arguments:
        obj -- string, numpy array, list, tuple, or scalar value
        name -- user-visible name of the variable
        dt_type -- string type used by DataTank
        time -- time value if this variable is time-varying

        Handles various object types, and adds appropriate names so they're visible
        in DataTank.  String, scalar, ndarray, tuple, and list objects are supported,
        although ndarray gives the most specific interface for precision and avoids
        type conversions.
        
        This method saves a 0D array (scalar) as a "Real Number", a 1D array as a
        "List of Numbers" and other shapes as "Array" by default.  Use the dt_type
        parameter if you want something specific, such as "2D Point" for a point
        (although the caller has to ensure the shape is correct).

        """
        
        #
        # The Obj-C programmer in me hates using isinstance here, but I'm not sure
        # what else to do, short of adding a separate write method for each data
        # type.  The basic problem is that you have to map to specific types in order
        # to use DTDataFile, and everything needs to be converted to an ndarray or
        # a string in the end.
        #

        if isinstance(obj, str):
            self.write_string(obj, name, time=time)
        elif isinstance(obj, (float, int)):
            # convert to an array, but allow numpy to pick the type
            array = np.array((obj,))
            self.write_array(array, name, dt_type="Real Number", time=time)
        elif isinstance(obj, (tuple, list)) and isinstance(obj[0], (str, unicode)):
            # this must be a StringList
            offsets = []
            char_list = []
            current_offset = 0
            for string in obj:
                string = string.encode("utf-8")
                char_list += [ord(x) for x in string]
                offsets.append(current_offset)
                current_offset += len(string)
            self._write_array(np.array(offsets, dtype=np.int32), name + "_offs")
            self.write_array(np.array(char_list, dtype=np.uint8), name, dt_type="StringList", time=time)
        elif isinstance(obj, (np.ndarray, tuple, list)):
            # need to be able to call shape
            array = _ensure_array(obj)
            # DTDataStorage::WriteOne changes the type based on the dimensions, so do the same.
            if dt_type is None:
                dt_type = "NumberList" if len(array.shape) == 1 else "Array"
            self.write_array(array, name, dt_type=dt_type, time=time)
        else:
            assert False, "unhandled object type"
            
    def __setitem__(self, name, value):
        # support for dictionary-style setting; this is very limited
        self.write(value, name)

    def write_image_one(self, image, name, grid=None):
        """Save a single PIL image.
        
        Arguments:
        image -- a PIL image
        name -- the user-visible name of the image variable
        grid -- the origin and pixel size of the image, as (xmin, ymin, dx, dy)

        Handles RGB and grayscale images, with or without an alpha channel.
        16-bit images should be supported, but I don't have one to test with
        at the moment.  DTBitmap2D itself doesn't support floating-point images,
        but those are typically elevation data that I'd want as a DTMesh2D anyway.

        """
        
        array = _array_from_image(image)
        assert array is not None, "unable to convert the image to a numpy array"
        assert array.dtype in (np.int16, np.uint16, np.uint8, np.int8, np.bool), "unsupported bit depth"

        # no suffix on DataTank names for 8 bit images
        name_suffix = "" if array.dtype in (np.uint8, np.int8) else "16"

        self._write_string("2D Bitmap", "Seq_" + name)
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
                self._write_array(np.flipud(array), name + "_Gray" + name_suffix)
            else:
                assert image.mode == "LA", "requires gray + alpha image"
                self._write_array(np.flipud(array[:,0]), name + "_Gray" + name_suffix)
                self._write_array(np.flipud(array[:,1]), name + "_Alpha" + name_suffix)

        elif image.mode in ("RGB", "RGBA"):

            self._write_array(np.flipud(array[:,:,0]), name + "_Red" + name_suffix)
            self._write_array(np.flipud(array[:,:,1]), name + "_Green" + name_suffix)
            self._write_array(np.flipud(array[:,:,2]), name + "_Blue" + name_suffix)
            if image.mode == "RGBA":
                self._write_array(np.flipud(array[:,:,3]), name + "_Alpha" + name_suffix)            
                            
        else:
            assert False, "unsupported image mode"

        # Equivalent of WriteNoSize(DTDataStorage, string, DTMesh2DGrid).
        if grid is None:
            grid = (0, 0, 1, 1)
        self._write_array(grid, name)       

    def write_2dmesh_one(self, values, name, grid=None):
        """Save a single 2D mesh variable.
        
        Arguments:
        values -- the mesh array (must be an ndarray)
        grid -- the origin and element size of the mesh, as (xmin, ymin, dx, dy)

        This saves the equivalent of a 2D mesh grid and values to the given file object.
        The grid is described by xmin, ymin, dx, dy, and the extent of the grid is
        determined by the shape of the values array (which has a single value per node).
        If no grid is given, a unit grid with origin (0, 0) is assumed.

        """

        #
        # 1. Write bounding box as DTRegion2D as "name" + "_bbox2D"
        #    This is a double array with corners ordered (xmin, xmax, ymin, ymax)
        # 2. Write grid using WriteNoSize as "name" + "_loc"
        #    This is a double array with (xmin, ymin, dx, dy)
        # 3. Write mask (ignored for now)
        # 4. Write values as array "name"
        # 5. Write name and type for DataTank
        #

        if grid is None:
            grid = (0, 0, 1, 1)
            
        (xmin, ymin, dx, dy) = grid 
        xmax = xmin + values.shape[1] * float(dx)
        ymax = ymin + values.shape[0] * float(dy)

        # will be converted to double arrays
        bbox = (xmin, xmax, ymin, ymax)

        self._write_array(bbox, name + "_bbox2D")
        self._write_array(grid, name + "_loc")
        self._write_array(values, name)
        self._write_string("2D Mesh", "Seq_" + name)

    