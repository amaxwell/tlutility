#define Copyright "dvi2tty.c  Copyright (C) 1984, 1985, 1986 Svante Lindahl.\n\
Copyright (C) 1988 M.J.E. Mol 1989, 1990"

#import <CoreFoundation/CoreFoundation.h>

/*
 * ERROR CODES , don't start with 0
 */

#define illop    1              /* illegal op-code                   */
#define stkof    2              /* stack over-flow                   */
#define stkuf    3              /* stack under-flow                  */
#define stkrq    4              /* stack requirement                 */
#define lnerq    5              /* line allocation                   */
#define badid    6              /* id is not right                   */
#define bdsgn    7              /* signature is wrong                */
#define fwsgn    8              /* too few signatures                */
#define nopre    9              /* no pre-amble where expected       */
#define nobop   10              /* no bop-command where expected     */
#define nopp    11              /* no postpost where expected        */
#define bdpre   12              /* unexpected preamble occured       */
#define bdbop   13              /* unexpected bop-command occured    */
#define bdpst   14              /* unexpected post-command occured   */
#define bdpp    15              /* unexpected postpost               */
#define nopst   16              /* no post-amble where expected      */
#define illch   17              /* character code out of range       */
#define filop   18              /* cannot access file                */
#define filcr   19              /* cannot creat file                 */
#define pipcr   20              /* cannot creat pipe                 */


__BEGIN_DECLS

extern CFStringRef CreateStringWithContentsOfDVIFile(CFStringRef absolutePath);

__END_DECLS
