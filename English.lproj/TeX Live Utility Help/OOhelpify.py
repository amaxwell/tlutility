# -*- coding: UTF-8 -*-
#
# Copyright 2008 Omni Development, Inc.  All rights reserved.
#
# Omni Source Code software is available from the Omni Group on their
# web site at www.omnigroup.com.
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# Any original copyright notices and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/Staff/wvh/Helpify/OOhelpify.py 137210 2010-08-12 01:42:01Z wvh $

import sys, os, shutil, re, commands, codecs
from xml.dom.minidom import parseString

reload(sys)
sys.setdefaultencoding('utf-8')

TEXT_NODE = 3
IMAGE_PATH = "HelpImages/"
COMPANY_URL = "www.example.com"
INDEXER_ARGS = "-s en -C -a -v -f"

bookTitle = ""
attachments = {}
links = []
anchors = []
doNavi = True
outputPath = ""


def scrubAnchor(text):
    anchor = re.sub('<span class="Drop">.*?</span>', '', text)
    anchor = re.sub('\&.*?\;', '', anchor)
    anchor = re.sub('<.*?>', '', anchor)
    anchor = re.sub('\W', '', anchor)
    return anchor

def fileHeader(theFile, title, robots="", isTop=False, url="", description=""):
    """Print to a file the stuff we need at the top of an HTML document."""

    title = re.sub('<.*?>', '', title).strip()
    
    topString = ""
    if isTop:
        topString = """<meta name="AppleTitle" content="%(title)s">
        <meta name="AppleIcon" content="%(title)s/../../Icon.icns">
        """ % {
        'title': title
        }
    
    print >> theFile, """<html>

    <head>
        <meta http-equiv="content-type" content="text/html;charset=utf-8">
		<title>%(title)s</title>
		%(topString)s
		%(robots)s
		<meta name="description" content="%(description)s">
        <link rel="stylesheet" href="help.css" type="text/css">
    </head>
    <body>""" % {
    'title': title,
    'topString': topString,
    'robots': robots,
    'description': description
    }


def fileFooter(theFile):
    """Print to a file the stuff we need at the bottom of an HTML document."""
    print >> theFile, """
    </body>
</html>"""


def fileFrames(theFile, title, anchor):
    """Write to a file the frameset to hold a table of contents."""
    print >> theFile, """<html>

    <head>
        <meta http-equiv="content-type" content="text/html;charset=utf-8">
        <meta name="robots" content="noindex">
        <title>%(title)s</title>
        <link href="help.css" rel="stylesheet" media="all">
    </head>

    <frameset cols="170,*">
        <frame name="left" noresize src="%(anchor)s.html">
        <frame name="right" noresize src="empty.html">
        <noframes>

            No frames.

        </noframes>
    </frameset>

</html>
    """ % {
    'title': title,
    'anchor': anchor
    }


