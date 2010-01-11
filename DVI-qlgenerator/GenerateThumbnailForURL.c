/*
 This software is Copyright (c) 2009-2010
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

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>
#import "DVIPDFTask.h"

/* -----------------------------------------------------------------------------
    Generate a thumbnail for file

   This function's job is to create thumbnail for designated file as fast as possible
   ----------------------------------------------------------------------------- */

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize)
{
    CFDataRef pdfData = DVICreatePDFDataFromFile(url, false, QLThumbnailRequestGetGeneratorBundle(thumbnail));
    
    // if dvi conversion failed, return immediately
    if (NULL == pdfData) return coreFoundationUnknownErr;
    
    OSStatus err = noErr;
        
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(pdfData);
    CFRelease(pdfData);

    CGPDFDocumentRef pdfDoc = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    
    // 1-based, returns NULL if no such page exists
    CGPDFPageRef page = CGPDFDocumentGetPage(pdfDoc, 1);

    if (page) {
                            
        /*
         The page is typically larger than maxSize, so we need to scale it before asking for a 
         context that's too large for a texture (or whatever Quick Look uses internally).  
         Failure to do this can result in "CGImageCreate: invalid image size: 0 x 0" log messages.
         */
        CGRect pageRect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        CGFloat scale = fmin(maxSize.width / pageRect.size.width, maxSize.height / pageRect.size.height);
        CGRect imageRect = CGRectZero;
        imageRect.size.height = pageRect.size.height * scale;
        imageRect.size.width = pageRect.size.width * scale;
        imageRect = CGRectIntegral(imageRect);
        
        CGContextRef ctxt = QLThumbnailRequestCreateContext(thumbnail, imageRect.size, FALSE, NULL);
        
        if (ctxt) {

            /*
             Note: CGPDFPageGetDrawingTransform only downscales, but that's all we really need for a thumbnail.
             Correct handling of rotation was verified using a trivial example with \usepackage[landscape=true]{geometry}.
             */
            int rotation = CGPDFPageGetRotationAngle(page);
            CGAffineTransform transform = CGPDFPageGetDrawingTransform(page, kCGPDFMediaBox, imageRect, rotation, true);

            CGContextSaveGState(ctxt);
            CGContextConcatCTM(ctxt, transform);
            
            // not clear if we get a page based context, but this call is a no-op if not
            CGContextBeginPage(ctxt, NULL);
            
            // draw page background since it's transparent; something like \pagecolor{green} draws over it
            CGContextSaveGState(ctxt);
            CGContextSetGrayFillColor(ctxt, 1.0, 1.0);
            CGContextFillRect(ctxt, pageRect);
            CGContextRestoreGState(ctxt);

            // draw page content
            if (page) CGContextDrawPDFPage(ctxt, page);
            CGContextEndPage(ctxt);
            CGContextRestoreGState(ctxt);
            
            QLThumbnailRequestFlushContext(thumbnail, ctxt);
            CGContextRelease(ctxt);
        }
        else {
            // no drawing context
            err = coreFoundationUnknownErr;
        }
    }
    else {
        // no pages in pdf document
        err = coreFoundationUnknownErr;
    }
    CGPDFDocumentRelease(pdfDoc);

    return err;
}

void CancelThumbnailGeneration(void* thisInterface, QLThumbnailRequestRef thumbnail)
{
    // implement only if supported
}
