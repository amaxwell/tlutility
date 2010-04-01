#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

import os, sys
from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTProgress import DTProgress
from time import clock, sleep

if __name__ == '__main__':
    
    #
    # This program replaces a standard DataTank External Program module
    # in C++.  Note that it must be executable (chmod 755 in Terminal).
    #
    
    input_file = DTDataFile("Input.dtbin")
    number = input_file["Number"]
    input_file.close()
    
    # record start time and create a list for errors
    start_time = clock()
    errors = []
    
    values = []
    progress = DTProgress()
    
    # sleep in a loop just to slow things down enough
    for idx in xrange(int(number)):
        values.append(idx)
        progress.update_percentage(idx / float(number))
        sleep(0.1)
    
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
            output_file["Var"] = values
