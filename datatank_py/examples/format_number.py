#!/usr/bin/env python

import os, sys
from datatank_py.DTDataFile import DTDataFile
from time import clock

if __name__ == '__main__':
    
    #
    # This program replaces a standard DataTank External Program module
    # in C++.  Note that it must be executable (chmod 755 in Terminal)
    # and gdal and numpy are required.
    #
    
    input_file = DTDataFile("Input.dtbin")
    format_string = input_file["Format String"]
    number = input_file["Number"]
    input_file.close()
    
    # record start time and create a list for errors
    start_time = clock()
    errors = []
    
    # run the computation, here using an exception handler to catch problems
    output_string = ""
    try:
        output_string += format_string % (number)
    except Exception, e:
        errors.append("Exception raised: %s" % (e))
    
    # create or truncate the output file    
    with DTDataFile("Output.dtbin", truncate=True) as output_file:
        # record computation time
        output_file["ExecutionTime"] = clock() - start_time
        
        # DataTank seems to display stderr instead of the error list, so
        # make sure to write to both.
        if len(errors):
            output_file["ExecutionErrors"] = errors
            sys.stderr.write("%s\n" % errors)
            
        else:
            # save the output variable; this will be visible to DataTank
            #sys.stderr.write("%s: %s\n" % (type(output_string), output_string))
            output_file["Var"] = output_string
