//
//  main.m
//  convert2png
//
//  Created by Adam R. Maxwell on 05/22/12.
//  Copyright (c) 2012 Adam R. Maxwell. All rights reserved.
//
/*
 This software is Copyright (c) 2007-2012
 Adam Maxwell. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 - Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 - Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in
 the documentation and/or other materials provided with the
 distribution.
 
 - Neither the name of Adam Maxwell nor the names of any
 contributors may be used to endorse or promote products derived
 from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <AppKit/AppKit.h>

@interface NSBitmapImageRep (SKExtensions)
- (NSRect)foregroundRect;
@end

#define SCALE_FACTOR 2

static void usage()
{
    fprintf(stderr, "  Usage:\n");
    fprintf(stderr, "  convert2png [-s scale] input_file output_file\n");
    fprintf(stderr, "  -s\t integer scaling factor to increase pixel density (default is 2)\n");
}

static CFStringRef UTIForPath(NSString *path)
{    
    NSURL *fileURL = [NSURL fileURLWithPath:path];
        
    FSRef fileRef;    
    CFTypeRef theUTI;
    if (CFURLGetFSRef((CFURLRef)fileURL, &fileRef)) {
        
        // kLSItemContentType returns a CFStringRef, according to the header
        OSStatus err = LSCopyItemAttribute(&fileRef, kLSRolesAll, kLSItemContentType, &theUTI);
        if (noErr != err) {
            fprintf(stderr, "Unable to determine type of file %s (%s)\n", [path fileSystemRepresentation], GetMacOSStatusErrorString(err));
            theUTI = NULL;
        }
    }
        
    return (CFStringRef)[(NSString *)theUTI autorelease];
}

int main(int argc, char * const argv[])
{

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    if (argc < 3 || argc > 5) {
        usage();
        fflush(stderr);
        exit(EXIT_FAILURE);
    }
    
    int ch, scaleFactor = SCALE_FACTOR;
    while ((ch = getopt(argc, argv, "s:h")) != -1) {
        switch (ch) {
            case 's':
                scaleFactor = atoi(optarg);
                break;
            case 'h':
            case '?':
                usage();
                fflush(stderr);
                exit(EXIT_FAILURE);
        }
    }
    
    NSString *inputPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[optind] length:strlen(argv[optind])];
    NSString *outputPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[optind + 1] length:strlen(argv[optind + 1])];

    argc -= optind;
    argv += optind;

    /*
     +[NSImageRep imageRepWithContentsOfFile:] should do this for us, but it's
     returning nil on 10.6.8 and 10.7.  +[NSImageRep imageFileTypes] also returns
     nothing, so apparently it's just been broken for years.  Way lame.
     */
    NSImageRep *imageRep = nil;
    
    CFStringRef theUTI = UTIForPath(inputPath);
    if (UTTypeConformsTo(theUTI, kUTTypePDF)) {
        imageRep = [NSPDFImageRep imageRepWithContentsOfFile:inputPath];
    }
    else if (UTTypeConformsTo(theUTI, CFSTR("com.adobe.postscript"))) {
        imageRep = [NSEPSImageRep imageRepWithContentsOfFile:inputPath];
    }
    else if (UTTypeConformsTo(theUTI, kUTTypeImage)) {
        imageRep = [NSBitmapImageRep imageRepWithContentsOfFile:inputPath];
    }
    
    // this is a fallback; may require a connection to the window server
    if (nil == imageRep) {
        fprintf(stderr, "unrecognized type %s\n", [(id)theUTI UTF8String]);
        NSImage *img = [[[NSImage alloc] initWithContentsOfFile:inputPath] autorelease];
        imageRep = [[img representations] count] ? [[img representations] objectAtIndex:0] : nil;
    }
    
    if (nil == imageRep) {
        fprintf(stderr, "unable to load file %s as image\n", [inputPath UTF8String]);
        return EXIT_FAILURE;
    }
    
    NSSize inputSize = [imageRep size];
    NSRect inputRect = NSZeroRect;
    inputRect.size = inputSize;
        
    NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                          pixelsWide:inputSize.width * scaleFactor
                                                                          pixelsHigh:inputSize.height * scaleFactor
                                                                       bitsPerSample:8
                                                                     samplesPerPixel:4
                                                                            hasAlpha:YES
                                                                            isPlanar:NO
                                                                      colorSpaceName:NSCalibratedRGBColorSpace
                                                                         bytesPerRow:0
                                                                        bitsPerPixel:0];
    
    const NSRect bitmapRect = NSMakeRect(0, 0, [bitmapRep pixelsWide], [bitmapRep pixelsHigh]);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmapRep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor clearColor] setFill];
    NSRectFillUsingOperation(bitmapRect, NSCompositeCopy);
    [context setImageInterpolation:NSImageInterpolationHigh];
    [context setShouldAntialias:YES];
    [context setCompositingOperation:NSCompositeSourceOver];
    [imageRep drawInRect:bitmapRect];
    [NSGraphicsContext restoreGraphicsState];
    
    const NSRect fgr = [bitmapRep foregroundRect];
    
    NSBitmapImageRep *croppedBitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                              pixelsWide:NSWidth(fgr)
                                                                              pixelsHigh:NSHeight(fgr)
                                                                           bitsPerSample:8
                                                                         samplesPerPixel:4
                                                                                hasAlpha:YES
                                                                                isPlanar:NO
                                                                          colorSpaceName:NSCalibratedRGBColorSpace
                                                                             bytesPerRow:0
                                                                            bitsPerPixel:0];
    
    NSRect smallRect = NSZeroRect;
    smallRect.size = [croppedBitmap size];
    context = [NSGraphicsContext graphicsContextWithBitmapImageRep:croppedBitmap];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor clearColor] setFill];
    NSRectFillUsingOperation(smallRect, NSCompositeCopy);
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMinX(fgr) yBy:NSMinY(fgr)];
    [transform concat];
    NSRectClip(smallRect);
    [context setImageInterpolation:NSImageInterpolationHigh];
    [context setShouldAntialias:YES];
    [context setCompositingOperation:NSCompositeSourceOver];
    [bitmapRep drawInRect:smallRect];
    [NSGraphicsContext restoreGraphicsState];
    
    NSSize actualSize = fgr.size;
    actualSize.width /= scaleFactor;
    actualSize.height /= scaleFactor;
    [croppedBitmap setSize:actualSize];
    
    NSData *outputData = [croppedBitmap representationUsingType:NSPNGFileType properties:nil];
    int ret = [outputData writeToFile:outputPath atomically:YES] ? EXIT_SUCCESS : EXIT_FAILURE;

    [pool release];
    
    return ret;
}

