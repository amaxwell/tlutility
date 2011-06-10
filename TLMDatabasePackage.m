//
//  TLMDatabasePackage.m
//  tlpdb_test
//
//  Created by Adam R. Maxwell on 06/08/11.
/*
 This software is Copyright (c) 2011
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

#import "TLMDatabasePackage.h"
#import "TLMLogServer.h"
#import <Python/Python.h>

/*
 See http://www.friday.com/bbum/2009/11/21/calling-python-from-objective-c/
 for the basic pattern of subclassing.
 */

#define TLM_METHOD(_rettype_, _mname_) \
- (_rettype_)_mname_ { \
    [NSException raise:@"SubclassResponsibility" \
                format:@"Must subclass %s and override the method %s.", object_getClassName(self), sel_getName(_cmd)]; \
    return (_rettype_)0; \
}

@implementation TLMDatabasePackage

+ (Class)_concretePackageClass
{
    NSParameterAssert([NSThread isMainThread]);
    static Class TLMPyDatabasePackage = Nil;
    if (Nil == TLMPyDatabasePackage) {
        Py_Initialize();
        char *script_path = strdup([[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"parse_tlpdb.py"] saneFileSystemRepresentation]);
        char *bundle_path = strdup([[[NSBundle mainBundle] bundlePath] saneFileSystemRepresentation]);
        char *py_argv[] = { script_path, bundle_path };
        PySys_SetArgv(sizeof(py_argv) / sizeof(char *), py_argv);
        PyRun_SimpleFileExFlags(fopen(script_path, "r"), script_path, true, NULL);
        free(script_path);
        free(bundle_path);
        TLMPyDatabasePackage = NSClassFromString(@"TLMPyDatabasePackage");
    }
    return TLMPyDatabasePackage;
}

+ (NSArray *)_packagesFromDatabaseWithPipe:(NSPipe *)aPipe;
{
    [NSException raise:@"SubclassResponsibility"
                format:@"Must subclass %s and override the method %s.", object_getClassName(self), sel_getName(_cmd)];
    return nil;    
}

+ (NSArray *)_packagesFromDatabaseAtPath:(NSString *)absolutePath;
{
    [NSException raise:@"SubclassResponsibility"
                format:@"Must subclass %s and override the method %s.", object_getClassName(self), sel_getName(_cmd)];
    return nil;
}

+ (NSArray *)packagesFromDatabaseWithPipe:(NSPipe *)aPipe;
{
    NSParameterAssert([NSThread isMainThread]);
    NSArray *packages = nil;
    @try {
        packages = [[self _concretePackageClass] _packagesFromDatabaseWithPipe:aPipe];
    }
    @catch (NSException *e) {
        TLMLog(__func__, @"Caught exception while trying to parse tlpdb: %@", e);
        packages = nil;
    }
    return packages;
}

+ (NSArray *)packagesFromDatabaseAtPath:(NSString *)absolutePath;
{
    NSParameterAssert([NSThread isMainThread]);
    NSArray *packages = nil;
    @try {
        packages = [[self _concretePackageClass] _packagesFromDatabaseAtPath:absolutePath];
    }
    @catch (NSException *e) {
        TLMLog(__func__, @"Caught exception while trying to parse tlpdb: %@", e);
        packages = nil;
    }
    return packages;
}

TLM_METHOD(NSString*, name)
TLM_METHOD(NSString*, category)
TLM_METHOD(NSString*, shortDescription)
TLM_METHOD(NSString*, catalogue)
TLM_METHOD(NSInteger, relocated)
TLM_METHOD(NSArray*, runFiles)
TLM_METHOD(NSArray*, sourceFiles)
TLM_METHOD(NSArray*, docFiles)
TLM_METHOD(NSInteger, revision)

@end
