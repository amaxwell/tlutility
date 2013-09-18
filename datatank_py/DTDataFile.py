#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

"""Pure python script for generating binary files for DataTank.  The 
internal details of the file format were determined from DTSource:

http://www.visualdatatools.com/DTSource.html

This script is a mixture of functionality from several objects in
DTSource, including DTDataFile, and DTStorage, with other parts
taken as needed from the Write() implementation of various objects.
The intent is not to duplicate all of the functionality of DTSource,
but allow saving the results of computations in objects that are
easily readable by DataTank.  High-level objects such as meshes
and images can be handled specially as needed; see the DTMesh2D
and DTBitmap2D classes as example.

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

"""

__all__ = ["DTDataFile"]

import sys, os
from struct import Struct
import numpy as np
from DTPyWrite import dt_writer

# see doc for _load_modules
_CLASSES_BY_TYPE = {}

def _log_warning(msg):
    """Write a message to standard error"""
    sys.stderr.write("DTDataFile: %s\n" % (msg))
    
def _load_modules():
    """Creates a cache mapping DataTank type names to datatank_py classes.
    
    For instance, this will have something like
    
    "2D Point" = <class 'datatank_py.DTPoint2D.DTPoint2D'>
    "2D Path"  = <class 'datatank_py.DTPath2D.DTPath2D'>
    "Path2D"   = <class 'datatank_py.DTPath2D.DTPath2D'>
    
    where the class objects will have attribute dt_type (iterable)
    and class method from_data_file (DTPyWrite).
    
    """
    if len(_CLASSES_BY_TYPE) == 0:
        from glob import glob
        import datatank_py
        
        # try to load all modules in the datatank_py module directory
        for module_name in glob(os.path.join(os.path.dirname(datatank_py.__file__), "DT*.py")):
            # e.g. DTPath2D.py
            module_name = os.path.basename(module_name)
            if "DTDataFile" in module_name:
                continue
            # DTPath2D
            class_name = os.path.splitext(module_name)[0]
            # datatank_py.DTPath2D
            module_name = "datatank_py." + class_name
            # import datatank_py.DTPath2D
            module = __import__(module_name, fromlist=[])
            # ignore modules that don't have a class with the same name
            if hasattr(module, class_name):
                mcls = getattr(module, class_name)
                if hasattr(mcls, class_name):
                    # finally, an instance of the class itself
                    mcls = getattr(mcls, class_name)
                    # check for class attribute of dt_type and class method from_data_file
                    if hasattr(mcls, "dt_type") and hasattr(mcls, "from_data_file"):
                        # DataTank and DTSource use different constants. Sometimes.
                        for dt_type in mcls.dt_type:
                            _CLASSES_BY_TYPE[dt_type] = mcls

# from cProfile, these are surprisingly expensive to get
try:
    _INT32_MAX = np.iinfo(np.int32).max
    _INT32_MIN = np.iinfo(np.int32).min
except AttributeError:
    # These constants don't exist in the ancient version of NumPy included with
    # OS X 10.5.8, so here are the values from NumPy 2.0.0dev8291.
    _log_warning("int32 limits not found in NumPy, likely because version %s is too old" % (np.version.version))
    _INT32_MAX = 2147483647
    _INT32_MIN = -2147483648
    
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
    
    if isinstance(obj, basestring):
        return (20, 1)
    elif isinstance(obj, np.ndarray):
        array = obj
        dt_array_type = None
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
        
        # could be something like int64
        if dt_array_type != None:
            return (dt_array_type, element_size)
        else:
            _log_warning("unsupported ndarray type %s" % (array.dtype))

    # default case is an error
    _log_warning("unable to determine DT type for object %s" % (type(obj)))
    return (None, None)

