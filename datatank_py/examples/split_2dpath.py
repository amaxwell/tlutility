#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This software is under a BSD license.  See LICENSE.txt for details.

from datatank_py.DTDataFile import DTDataFile
from datatank_py.DTPath2D import DTPath2D
from datatank_py.DTPoint2D import DTPoint2D
from datatank_py.DTPointCollection2D import DTPointCollection2D
from datatank_py.DTPointValueCollection2D import DTPointValueCollection2D

import numpy as np
from bisect import bisect_right
from time import time
import sys

def _find_le(a, x):
    'Find rightmost value less than or equal to x'
    i = bisect_right(a, x)
    if i:
        return i-1, a[i-1]
    raise ValueError
    
def _pp_distance(p1, p2):
    """Euclidean distance between two points"""
    dx = p2.x - p1.x
    dy = p2.y - p1.y
    r = np.sqrt(dx * dx + dy * dy)
    return r

def _divide_path_with_segment_spacing(path, required_distance):
    """Divide a path into points at equal intervals.
    
    Arguments:
    path -- DTPath2D with no subpaths
    required_distance -- Distance between successive points
    
    Returns:
    DTPointValueCollection2D containing the points and their distances
    from the start of the path.
    
    This is designed to work with straight-line paths, as it only considers
    the Euclidean distance between points.  If the input path has sufficient
    point resolution, results for curved paths may be adequate.
    
    """
    
    points = path.point_list()
    distances = []
    
    p1 = points[0]
    for p2 in points[1:]:
        distances.append(_pp_distance(p1, p2))
        p1 = p2
    
    path_length = np.sum(distances)
    num_elements = int(path_length / required_distance)
    cum_dist = np.cumsum(distances)
    
    point_values = DTPointValueCollection2D(DTPointCollection2D([], []), [])
    point_values.add_point_value(points[0], 0)
    for el in xrange(1, num_elements + 1):
        
        distance_to_find = el * required_distance
        idx, dist = _find_le(cum_dist, distance_to_find)
        p1 = points[idx - 1]
        p2 = points[idx]
        remainder = distance_to_find - dist
        assert remainder >= 0, "negative distance"
        
        dx = p2.x - p1.x
        dy = p2.y - p1.y
        r = np.sqrt(dx * dx + dy * dy)
        
        delta_y = remainder * dy / r
        delta_x = remainder * dx / r
        p3 = DTPoint2D(p1.x + delta_x, p1.y + delta_y)
        point_values.add_point_value(p3, distance_to_find)
        
    return point_values    
    
def _test():
    
    with DTDataFile("split_2dpath.dtbin", truncate=True) as df:
        xvalues = np.linspace(0, 10, num=100)
        yvalues = np.sin(xvalues)
        xvalues = np.append(xvalues, np.flipud(xvalues))
        xvalues = np.append(xvalues, xvalues[0])
        yvalues = np.append(yvalues, -yvalues)
        yvalues = np.append(yvalues, yvalues[0])
        path = DTPath2D(xvalues, yvalues)
        df["Path"] = path
        df["PointValues"] = _divide_path_with_segment_spacing(path, 0.5)
    
if __name__ == '__main__':
    
    #
    # This is a DataTank plugin that is intended to find points on a path
    # that are some user-specified distance apart.  It works well with a
    # straight-line transect, say for creating a distance scale or choosing
    # discrete stations for further analysis.  You are only guaranteed to get
    # a point at the starting endpoint.
    #
    # It will only work properly with curved paths if you have a sufficiently
    # refined path.  Even then, you still have to watch the error tolerances.
    #
    
    start_time = time()
    errors = []
            
    try:
        input_file = DTDataFile("Input.dtbin")
        required_distance = input_file["Distance"]
        assert required_distance > 0, "distance must be greater than zero"
        path = DTPath2D.from_data_file(input_file, "Path")
        input_file.close()
        point_values = _divide_path_with_segment_spacing(path, float(required_distance))
    except Exception, e:
        errors.append(str(e))
    
    # create or truncate the output file    
    with DTDataFile("Output.dtbin", truncate=True) as output_file:
        # record computation time
        output_file.write_anonymous(time() - start_time, "ExecutionTime")
        
        # DataTank seems to display stderr instead of the error list, so
        # make sure to write to both.
        if len(errors):
            output_file.write_anonymous(errors, "ExecutionErrors")
            sys.stderr.write("%s\n" % errors)
            
        else:
            # save the output variable; this will be visible to DataTank
            output_file["Var"] = point_values
