#!/usr/bin/env python

def _times_considered_same(t1, t2):
    """docstring for _times_considered_same"""
    return abs(t1 - t2) <= 0.000001 * (t1 + t2)

class DTSeries(object):
    """Base class for series support"""
    def __init__(self, datafile, series_name, series_type):
        super(DTSeries, self).__init__()
        self._name = series_name
        self._time_values = []
        
        # TODO: assert empty file
        self._datafile = datafile
        self._type = series_type
        
        # add series type descriptor
        datafile[series_name] = series_type
    
    def datafile(self):
        return self._datafile
        
    def type(self):
        return self._series_type
        
    def savecount(self):
        return len(self.time_values())
        
    def name(self):
        return self._name
        
    def basename(self, count=None):
        if count == None:
            count = self.savecount() - 1
        assert count >= 0, "invalid count"
        return "%s_%d" % (self.name(), count)
    
    def time_values(self):
        return self._time_values
        
    def last_time(self):
        return self.time_values()[-1] if self.savecount() else None
        
    def shared_save(self, time):
        
        # DTSource logs error and returns false here; assert since these are really
        # programmer errors in our case.
        assert time >= 0, "time must not be negative"
        if len(self.time_values()):
            assert time > self.last_time(), "time must be strictly increasing"
        
        if self.last_time() >= 0:
             assert _times_considered_same(time, self.last_time()) == False, "time values too close together"
             
        self._time_values.append(time)
        self._datafile.write_anonymous(time, self.basename() + "_time")
        
class DTSeriesGroup(DTSeries):
    """Base series group class"""
    def __init__(self, datafile, name):
        super(DTSeriesGroup, self).__init__(datafile, name, "Group")
        
    def write_structure(self):
        
        basename = "SeqInfo_" + self.name()
        
        self.datafile().write_anonymous("OutputArray", basename + "_1N")
        self.datafile().write_anonymous("Array", basename + "_1T")
        
        self.datafile().write_anonymous("OutputString", basename + "_2N")
        self.datafile().write_anonymous("String", basename + "_2T")
        
        self.datafile().write_anonymous("Output Number", basename + "_3N")
        self.datafile().write_anonymous("Real Number", basename + "_3T")
        
        self.datafile().write_anonymous(3, basename + "_N")
        self.datafile().write_anonymous("Group", basename)
        
    def add(self, time, array_value, string_value, number_value):
        
        if self.savecount() == 0:
            self.write_structure()
            
        # DTSeries::SharedSave
        self.shared_save(time)
        
        # DTRetGroup::Write
        self.datafile().write_anonymous(array_value, self.basename() + "_OutputArray")
        self.datafile().write_anonymous(string_value, self.basename() + "_OutputString")
        self.datafile().write_anonymous(number_value, self.basename() + "_Output Number")
        self.datafile().write_anonymous(np.array([], dtype=np.float64), self.basename())

if __name__ == '__main__':
    
    import numpy as np
    from datatank_py.DTDataFile import DTDataFile
    from datatank_py.DTProgress import DTProgress
    
    with DTDataFile("Output.dtbin", truncate=True) as df:
        
        progress = DTProgress()
    
        group = DTSeriesGroup(df, "Var")
        group.add(0.0, (0, 1, 2, 3.), "String 1", 1)
        # progress.update_percentage(1 / 3.)
        # group.add(1.1, (4, 5, 6, 7.), "String 1.1", 1.1)
        # progress.update_percentage(2 / 3.)
        # group.add(1.5, (8, 9, 10, 11.), "String 1.5", 1.5)
        # progress.update_percentage(1.)
        
        for v in df.variable_names():
            print "%s = %s" % (v, df[v])