def _debug_log(msg):
    from syslog import syslog, LOG_ERR, LOG_USER
    syslog(LOG_ERR | LOG_USER, msg)
            
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
    
    def __init__(self, file_path, truncate=False, readonly=False):
        """Creates a new DTDataFile instance.
        
        Arguments:
        file_path -- absolute or relative path
        truncate -- whether to truncate the file if it exists (default is False)
        readonly -- open the file for read-only access (default is False)
        
        The default mode is to append to a file, creating it if
        it doesn't already exist.  Passing True for truncate will
        entirely clear the file's content.
        
        """
        
        super(DTDataFile, self).__init__()
        # store absolute path, in case someone calls chdir after creation
        # with a relative path
        self._file_path = os.path.abspath(file_path)
        # ensure __del__ works in case of failure in __init__        
        self._file = None
        self._readonly = False
        
        if readonly:
            assert truncate == False, "truncate and readonly are mutually exclusive"
            filemode = "rb"
            self._readonly = True
        elif truncate:
            assert readonly == False, "truncate and readonly are mutually exclusive"
            filemode = "wb+"
        else:
            assert readonly == False, "append and readonly are mutually exclusive"
            filemode = "ab+"
            
        self._file = open(file_path, filemode)
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
        # ensure we have a consistent file unless we're read-only
        if self._readonly == False:
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
        
        assert self._length == os.path.getsize(self._file_path), "file size = %d, length record = %d" % (os.path.getsize(self._file_path), self._length)
    
    def _reload_content_if_needed(self):
        """Ensures the name-offset dictionary is current.
        
        Called before reading variable names or accessing values.  This is
        a no-op if file size has not changed; any rewrites to content that
        do not change length are ignored, so you can call this as often as
        needed without taking a big hit.
        
        I expect the only time self._length and the size from stat are not
        consistent will be if you're modifying the file from another program,
        in which case you'd better just be reading it here.
        
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
                _log_warning("reloading content:" + " ".join(reasons))
            self._read_in_content()
    
    def close(self):
        """Close the underlying file object.
        
        Further access to variables and names is not possible at this point
        and will raise an exception.
        
        """
        
        if self._file != None:
            self._file.close()
            # could use as a sentinel to allow reopening
            self._file = None
            
        self._name_offset_map = {}
        
    def path(self):
        """Returns the file path."""
        return self._file_path
        
    def resolve_name(self, name):
        """Resolve a name in case of shared variables.
        
        Arguments:
        name -- A potentially shared variable name
        
        Returns:
        The underlying variable name, with all references resolved
        
        This is pretty efficient in the common case of no redirect, as
        it only reads the header.  Other cases are a bit more expensive,
        but too tricky to be worth rewriting at the moment.
        
        """
        
        self._reload_content_if_needed()

        if name not in self._name_offset_map:
            # exception here would be more pythonic, but this is consistent
            return name
        
        block_start = self._name_offset_map[name]
        (block_length, var_type, m, n, o, name_length) = self._read_object_header_at_offset(block_start)
        
        # if this isn't a string, return the name without munging it
        if var_type != 20:
            return name
            
        underlying_name = self.variable_named(name)
        
        # shortcut for a one step redirect
        if isinstance(underlying_name, basestring) == False:
            return underlying_name
        
        # deeper redirect, so avoid circular references
        names_seen = set()
        names_seen.add(underlying_name)
        
        while isinstance(underlying_name, basestring) == False:
            underlying_name = self.variable_named(underlying_name)
            assert underlying_name not in names_seen, "DTDataFile: circular name reference for %s" % (name)
            names_seen.add(underlying_name)
            
        return underlying_name
                
    def variable_names(self):
        """Unsorted list of variable names."""
        
        #
        # WARNING: calling this in asserts at each write was killing performance,
        # due to overhead of dict.keys().  Accessing the dict directly in those
        # methods increased speed by 10x.
        #
        self._reload_content_if_needed()
        return self._name_offset_map.keys()

    def variable_named(self, name, use_modules=False):
        """Procedural API for getting a value from disk.
        
        Arguments:
        name -- the variable name as user-visible in the file (without the trailing nul)
        use_modules -- try to convert to abstract type by introspection of available modules
        
        Returns:
        A string, scalar, or numpy array.
        
        This returns values as strings, scalars, or numpy arrays.  By default, no 
        attempt is made to convert a given array to its abstract type (so you can
        retrieve each plane of a 2D Bitmap object by name, but not as a PIL image).
        
        """
        
        self._reload_content_if_needed()

        if name not in self._name_offset_map:
            return None
        
        block_start = self._name_offset_map[name]
        (block_length, var_type, m, n, o, name_length) = self._read_object_header_at_offset(block_start)
        
        # WARNING: this is constant, but make sure to call self._file.seek(data_start)
        # before calling anything that actually reads from the file, especially since
        # recursive calls can change the file pointer.
        data_start = block_start + self._struct.size + name_length
        
        # DTDataFile_String
        if var_type == 20:
            self._file.seek(data_start)
            bytes_read = self._file.read(block_length - self._struct.size - name_length).strip("\0")
            return unicode(bytes_read, "utf-8")
        elif name.startswith("Seq_") is False:
            
            # !!! reentrancy here
            dt_type = self.variable_named("Seq_" + name)
            
            # This is a slippery slope, but I needed StringList support.  In general,
            # reading compound types should not be done here, but StringList is a special
            # case since it's composed of native Python objects, unlike a DTMesh2D, and
            # we don't want a StringList Python class to wrap a list of strings.
            if dt_type == "StringList":
                
                element_count = m * n * o
                self._file.seek(data_start)
                values = np.fromfile(self._file, dtype=np.dtype(np.int8), count=element_count)
                
                # !!! reentrancy here
                offsets = self.variable_named(name + "_offs")
                
                # singleton dimensions are now saved, but mess things up here
                offsets = np.squeeze(offsets)

                assert offsets != None, "invalid StringList: no offsets found for %s" % (name)
                string_list = []
                
                for idx in xrange(len(offsets)):
                    start = offsets[idx]
                    end = offsets[idx + 1] if idx < (len(offsets) - 1) else values.size
                    # get rid of trailing null
                    if end > 0:
                        end -= 1
                    string = "".join([chr(x) for x in values[start:end]]).decode("utf-8")
                    string_list.append(string)
                
                return string_list
            elif use_modules:
                _load_modules()
                # could log and continue, but this is currently only be explicit request
                assert dt_type in _CLASSES_BY_TYPE, "Class %s is not in %s" % (dt_type, _CLASSES_BY_TYPE)
                
                dt_cls = _CLASSES_BY_TYPE[dt_type]
                # !!! early return here
                return dt_cls.from_data_file(self, name)
                            
        # everything else is a DTArray type
        data_type = _type_string_from_dtarray_type(var_type)
        assert data_type is not None, "unhandled DTArray type"
                    
        # include the byte order when it's not host-ordered and wider than 8 bits
        if self._swap and data_type.endswith("1") is False:
            byte_order = "<" if self._little_endian else ">"
            data_type = byte_order + data_type
        
        element_count = m * n * o
        
        # We end up returning an array containing an empty array if element_count
        # is zero, and that's not what I want; an empty vector is more appropriate.
        if element_count == 0:
            return np.array([], dtype=np.dtype(data_type))
            
        self._file.seek(data_start)
        values = np.fromfile(self._file, dtype=np.dtype(data_type), count=element_count)
        assert values.size == element_count, "unable to read all data"
                
        # handle scalar values specially
        if m == 1 and n == 1 and o == 1:
            return values[0]
        
        # !!! Original code ignored singleton dimensions in determining shape, 
        # but this caused major problems when reading objects from DataTank
        # files; not sure if preexisting code accounts for singletons correctly.
        
        # see the array writing code for order of these elements
        shape = (o, n, m)
            
        return values.reshape(shape, order="C")        
    
    def dt_object_named(self, key):
        # Tried to make this the default in __getitem__, but too many of the
        # modules use dictionary-style getters in from_data_file methods,
        # and that would be a compatibility nightmare.
        return self.variable_named(key, use_modules=True)
        
    def __iter__(self):
        # unordered iteration
        return self.variable_names().__iter__()
        
    def __getitem__(self, key):
        # support for dictionary-style getting
        return self.variable_named(key)
        
    def __contains__(self, item):
        # direct (fast) support for in statement
        self._reload_content_if_needed()
        return item in self._name_offset_map
    
    def __enter__(self):
        # support for with statement
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        # support for with statement
        self.close()
        return False
        
    def __del__(self):
        # close the file when an instance is deleted
        self.close()
        
    def __str__(self):
        """Basic description of the object and its size."""
        string = super(DTDataFile, self).__str__()
        self._reload_content_if_needed()
        string += "\n\tPath: %s\n\tSize: %s bytes\n\tLittle-endian content: %s\n\tSwap bytes: %s\n\tCount: %s variables" % (os.path.abspath(self._file_path), self._length, self._little_endian, self._swap, len(self.variable_names()))
        return string
        
    def _check_and_write_header(self):
        """Checks for dtbin header and writes it if the file is empty.
    
        The output file must be open for binary reading and writing.
        On return, the file position will be restored or at end-of-file
        if a new file.
    
        """
    
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
            self._length = self._file.tell()
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

        assert name not in self._name_offset_map, "variable name %s already exists" % (name)

        # file writes always take place at the end; we can't edit in-place
        self._file.seek(0, os.SEEK_END)  
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

        # file writes always take place at the end; we can't edit in-place
        self._file.seek(0, os.SEEK_END)  
        self._check_and_write_header()  
        block_start = self._file.tell()

        array = _ensure_array(array)
        assert len(array.shape) > 0, "zero dimension array is not allowed"
        assert len(array.shape) <= 3, "maximum of 3 dimensions is supported"
        
        # Flip the axes so the shape is compatible with DTArray indexing, then
        # write the array in C order.  DTSource indexes as (row, column, slice)
        # and numpy indexes as (slice, row, column).  This gets very confusing.
        # Further, the row/column display in DataTank when you view an array as
        # text is backwards.  I tried various schemes of flipping arrays here to
        # make this more transparent, but just ended up confusing myself really
        # badly.  In the end, the important thing to remember is that the user
        # is responsible for the array shape; in numpy, you need to remember
        # that you're indexing (slice, row, column), and reorder that as needed
        # for DataTank.
        reversed_shape = list(array.shape)
        reversed_shape.reverse()
        array = array.reshape(reversed_shape, order="C")

        # map ndarray type to DTArray type and record element size in bytes
        (dt_array_type, element_size) = _dtarray_type_and_size_from_object(array)
            
        # look up a type to pass to np.array.tofile(), mainly so we can swap bytes
        data_type = _type_string_from_dtarray_type(dt_array_type)
        assert data_type is not None, "unhandled DTArray type"

        # don't need to change the byte order unless it's not host-ordered
        if self._swap and data_type.endswith("1") is False:
            byte_order = "<" if self._little_endian else ">"
            data_type = byte_order + data_type
            array = array.astype(np.dtype(data_type))
            
        assert dt_array_type is not None, "unknown array type: " + str(array.dtype)

        shape = array.shape
        m = shape[0]
        n = shape[1] if len(shape) > 1 else 1
        o = shape[2] if len(shape) > 2 else 1
        
        block_length = self._struct.size + len(name) + 1 + m * n * o * element_size
        file_struct = self._struct.pack(block_length, dt_array_type, m, n, o, len(name) + 1)

        # write the header
        self._file.write(file_struct)
        # write the variable name
        self._file.write(name + "\0")
        # write the variable values as raw binary
        array.tofile(self._file)
        
        # update file length and variable map manually
        self._length = self._file.tell()
        self._name_offset_map[name] = block_start  
    
    def _dt_write(self, obj, name, time=None, anonymous=False):
        """Wrapper that calls __dt_write__ on a compound object.
        
        Arguments:
        obj -- object that implements __dt_write__ and __dt_type__
        name -- user-visible name of the variable; user is responsible for appending _N if needed
        time -- time value if this variable is time-varying        
        anonymous -- whether to expose the variable name by prefixing with Seq_
        
        For time-varying values, an underscore and integer must be appended to the
        variable name, beginning with zero.  This method will raise if there is no
        zero time, or if time values are not strictly increasing.
        
        """
        
        # get the type by introspection
        assert dt_writer(obj), "object must implement dt_writer methods"
        dt_type = obj.__dt_type__()
        
        # we'll be accessing the variable map
        self._reload_content_if_needed()
        
        # Expose a time series of type dt_type
        if anonymous == False:
            bnv = _basename_of_variable(name)
            base_name = "Seq_" + bnv
            if time and base_name not in self._name_offset_map:
                self._write_string(dt_type, base_name)
            elif time is None:
                self._write_string(dt_type, base_name)
                if bnv != name:
                    _log_warning("\"%s\" name has implicit time, but no time given" % (name))
        else:
            assert time == None, "anonymous write cannot save a time variable"
        
        # Write time value before writing the variable, to DataTank doesn't see
        # an inconsistent file (suggested by an error message in DataTank).
        if time is not None:
            
            # The sanity checks here are pretty strict, but should save time in
            # debugging, since they're confusing or hard to spot in DataTank itself.
            
            # ensure that we're following convention for variable naming of time series
            name_parts = name.split("_")
            assert name_parts[-1].isdigit(), "time series names must end with an integer"
            time_index = int(name_parts[-1])

            if time_index > 0:
                # if you skip the zero time index, DataTank gives you index-based times
                previous_time_name = "%s_%d_time" % ("_".join(name_parts[0:-1]), time_index - 1)
                assert previous_time_name in self._name_offset_map, "variable \"%s\" not found in %s" % (previous_time_name, self._name_offset_map.keys())
                # DataTank enforces this as well, and I'd rather find out about it while creating the file
                assert self[previous_time_name] < time, "time must be strictly increasing (error in %s at t=%f)" % (name, time)
        
            self._write_array(np.array((time,), dtype=np.double), name + "_time")

        # caller is responsible for appending _N as needed for time series
        obj.__dt_write__(self, name)
            
    def write_anonymous(self, obj, name):
        """Write an object that will not be visible in DataTank.
        
        Arguments:
        array -- a string, numpy array, list, or tuple
        name -- name of the variable
        
        This is used for writing additional arrays and strings used by compound types,
        such as a 2D Mesh, which has an additional grid array.
        
        """
        
        # for now, just a simple wrapper around the primitive write methods
        if dt_writer(obj):
            self._dt_write(obj, name, None, anonymous=True)
        elif isinstance(obj, basestring):
            self._write_string(obj, name)
        elif isinstance(obj, (float, int)):
            # convert to an array, but allow numpy to pick the type for a float
            if isinstance(obj, float):
                array = np.array((obj,))  
            else:
                # coerce int to int32, since it defaults to int64 on 64 bit systems, but check size
                assert obj <= _INT32_MAX and obj >= _INT32_MIN, "integer too large for 32-bit type"
                array = np.array((obj,), dtype=np.int32)
            self._write_array(array, name)
        elif isinstance(obj, (tuple, list)) and len(obj) and isinstance(obj[0], basestring):
            # this will be a StringList; note that anonymous StringList variables are
            # used for error lists in DataTank
            offsets = []
            char_list = []
            current_offset = 0
            # flat list of character codes, with each string separated by a null
            for string in obj:
                string = (string + "\0").encode("utf-8")
                char_list += [ord(x) for x in string]
                offsets.append(current_offset)
                current_offset += len(string)
            self._write_array(np.array(offsets, dtype=np.int32), name + "_offs")
            self._write_array(np.array(char_list, dtype=np.int8), name)
        elif isinstance(obj, (np.ndarray, tuple, list)):  
            self._write_array(_ensure_array(obj), name)
        else:
            assert False, "unhandled object type"
            
    def write_array(self, array, name, dt_type=None, time=None):
        """Write an array with optional time dependence.
        
        Arguments:
        array -- a numpy array, list, or tuple
        name -- user-visible name of the array variable
        dt_type -- string type used by DataTank
        time -- time value if this variable is time-varying
        
        This will add a string to expose it in DataTank using the dt_type parameter, 
        which is a DataTank type such as "Array" or "NumberList."  The time parameter 
        is a double-precision floating point value, relative to DataTank's time slider.

        Note that if time dependence is used, the caller is responsible for appending
        "_N" to the variable, where N is an integer >= 0 and strictly increasing 
        with time.  A contrived example follows:
        
        >>> import numpy as np
        >>> f = DTDataFile("foo.dtbin")
        >>> for idx in xrange(10):
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
        bnv = _basename_of_variable(name)
        base_name = "Seq_" + bnv
        if time and base_name not in self._name_offset_map:
            self._write_string(dt_type, base_name)
        elif time is None:
            self._write_string(dt_type, base_name)
            if bnv != name:
                _log_warning("\"%s\" name has implicit time, but no time given" % (name))            
            
        # caller is responsible for appending _index as needed for time series
        self._write_array(array, name)

        if time is not None:
            assert name[-1].isdigit(), "time series names must end with a digit"
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
        >>> for idx in xrange(10):
        ...     s = datetime.now().isoformat()
        ...     f.write_array(s, "PointTest_%d" % (idx), time=idx * 2.)
                
        """
        
        # Expose a time series of type String
        bnv = _basename_of_variable(name)
        base_name = "Seq_" + bnv
        if time and base_name not in self._name_offset_map:
            self._write_string("String", base_name)
        elif time is None:
            self._write_string("String", base_name)
            if bnv != name:
                _log_warning("\"%s\" name has implicit time, but no time given" % (name))
             
        # caller is responsible for appending _index as needed for time series
        self._write_string(string, name)

        if time is not None:
            assert name[-1].isdigit(), "time series names must end with a digit"
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
        
        In addition, any object that implements __dt_type__ and __dt_write__ methods 
        can be passed, which allows saving compound types such as 2D Mesh or 2D Bitmap,
        without bloating up DTDataFile with all of those types.
        
        The __dt_type__ method must return a DataTank type name:
        
            def __dt_type__(self):
                return "2D Mesh"
        
        The __dt_write__ method should use write_anonymous to save all variables as
        required for the object.  The datafile argument is this DTDataFile instance.
        Note that __dt_write__ must not expose the variable by adding a "Seq" name, as
        that is the responsibility of DTDataFile as the higher-level object.
        
            def __dt_write__(self, datafile, name):
                ...
                datafile.write_anonymous( ... , name)

        """
        
        #
        # The Obj-C programmer in me hates using isinstance here, but I'm not sure
        # what else to do, short of adding a separate write method for each data
        # type.  The basic problem is that you have to map to specific types in order
        # to use DTDataFile, and everything needs to be converted to an ndarray or
        # a string in the end.
        #
        
        if dt_writer(obj):
            self._dt_write(obj, name, time)
        elif isinstance(obj, basestring):
            self.write_string(obj, name, time=time)
        elif isinstance(obj, (float, int)):
            # convert to an array, but allow numpy to pick the type for a float
            if isinstance(obj, float):
                array = np.array((obj,))  
            else:
                # coerce int to int32, since it defaults to int64 on 64 bit systems, but check size
                assert obj <= _INT32_MAX and obj >= _INT32_MIN, "integer too large for 32-bit type"
                array = np.array((obj,), dtype=np.int32)
            self.write_array(array, name, dt_type="Real Number", time=time)
        elif isinstance(obj, (tuple, list)) and len(obj) and isinstance(obj[0], basestring):
            # this will be a StringList
            offsets = []
            char_list = []
            current_offset = 0
            # flat list of character codes, with each string separated by a null
            for string in obj:
                string = (string + "\0").encode("utf-8")
                char_list += [ord(x) for x in string]
                offsets.append(current_offset)
                current_offset += len(string)
            self._write_array(np.array(offsets, dtype=np.int32), name + "_offs")
            self.write_array(np.array(char_list, dtype=np.int8), name, dt_type="StringList", time=time)
        elif isinstance(obj, (np.ndarray, tuple, list)):
            # need to be able to call shape
            array = _ensure_array(obj)
            # DTDataStorage::WriteOne changes the type based on the dimensions, so do the same.
            if dt_type is None:
                dt_type = "NumberList" if len(array.shape) == 1 else "Array"
            self.write_array(array, name, dt_type=dt_type, time=time)
        else:
            assert False, "unhandled object type" + str(type(obj))
            
    def __setitem__(self, name, value):
        # support for dictionary-style setting; calls write()
        self.write(value, name)

