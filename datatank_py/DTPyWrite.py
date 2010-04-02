#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

def dt_writer(obj):
    """Check to ensure conformance to dt_writer protocol."""
    return hasattr(obj, "__dt_type__") and hasattr(obj, "__dt_write__")

class DTPyWrite(object):
    """Class documenting methods that must be implemented for DTDataFile.
    
    This is never instantiated directly.  DTDataFile checks to ensure that an
    object implements all of the required methods, but you are not required to
    use DTPyWrite as a base class.  It's mainly provided as a convenience and
    formal documentation.
    
    """
    
    def __dt_type__(self):
        """The variable type as required by DataTank.
        
        Returns:
        Variable type as a string
        
        This is a string description of the variable, which can be found in the
        DataTank manual PDF or in DTSource.  It's easiest to look in DTSource, 
        since you'll need to look there for the dt_write implementation anyway.
        You can find the type in the WriteOne() function for a particular class,
        such as
        
        void WriteOne(DTDataStorage &output,const string &name,const DTPath2D &toWrite)
        {
            Write(output,name,toWrite);
            Write(output,"Seq_"+name,"2D Path");
            output.Flush();
        }
        
        where the type is the string "2D Path".  In some cases, it seems that
        multiple type names are recognized; e.g., "StringList" is written by
        DataTank, but "List of Strings" is used in DTSource.  Regardless, this
        is trivial; the DTPath2D.dt_type method looks like this:
        
        def dt_type(self):
            return "2D Path"
        
        """
        
        return "String"
        
    def __dt_write__(self, datafile, name):
        """Write all associated values to a file.
        
        Arguments:
        datafile -- a DTDataFile instance
        name -- the name of the variable as it should appear in DataTank
        
        Returns:
        Nothing
        
        This method collects the necessary components of the compound object and
        writes them to the datafile.  The name is generally used as a base for
        associated variable names, since only one of the components can have the 
        "primary" name.  Again, the DataTank manual PDF or DTSource must be used
        here as a reference (DTSource is more complete).  In particular, you need
        to look at the Write() function implemented in the class:
        
        void Write(DTDataStorage &output,const string &name,const DTPath2D &thePath)
        {
            Write(output,name+"_bbox2D",BoundingBox(thePath));
            Write(output,name,thePath.Data());
        }
        
        Here the bounding box is written as "name_bbox2D"; this is just a 4 element
        double-precision array.  Next, the actual path array is saved under the name
        as passed in to the function.  The equivalent Python implementation is
        
        def dt_write(self, datafile, name):
            datafile.write_anonymous(self.bounding_box(), name + "_bbox2D")
            datafile.write_anonymous(np.dstack((self._xvalues, self._yvalues)), name)
        
        Note that DTDataFile.write_anonymous should be used in order to avoid any
        variable name munging (prepending "Seq_" in order to make the variable visible
        in DataTank).
        
        """
        
        datafile.write_anonymous("ERROR: forgot to override dt_write", name)