def digItem(theItem, level, inheritedStyle=[], destReached=False):
    """The horrific recursive function that examines an outline item, decides what it is and what to do with it, and then processes all of its children"""
    
    output = ''
    applicableStyles = []
    divStyles = []
    
    itemStyles = findStyles(theItem)
    while len(itemStyles) < 2:
        itemStyles.append([])
    if itemStyles[0]: applicableStyles.extend(itemStyles[0])
    if inheritedStyle: applicableStyles.extend(inheritedStyle) 
    
    possibleDivStyles = ['Pro', 'List', 'ListItem', 'Steps', 'Box', 'Destination', 'Anchor', 'Pre', 'Variables']
    for oneStyle in possibleDivStyles:
        if oneStyle in applicableStyles:
            divStyles.append(oneStyle)
            applicableStyles.remove(oneStyle)
    
    #if not len(applicableStyles): applicableStyles = ['plain']
    #print applicableStyles
    
    preness = None
    if 'Pre' in divStyles:
        preness = 'Pre'
    
    text = itemText(theItem, preness)
    anchor = ""
    
    if destReached:         #we're already at the destination; we're just filling in the text of the page.
    
        if 'Anchor' in divStyles:

            output += """<a name="%s"></a>""" % (scrubAnchor(itemText(theItem)).lower())
            if scrubAnchor(itemText(theItem)).lower() not in anchors:
                anchors.append(scrubAnchor(itemText(theItem)).lower())
        
        elif 'List' in divStyles or 'Steps' in divStyles:
            
            listType = 'ul'
            if 'Steps' in divStyles: listType = 'ol'
            
            output += "        " + "    "*level + '<%s class="item %s">' % (listType, ' '.join(divStyles))
            if text:
                output += '<span class="%(classes)s">%(text)s</span>' % {
                    'classes': ' '.join(applicableStyles),
                    'text': text
                    }
            
            for childrenNode in findSubNodes(theItem, 'children'):
                for itemNode in findSubNodes(childrenNode, 'item'):
                    subText = digItem(itemNode, level+1, ['ListItem'], destReached=True)
                    output += subText['text']
                    
            output += "        " + "    "*level + "</%s>\n" % (listType)
        
        elif 'ListItem' in divStyles:
            
            output += "        " + "    "*level + '<li class="item %s">' % (' '.join(divStyles))
            if text:
                output += '<span class="%(classes)s">%(text)s</span>' % {
                    'classes': ' '.join(applicableStyles),
                    'text': text
                    }
                    
            output += "        " + "    "*level + "</li>\n"
        
        else:
        
            output += "        " + "    "*level + '<div class="item %s">' % (' '.join(divStyles))
            if text:
                output += '<span class="%(classes)s">%(text)s</span>' % {
                    'classes': ' '.join(applicableStyles),
                    'text': text
                    }
            
            for childrenNode in findSubNodes(theItem, 'children'):
                for itemNode in findSubNodes(childrenNode, 'item'):
                    subText = digItem(itemNode, level+1, itemStyles[1], destReached=True)
                    output += subText['text']
                    
            output += "        " + "    "*level + "</div>\n"
            
        if 'Pre' in divStyles:
            output = "<pre>" + output + "</pre>"
            
        text = output       #send back all of the text of the contained nodes, formatted properly
    
    else:                   #we're not at the destination yet
        
        if "Variables" in divStyles:    #wait, actually we're at the special variable section; let's parse those guys
            #uh, there has got to be a better way to do this.
            oneKey = ""
            global IMAGE_PATH, COMPANY_URL, INDEXER_ARGS
            for childrenNode in findSubNodes(theItem, 'children'):
                for itemNode in findSubNodes(childrenNode, 'item'):
                    for valuesNode in findSubNodes(itemNode, 'values'):
                        for textNode in findSubNodes(valuesNode, 'text'):
                            for pNode in findSubNodes(textNode, 'p'):
                                for runNode in findSubNodes(pNode, 'run'):
                                    for litNode in findSubNodes(runNode, 'lit'):
                                        oneKey = unicode(litNode.firstChild.nodeValue)
                    for childrenNode in findSubNodes(itemNode, 'children'):
                        for itemNode in findSubNodes(childrenNode, 'item'):
                            for valuesNode in findSubNodes(itemNode, 'values'):
                                for textNode in findSubNodes(valuesNode, 'text'):
                                    for pNode in findSubNodes(textNode, 'p'):
                                        for runNode in findSubNodes(pNode, 'run'):
                                            for litNode in findSubNodes(runNode, 'lit'):
                                                oneValue = unicode(litNode.firstChild.nodeValue)
                                                if oneKey == "Image Path": IMAGE_PATH = oneValue
                                                elif oneKey == "Company URL": COMPANY_URL = oneValue
                                                elif oneKey == "Help Indexer utility arguments": INDEXER_ARGS = oneValue
                                        
                    

        else:                           #yeah, we need to make a sub-page for this item
            anchor = scrubAnchor(text)
            
            if "Destination" in divStyles:
                destReached = True
            
            newFileName = anchor + '.html'
            level2File = open(outputPath + '/' + newFileName, 'w')
            roboString = """<meta name="robots" content="noindex">"""
            
            if destReached:
                roboString = ""
            elif level == 2:
                divStyles.append("toc-left")
            else:
                divStyles.append("toc-right")
            
            abstract = ""
            # turn the note into an abstract; suppress this if your notes are still notes :D
            for noteNode in findSubNodes(theItem, 'note'):
                for textNode in findSubNodes(noteNode, 'text'):
                    for pNode in findSubNodes(textNode, 'p'):
                        for runNode in findSubNodes(pNode, 'run'):
                            for litNode in findSubNodes(runNode, 'lit'):
                                abstract += litNode.toxml('utf-8')
            abstract = re.sub('<.*?>', '', abstract).strip()
                
            fileHeader(level2File, text, roboString, isTop=False, url=newFileName, description=abstract)
            
            print >> level2File, """
            <div class="%(classes)s">
            """ % {
            'classes': ' '.join(divStyles)
            }
            
            subTextList = []
            
            if destReached:
                subTextList.append({'text': '        <h2>' + text + '</h2>'})
            
            # time to look at all the children of this node
            
            for childrenNode in findSubNodes(theItem, 'children'):
                for itemNode in findSubNodes(childrenNode, 'item'):
                    subTextList.append(digItem(itemNode, level+1, itemStyles[1], destReached))
            
            #move the title of the page after any anchors that might be at the beginning of the page text
            i = 1
            while len(subTextList) > i and subTextList[i]['text'].find('<a name') > -1:
                i += 1
            if len(subTextList) > 0:
                titleItem = subTextList.pop(0)
                subTextList.insert(i-1, titleItem)
                
            
            if destReached:
                for subText in subTextList:
                    print >> level2File, subText['text']
            else:
                print >> level2File, '        <h2>' + text + '</h2>'
                print >> level2File, '        <ul>'
                for subText in subTextList:
                    target = "_top"
                    #if level >= 2 and not subText['destination']:
                    #    target = "right"
                    frameness = ''
                    print >> level2File, '<li><a href="%(anchor)s.html" target="%(target)s">%(text)s</a></li>' % {
                        'anchor': subText['anchor'] + frameness,
                        'target': target,
                        'text': subText['text']
                        }          
                print >> level2File, '        </ul>'
                
            print >> level2File, """
            </div>
            """
            
            #make a navi thingy; suppress this stuff if you are going to index, then emit the help again with the links in it
            
            if doNavi:
                prevAnchor = ""
                prevTitle = ""
                if theItem.previousSibling and theItem.previousSibling.previousSibling:
                    prevTitle = itemText(theItem.previousSibling.previousSibling)
                    prevAnchor = scrubAnchor(prevTitle)
                nextAnchor = ""
                nextTitle = ""
                if theItem.nextSibling and theItem.nextSibling.nextSibling:
                    nextTitle = itemText(theItem.nextSibling.nextSibling)
                    nextAnchor = scrubAnchor(nextTitle)
                
                print >> level2File, """
            <div class="bottom-nav">
            """
                
                if prevAnchor:
                    print >> level2File, """
                    <span class="left-nav"><a href="%(anchor)s.html">← %(title)s</a></span>
                """ % {
                    'anchor': prevAnchor,
                    'title': prevTitle
                    }
                
                if nextAnchor:
                    print >> level2File, """
                    <span class="right-nav"><a href="%(anchor)s.html">%(title)s →</a></span>
                """ % {
                    'anchor': nextAnchor,
                    'title': nextTitle
                    }
                    
                #  <a href="top.html">Top ↑</a>      
                print >> level2File, """
                &nbsp;<br/>&nbsp;
            </div>
            """
            
            #end navi thingy
            
            fileFooter(level2File)
    
    result = {}
    result['anchor'] = anchor
    result['text'] = text
    result['destination'] = destReached
    return result
        

