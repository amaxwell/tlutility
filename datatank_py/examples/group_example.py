#!/usr/bin/env python
# -*- coding: utf-8 -*-

import numpy as np
import os
from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTProgress import DTProgress
from datatank_py.DTSeries import DTSeriesGroup
from time import clock

if __name__ == '__main__':
    
    input_file = DTDataFile("GEInput.dtbin")
    input_string = input_file["InputString"]
    input_file.close()
    
    start_time = clock()
    
    with DTDataFile("GEOutput.dtbin", truncate=True) as df:
        
        progress = DTProgress()
    
        name_to_type = { "OutputArray":"Array", "OutputString":"String", "Output Number":"Real Number" }
        group = DTSeriesGroup(df, "Var", name_to_type)
        
        values = { "OutputArray":(0, 1, 2, 3), "OutputString":input_string + "1", "Output Number":1 }
        group.add(0.0, values)
        progress.update_percentage(1 / 3.)
        
        values = { "OutputArray":(4, 5, 6, 7), "OutputString":input_string + "2", "Output Number":2 }
        group.add(1.0, values)
        progress.update_percentage(2 / 3.)
        
        values = { "OutputArray":(8, 9, 10, 11), "OutputString":input_string + "3", "Output Number":3 }
        group.add(2.0, values)
        progress.update_percentage(1.)
        
        df["ExecutionTime"] = clock() - start_time
        df["ExecutionErrors"] = [""]
                    
