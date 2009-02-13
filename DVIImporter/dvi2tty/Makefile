# Makefile for dvi2tty and disdvi       23/01/89   M.J.E. Mol
#
# For BSD Unix use the following CFLAGS definition
# CFLAGS = -Dstrchr=index
#
# This Makefile does not work for MSDOS. Make your 
# own one, or compile by hand.
#
CFLAGS = -Os -g
CC = gcc

all:	dvi2tty disdvi

dvi2tty: dvi2tty.o dvistuff.o
	$(CC) $(CFLAGS) -o dvi2tty dvi2tty.o dvistuff.o

disdvi: disdvi.c commands.h
	$(CC) $(CFLAGS) -o disdvi disdvi.c

dvi2tty.o: dvi2tty.c dvi2tty.h

dvistuff.o: dvistuff.c dvi2tty.h commands.h

clean:
	rm -f dvi2tty disdvi *.o