def findSubNodes(theParent, kind):              # get all child nodes with certain tagName
    foundNodes = []
    for subNode in theParent.childNodes:
        if (subNode.nodeType != TEXT_NODE) and (subNode.tagName == kind):
            foundNodes.append(subNode)
    return foundNodes


def itemText(theItem, style=None):              # find out the text of an item and send it back nicely formatted for html and css
    itemStyles = findStyles(theItem)
    if itemStyles and u'Variables' in itemStyles[0]:
        return ''
    constructedText = u''
    for valuesNode in findSubNodes(theItem, 'values'):
        for textNode in findSubNodes(valuesNode, 'text'):
            for pNode in findSubNodes(textNode, 'p'):
                for runNode in findSubNodes(pNode, 'run'):
                    runStyles = []
                    linkage = False
                    for styleNode in findSubNodes(runNode, 'style'):
                        for inheritedStyleNode in findSubNodes(styleNode, 'inherited-style'):
                            runStyles.append(inheritedStyleNode.getAttribute('name'))
                        if "Link" in runStyles:
                            runStyles.remove("Link")
                            linkage = True
                        if runStyles:
                            constructedText += '<span class="%s">' % (" ".join(runStyles))
                    for litNode in findSubNodes(runNode, 'lit'):
                        for leaf in litNode.childNodes:
                            leafText = evaluateLeaf(leaf)
                            if linkage:
                                constructedText += """<a href="help:anchor='%(anchor)s' bookID='%(bookTitle)s'">%(text)s</a>""" % {
                                    'anchor': scrubAnchor(leafText).lower(),
                                    'bookTitle': bookTitle,
                                    'text': leafText
                                    }
                                if scrubAnchor(leafText).lower() not in links:
                                    links.append(scrubAnchor(leafText).lower())
                            else:
                                constructedText += leafText
                    if runStyles:
                        constructedText += '</span>'
                if style == 'Pre':
                    constructedText += '\n'
    return constructedText


