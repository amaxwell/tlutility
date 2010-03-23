#!/usr/bin/env python
# -*- coding: utf-8 -*-

from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTProgress import DTProgress
from datatank_py.DTSeries import DTSeriesGroup
from time import clock

if __name__ == '__main__':
    
    # dummy input file, just as boilerplate
    input_file = DTDataFile("GEInput.dtbin")
    input_string = input_file["InputString"]
    input_file.close()
    
    start_time = clock()
    
    # module is set to expect this filename, instead of the default "Output.dtbin"
    with DTDataFile("GEOutput.dtbin", truncate=True) as df:
        
        # Task groups use DTProgress for the progress bar
        progress = DTProgress()
    
        # Define the group structure using a dictionary, using the variable name as key,
        # and the DataTank type as the value.  This is used to create the file header.
        name_to_type = { "OutputArray":"Array", "OutputString":"String", "Output Number":"Real Number" }
        
        # Create a new DTSeriesGroup instance using that type mapping.  For a task group
        # to be run in DT, we want to use the "Var" name.
        group = DTSeriesGroup(df, "Var", name_to_type)
        
        # Now write some values to the file.  Here again we use a dictionary, with keys the same
        # as in the name_to_type dictionary, and values the actual values we want to write.  Note
        # that there are some type limitations here (no compound types, such as 2D Mesh).
        values = { "OutputArray":(0, 1, 2, 3), "OutputString":input_string + "1", "Output Number":1 }
        group.add(0.0, values)
        
        # Update the progress bar at each step
        progress.update_percentage(1 / 3.)
        
        # write more data...
        values = { "OutputArray":(4, 5, 6, 7), "OutputString":input_string + "2", "Output Number":2 }
        group.add(1.0, values)
        progress.update_percentage(2 / 3.)
        
        # write more data...
        values = { "OutputArray":(8, 9, 10, 11), "OutputString":input_string + "3", "Output Number":3 }
        group.add(2.0, values)
        progress.update_percentage(1.)
        
        # save execution time, and errors as a string list
        df["ExecutionTime"] = clock() - start_time
        df["ExecutionErrors"] = [""]
                    