@implementation NSBitmapImageRep (SKExtensions)

// allow for a slight margin around the image; maybe caused by a shadow (found this in testing)
static const NSInteger MARGIN = 2;
static const unsigned char EPSILON = 2;
static const NSInteger THRESHOLD = 8;

static inline BOOL differentPixels( const unsigned char *p1, const unsigned char *p2, NSUInteger count )
{
    NSUInteger i;    
    for (i = 0; i < count; i++) {
        if ((p2[i] > p1[i] && p2[i] - p1[i] > EPSILON) || (p1[i] > p2[i] && p1[i] - p2[i] > EPSILON))
            return YES;
    }
    return NO;
}

typedef struct _SKBitmapData {
    unsigned char *data;
    NSInteger bytesPerRow;
    NSInteger samplesPerPixel;
} SKBitmapData;

static inline void getPixelFromBitmapData(SKBitmapData *bitmap, NSInteger x, NSInteger y, unsigned char pixel[])
{    
    NSInteger spp = bitmap->samplesPerPixel;
    unsigned char *ptr = &(bitmap->data[(bitmap->bytesPerRow * y) + (x * spp)]);
    while (spp--)
        *pixel++ = *ptr++;
}

static BOOL isSignificantPixelFromBitMapData(SKBitmapData *bitmap, NSInteger x, NSInteger y, NSInteger minX, NSInteger maxX, NSInteger minY, NSInteger maxY, unsigned char backgroundPixel[])
{
    NSInteger i, j, count = 0;
    unsigned char pixel[bitmap->samplesPerPixel];
    
    getPixelFromBitmapData(bitmap, x, y, pixel);
    if (differentPixels(pixel, backgroundPixel, bitmap->samplesPerPixel)) {
        for (i = minX; i <= maxX; i++) {
            for (j = minY; j <= maxY; j++) {
                getPixelFromBitmapData(bitmap, i, j, pixel);
                if (differentPixels(pixel, backgroundPixel, bitmap->samplesPerPixel)) {
                    count += (ABS(i - x) < 4 && ABS(j - y) < 4) ? 2 : 1;
                    if (count > THRESHOLD)
                        return YES;
                }
            }
        }
    }
    return NO;
}