def evaluateLeaf(theElement):           # find out if an element is text or attachment and send back the appropriate html
    if (theElement.nodeType == TEXT_NODE):
        htmlText = unicode(theElement.toxml())
        htmlText = htmlText.replace("""“""", "&ldquo;")
        htmlText = htmlText.replace("""”""", "&rdquo;")
        htmlText = htmlText.replace("""‘""", "&lsquo;")
        htmlText = htmlText.replace("""’""", "&rsquo;")
        return htmlText
    elif (theElement.tagName == 'cell'):
        if theElement.getAttribute('href'):
            return '<a href="%(href)s">%(name)s</a>' % {
                'href': theElement.getAttribute('href'),
                'name': theElement.getAttribute('name')
                }
        else:
            fileName = attachments[theElement.getAttribute('refid')]
            fileName = re.sub("\d*__\S*?__", "", fileName)
            extension = fileName.split('.')[-1].lower()
            if extension == 'png' or extension == 'jpg':
                return '<img src="%s" class="inline-image">' % (IMAGE_PATH + fileName)
            else:
                return '<a href="%(fileName)s">%(name)s</a>' % {
                    'fileName': fileName,
                    'name': theElement.getAttribute('name')
                    }


def findStyles(theElement):
    """returns list of lists; inside list represents styles; outside list represents stack levels"""
    itemStyles = []
    for styleNode in findSubNodes(theElement, 'style'):
        nextStyle = []
        for inheritedStyleNode in findSubNodes(styleNode, 'inherited-style'):
            nextStyle.append(inheritedStyleNode.getAttribute('name'))
        itemStyles.append(nextStyle)
    return itemStyles
    

