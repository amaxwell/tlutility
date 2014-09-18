#!/bin/bash

sh texdist_common.sh '2014'

PROCESSOR=`/usr/bin/uname -p`

if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014 ]]; then
	mkdir -p  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources/English.lproj
    # !!! fixme
	cp ./TeXDistVersion  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TeXDistVersion
	chmod 644 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TeXDistVersion
    # !!! fixme
	cp ./Description.rtf  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources/English.lproj/Description.rtf
	chmod 644  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Resources/English.lproj/Description.rtf
	ln -s ../../../../../../usr/local/texlive/2014/texmf-dist/doc/info /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Info
	ln -s ../../../../../../usr/local/texlive/2014/texmf-dist/doc/man /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Man
	ln -s ../../../../../../usr/local/texlive/2014 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Root
	ln -s ../../../../../../usr/local/texlive/texmf-local /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TexmfLocal
	ln -s ../../../../../../usr/local/texlive/2014/texmf-var /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/TexmfSysVar
	ln -s ../../../../../../../usr/local/texlive/2014/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/i386
	ln -s ../../../../../../../usr/local/texlive/2014/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/powerpc
	ln -s ../../../../../../../usr/local/texlive/2014/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/ppc
	ln -s ../../../../../../../usr/local/texlive/2014/bin/x86_64-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/x86_64
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-dist-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-doc-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Doc/texmf-var-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-dist
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-doc
	ln -s ../../../../../../../usr/local/texlive/2014/texmf-var /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-var
	ln -s ../../../../../../../usr/local/texlive/texmf-local /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/AllTexmf/texmf-local
	if [[ "$PROCESSOR" == "powerpc" ]]; then
		echo "### setting program link powerpc"
		ln -s powerpc  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/texbin
	fi
	if [[ "$PROCESSOR" == "i386" ]]; then
		echo "### setting program link i386"
		ln -s i386  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Programs/texbin
	fi
    # !!! fixme
	cp ./PrefPane/Info.plist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Info.plist
	chmod 644 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014/Contents/Info.plist
fi