- (NSRect)foregroundRect;
{    
    NSInteger i, iMax = [self pixelsWide] - MARGIN;
    NSInteger j, jMax = [self pixelsHigh] - MARGIN;
    
    NSInteger bytesPerRow = [self bytesPerRow];
    NSInteger samplesPerPixel = [self samplesPerPixel];
    unsigned char pixel[samplesPerPixel];
    
    memset(pixel, 0, samplesPerPixel);
    
    NSInteger iLeft = iMax;
    NSInteger jTop = jMax;
    NSInteger iRight = MARGIN - 1;
    NSInteger jBottom = MARGIN - 1;
    
    unsigned char *bitmapData = [self bitmapData];
    
    SKBitmapData bitmap;
    bitmap.data = bitmapData;
    bitmap.bytesPerRow = bytesPerRow;
    bitmap.samplesPerPixel = samplesPerPixel;
    
    unsigned char backgroundPixel[samplesPerPixel];
    getPixelFromBitmapData(&bitmap, MIN(MARGIN, iMax), MIN(MARGIN, jMax), backgroundPixel);
    
    // basic idea borrowed from ImageMagick's statistics.c implementation
    
    // top margin
    for (j = MARGIN; j < jTop; j++) {
        for (i = MARGIN; i < iMax; i++) {            
            if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(MARGIN, i - 5), MIN(iMax - 1, i + 5), MAX(MARGIN, j - 1), MIN(jMax - 1, j + 5), backgroundPixel)) {
                // keep in mind that we're manipulating corner points, not height/width
                jTop = j; // final
                jBottom = j;
                iLeft = i;
                iRight = i;
                break;
            }
        }
    }
    
    if (jTop == jMax)
        // no foreground pixel detected
        return NSZeroRect;
    
    // bottom margin
    for (j = jMax - 1; j > jBottom; j--) {
        for (i = MARGIN; i < iMax; i++) {            
            if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(MARGIN, i - 5), MIN(iMax - 1, i + 5), MAX(MARGIN, j - 5), MIN(jMax - 1, j + 1), backgroundPixel)) {
                jBottom = j; // final
                if (iLeft > i)
                    iLeft = i;
                if (iRight < i)
                    iRight = i;
                break;
            }
        }
    }
    
    // left margin
    for (i = MARGIN; i < iLeft; i++) {
        for (j = jTop; j <= jBottom; j++) {            
            if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(MARGIN, i - 1), MIN(iMax - 1, i + 5), MAX(MARGIN, j - 5), MIN(jMax - 1, j + 5), backgroundPixel)) {
                iLeft = i; // final
                break;
            }
        }
    }
    
    // right margin
    for (i = iMax - 1; i > iRight; i--) {
        for (j = jTop; j <= jBottom; j++) {            
            if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(MARGIN, i - 5), MIN(iMax - 1, i + 1), MAX(MARGIN, j - 5), MIN(jMax - 1, j + 5), backgroundPixel)) {
                iRight = i; // final
                break;
            }
        }
    }
    
    // check top margin if necessary
    if (jTop == MARGIN) {
        for (j = 0; j < MARGIN; j++) {
            for (i = MARGIN; i < iMax; i++) {            
                if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(MARGIN, i - 5), MIN(iMax - 1, i + 5), MAX(0, j - 1), MIN(jMax - 1, j + 5), backgroundPixel)) {
                    jTop = j; // final
                    break;
                }
            }
        }
    }
    
    // check bottom margin if necessary
    if (jBottom == jMax - 1) {
        for (j = jMax + MARGIN - 1; j > jMax - 1; j--) {
            for (i = MARGIN; i < iMax; i++) {            
                if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(MARGIN, i - 5), MIN(iMax - 1, i + 5), MAX(MARGIN, j - 5), MIN(jMax + MARGIN - 1, j + 1), backgroundPixel)) {
                    jBottom = j; // final
                    break;
                }
            }
        }
    }
    
    // check left margin if necessary
    if (iLeft == MARGIN) {
        for (i = 0; i < MARGIN; i++) {
            for (j = jTop; j <= jBottom; j++) {            
                if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(0, i - 1), MIN(iMax - 1, i + 5), MAX(MARGIN, j - 5), MIN(jMax - 1, j + 5), backgroundPixel)) {
                    iLeft = i; // final
                    break;
                }
            }
        }
    }
    
    // check right margin if necessary
    if (iRight == iMax - 1) {
        for (i = iMax + MARGIN - 1; i > iMax - 1; i--) {
            for (j = jTop; j <= jBottom; j++) {            
                if (isSignificantPixelFromBitMapData(&bitmap, i, j, MAX(MARGIN, i - 5), MIN(iMax + MARGIN - 1, i + 1), MAX(MARGIN, j - 5), MIN(jMax - 1, j + 5), backgroundPixel)) {
                    iRight = i; // final
                    break;
                }
            }
        }
    }
    
    // finally, convert the corners to a bounding rect
    return NSMakeRect(iLeft, jMax - jBottom - MARGIN, iRight + 1 - iLeft, jBottom + 1 - jTop);
}

@end