def main():

    if len(sys.argv) >= 2:
    
        global outputPath
        inputPath = sys.argv[1]
        if inputPath[-1] == '/':
            inputPath = inputPath[0:-1]
        inputTitle = inputPath.split('/')[-1].split('.')[0]
        outputPath = inputPath + '/../%s/' % (inputTitle)
        if not os.access(outputPath, os.F_OK):
            os.mkdir(outputPath)
        if not os.access(outputPath + '/HelpImages', os.F_OK):
            os.mkdir(outputPath + '/HelpImages')
        
        if os.access(outputPath + '/../help.css', os.F_OK):
            shutil.copyfile(outputPath + '/../help.css', outputPath + '/help.css')
        if os.access(outputPath + '/../Icon.png', os.F_OK):
            shutil.copyfile(outputPath + '/../Icon.png', outputPath + '/HelpImages/Icon.png')
        
        f = codecs.open(inputPath + '/contents.xml', 'r', 'utf-8')
        xmlString = f.read().encode('utf-8')
        theTree = parseString(xmlString)
        f.close()
        
        docNode = theTree.documentElement
        
        rootNode = None
        for oneNode in findSubNodes(docNode, 'root'):
            rootNode = oneNode
            
        for attachmentsNode in findSubNodes(docNode, 'attachments'):
            for attachmentNode in findSubNodes(attachmentsNode, 'attachment'):
                if attachmentNode.getAttribute('href'):
                    attachments[attachmentNode.getAttribute('id')] = attachmentNode.getAttribute('href')
                    if attachmentNode.getAttribute('href').find("__#$!@%!#__") == -1:       ## get rid of INSANE outliner dupe files
                        shutil.copyfile((inputPath + '/' + attachmentNode.getAttribute('href')), outputPath + '/HelpImages/' + attachmentNode.getAttribute('href'))
        
        
        #This is where the files get generated. If we are adding navigation links, then generate the pages once without navi links for indexing, then once more with the navi links. If we are not adding navi, then just generate the pages once and index them. Also, running through the outline twice ensures that the variables are found and set properly in the first pass, to be used in the second pass.
        naviIterations = [False]
        if doNavi:
            naviIterations = [False, True]
        
        for oneNaviIteration in naviIterations:
            
            for oneNode in rootNode.childNodes:
                if (oneNode.nodeType != TEXT_NODE) and (oneNode.tagName == 'item'):
                    text = itemText(oneNode, 'title')
                    global bookTitle
                    bookTitle = text
                    
                    tocFile = open(outputPath + '/top.html', 'w')
                    fileHeader(tocFile, bookTitle, """<meta name="robots" content="noindex">""", isTop=True, url='top.html')
                    
                    print >> tocFile, """
                        <div class="top-all">
                            <div class="top-title">
                                <img src="%(imagePath)sIcon.png" alt="Application Icon" height="128" width="128" border="0">
                                <h1>%(bookTitle)s</h1>
                                <p><a href="http://%(url)s">%(url)s</a></p>
                            </div>
                            <div class="top-contents">
                                <ul>
                    """ % {
                        'imagePath': IMAGE_PATH,
                        'bookTitle': bookTitle,
                        'url': COMPANY_URL
                        }
                    
                    for childrenNode in findSubNodes(oneNode, 'children'):
                        for itemNode in findSubNodes(childrenNode, 'item'):
                            subText = digItem(itemNode, 2, [])
                            frameness = ''
                            #if not subText['destination']:
                            #    frameFile = open(outputPath + '/' + subText['anchor'] + 'frame.html', 'w')
                            #    fileFrames(frameFile, subText['text'], subText['anchor'])
                            #    frameness = 'frame'
                            if subText['anchor']:
                                print >> tocFile, '<li><a href="%(anchor)s.html">%(text)s</a></li>' % {
                                    'anchor': subText['anchor'] + frameness,
                                    'text': subText['text']
                                    }
                    
                    print >> tocFile, """
                                </ul>
                            </div>
                        </div>
                    """
                    
                    fileFooter(tocFile)
                    tocFile.close()
                
            # create a help index on the iteration that has no navi
            if not oneNaviIteration:
                # In case the user has an atypical "/Developer" directory 
                developerDirPath = commands.getoutput("""/usr/bin/xcode-select -print-path""")
                escapedOutputPath = outputPath.replace(' ', '\ ')

                # On 10.6 and later we can use the hiutil tool and avoid the stuck UI that
                # occurs when using "Help Indexer".
                indexerToolPath = "/usr/bin/hiutil"
                if os.path.exists(indexerToolPath): 
                    helpBookOutputFileName = bookTitle.replace(' ', '\ ') + ".helpindex"
                    escapedHelpIndexPath = escapedOutputPath + helpBookOutputFileName
                    indexerCommandLine = """%s %s %s %s""" % (indexerToolPath, INDEXER_ARGS, escapedHelpIndexPath, escapedOutputPath)
                else:
                    indexerToolPath = developerDirPath + """/Applications/Utilities/Help\ Indexer.app/Contents/MacOS/Help\ Indexer"""                    
                    indexerCommandLine = """%s %s""" % (indexerToolPath, escapedOutputPath)
                
                print commands.getoutput(indexerCommandLine)
        
        # check that all links are hooked up
        links.sort()
        anchors.sort()
        
        anchorlessLinks = []
        for oneLink in links:
            if oneLink not in anchors:
                anchorlessLinks.append(oneLink)
        
        if len(anchorlessLinks):
            print "You've got some anchorless links:"
            for oneLink in anchorlessLinks:
                print "    ", oneLink
            
            print "\n"
                
        else:
            print "Congratulations, all links are hooked up!"
    
    else:
        print """usage: 
    python OOhelpify.py OutlinerFile.oo3"""


if __name__ == "__main__":
    main()
