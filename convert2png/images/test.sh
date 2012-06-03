#!/bin/sh

CONVERT=$HOME/BuildProducts/Debug/convert2png
rm -f *.png

SCALE=10

for f in *.pdf ; do    
    $CONVERT -s $SCALE $f $f.png
done

for f in *.ps ; do
    $CONVERT -s $SCALE $f $f.png
done
