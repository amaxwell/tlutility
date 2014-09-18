#!/bin/bash

sh texdist_common.sh '2014-Basic'

PROCESSOR=`/usr/bin/uname -p`

if [[ ! -d /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic ]]; then
	mkdir -p  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/AllTexmf
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Doc
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Programs
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Resources
	mkdir -p /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Resources/English.lproj
	cp ./TeXDistVersion  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/TeXDistVersion
	chmod 644 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/TeXDistVersion
	cp ./Description.rtf  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Resources/English.lproj/Description.rtf
	chmod 644  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Resources/English.lproj/Description.rtf
	ln -s ../../../../../../usr/local/texlive/2014basic/texmf-dist/doc/info /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Info
	ln -s ../../../../../../usr/local/texlive/2014basic/texmf-dist/doc/man /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Man
	ln -s ../../../../../../usr/local/texlive/2014basic /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Root
	ln -s ../../../../../../usr/local/texlive/2014basic/texmf-local /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/TexmfLocal
	ln -s ../../../../../../usr/local/texlive/2014basic/texmf-var /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/TexmfSysVar
	ln -s ../../../../../../../usr/local/texlive/2014basic/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Programs/i386
	ln -s ../../../../../../../usr/local/texlive/2014basic/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Programs/powerpc
	ln -s ../../../../../../../usr/local/texlive/2014basic/bin/universal-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Programs/ppc
	ln -s ../../../../../../../usr/local/texlive/2014basic/bin/x86_64-darwin /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Programs/x86_64
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Doc/texmf-dist-doc
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Doc/texmf-doc
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Doc/texmf-doc-doc
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Doc/texmf-var-doc
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/AllTexmf/texmf
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-dist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/AllTexmf/texmf-dist
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-dist/doc /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/AllTexmf/texmf-doc
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-var /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/AllTexmf/texmf-var
	ln -s ../../../../../../../usr/local/texlive/2014basic/texmf-local /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/AllTexmf/texmf-local
	if [[ "$PROCESSOR" == "powerpc" ]]; then
		echo "### setting program link powerpc"
		ln -s powerpc  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Programs/texbin
	fi
	if [[ "$PROCESSOR" == "i386" ]]; then
		echo "### setting program link i386"
		ln -s i386  /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Programs/texbin
	fi
    
    # !!! FIXME
	cp "${PKG_PATH}"/Contents/Resources/PrefPane/Info.plist /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Info.plist
	chmod 644 /Library/TeX/Distributions/.FactoryDefaults/TeXLive-2014-Basic/Contents/Info.plist
fi
