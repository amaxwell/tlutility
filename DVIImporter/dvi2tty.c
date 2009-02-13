/******************************************************************************
 * Marcel Mol: 1990-03-27  (UUCP: marcel@duteca.tudelft.nl)
 *               Fixed bug that causes the program to hang when it finds a
 *               fontname with an 's' in it not followed by an 'y'.
 *               Thanks to Paul Orgren (orgren@Stars.Reston.Unisys.COM).
 * Marcel Mol: 1990-02-04  (UUCP: marcel@duteca.tudelft.nl)
 *               First attempt to recognize symbol fonts, so bullets (in
 *               itemized lists) are translated to a proper character instead
 *               an awfull ligature.
 *               Version 4.0.
 * Marcel Mol: 1990-02-01  (UUCP: marcel@duteca.tudelft.nl)
 *               Included port to VMS (off Joseph Vasallo and Seppo Rantala)
 *               into latest version. Hope things still work, cannot test it ...
 * Joseph Vasallo & Seppo Rantala: 1989-09-05 (Internet: rantala@tut.FI)
 *		 Ported to work under VAX/VMS V4.4 & VAXC V2.4 or higher.
 *		 Fixed bugs in using Swedish/Finnish characters.
 * Marcel Mol: 1989-02-14  (UUCP: duteca!marcel)
 *               Fixed check for .dvi extension.
 *               Allowed more ligatures.
 *               Fixed side effect bugs (2 gets as function arguments).
 *               Version 3.2.
 * Marcel Mol: 1989-01-19  (UUCP: duteca!marcel)
 *               Changed in option handling, no change
 *               in user interface (only the undocumented 
 *               feature -e).
 *               Version 3.1.
 * Marcel Mol: 1989-01-11  (UUCP: duteca!marcel)
 *               Changed some longs to ints.
 *               It now also runs on MSDOS Microsoft C 5.1
 *               New version: 3.0
 * Marcel Mol: 1989-01-03  (UUCP: duteca!marcel)
 *               Fixed a bugs concerning pager programs
 *               and scanning environment variable DVI2TTY.
 * Marcel Mol: 1988-10-25  (UUCP: duteca!marcel)
 *        dvi2tty.c dvi2tty.h dvistuff.c commands.h
 *               Converted program to C.
 *               improved spacing between words/characters.
 * bogart:/usr/alla/zap/dvitty/dvitty.p  1986-08-15 20:24:31,
 *               Version to be sent to mod.sources ready.
 * New option since last version:
 *   -Fprog      Pipe output to prog. Can be used to get a different
 *               pager than the default.
 * bogart:/usr/alla/zap/dvitty/dvitty.p  1986-01-13 21:49:31,
 *   Environment variable DVITTY is read and options can be set from it.
 *   These are the currently implemented options:
 *      -ofile   Write output to file, else write to stdout,
 *               possibly piped through a pager if stdout is a tty.
 *      -plist   Print pages whos TeX-page-number are in list.
 *               List is on the form  1,3:6,8  to choose pages
 *               1,3-6 and 8. TeX-nrs can be negative: -p-1:-4,4
 *      -Plist   Print pages whos sequential number are in list.
 *      -wn      Print the lines with width n characters, default is
 *               80. Wider lines gives better results.
 *      -q       Don't try to pipe to a pager.
 *      -f       Try to pipe to a pager if output is a tty.
 *      -Fname   Specify a pager program.                  
 *               Default of -q and -f is a compile time option, a constant.
 *      -l       Write '^L' instead of formfeed between pages.
 *      -u       Don't try to find Scandinavian characters (they will
 *               print as a:s and o:s if this option is choosen).
 *      -s       Scandinavian characters printed as }{|][\.
 *               Default of -s and -u is a compile time option, a constant.
 * bogart:/usr/alla/zap/dvitty/dvitty.p  1986-01-10 18:51:03,
 *   Argument parsing, and random access functions (external, in C)
 *   and other OS-dependent stuff (in C). Removed private 'pager' &
 *   tries to pipe through PAGER (environment var) or, if PAGER not
 *   defined, /usr/ucb/more. Some changes for efficency.
 * bogart:/usr/alla/svante/dvitty/dvitty.p  1985-07-15 20:51:00,
 *   The code for processing dvi-files running on UNIX (UCB-Pascal)
 *   but no argument parsing.
 * VERA::SS:<SVANTE-LINDAHL.WORK>DVITTY.PAS.140, 30-Mar-85 05:43:56,
 *   Edit: Svante Lindahl
 * VERA::SS:<SVANTE-LINDAHL.WORK>DVITTY.PAS.136, 15-Jan-85 13:52:59,
 *   Edit: Svante Lindahl, final Twenex version !!!??
 * VERA::SS:<SVANTE-LINDAHL.WORK>DVITTY.PAS.121, 14-Jan-85 03:10:22,
 *   Edit: Svante Lindahl, cleaned up and fixed a lot of little things
 * VERA::SS:<SVANTE-LINDAHL.WORK>DVITTY.PAS.25, 15-Dec-84 05:29:56,
 *   Edit: Svante Lindahl, COMND-interface, including command line scanning
 * VERA::SS:<SVANTE-LINDAHL.WORK>DVITTY.PAS.23, 10-Dec-84 21:24:41,
 *   Edit: Svante Lindahl, added command line scanning with Rscan-JSYS
 * VERA::<SVANTE-LINDAHL.DVITTY>DVITTY.PAS.48,  8-Oct-84 13:26:30,
 *  Edit: Svante Lindahl, fixed switch-parsing, destroyed by earlier patches
 * VERA::<SVANTE-LINDAHL.DVITTY>DVITTY.PAS.45, 29-Sep-84 18:29:53,
 *  Edit: Svante Lindahl
 *
 * dvitty - get an ascii representation of a dvi-file, suitable for ttys
 *
 * This program, and any documentation for it, is copyrighted by Svante
 * Lindahl. It may be copied for non-commercial use only, provided that
 * any and all copyright notices are preserved.
 *
 * Please report any bugs and/or fixes to:
 *
 * UUCP: {seismo,mcvax,cernvax,diku,ukc,unido}!enea!ttds!zap
 * ARPA: enea!ttds!zap@seismo.CSS.GOV
 *  or   Svante_Lindahl_NADA%QZCOM.MAILNET@MIT-MULTICS.ARPA
 * EAN:  zap@cs.kth.sunet
 */

#include "dvi2tty.h"

    /*-----------------------------------------------------------------------*/
    /* The following constants may be toggled before compilation to          */
    /* customize the default behaviour of the program for your site.         */
    /* Whichever their settings are, the defaults can be overridden at       */
    /* runtime.                                                              */
    /*-----------------------------------------------------------------------*/

#define DEFSCAND    FALSE     /* default is Scandinavian, toggle this if you */
                              /* don't have terminals with Scand. nat. chars */
#define WANTPAGER   FALSE      /* default: try to pipe through a pager (like  */
                              /* more) if stdout is tty and no -o switch     */
#define DEFPAGER    "/usr/bin/more"   /* CHANGE TO YOUR LOCAL PAGER            */

    /*------------------ end of customization constants ---------------------*/

#define OPTSET      "wepPousqlfF"/* legal options                            */
#define OPTWARG     "wepPoF"     /* options with argument                    */

/*
 * USAGE CODES
 */

#define wrnge  1                /* width switch arg out of range     */
#define ign    2                /* ignore cause, print 'Usage:..'    */
#define nan    3                /* not a number where one expected   */
#define gae    4                /* garbage at end                    */
#define bdlst  5                /* bad page-numberlist               */
#define onef   6                /* only one dvifile allowed          */
#define bdopt  7                /* bad option                        */
#define onepp  8                /* only one page list allowed        */
#define noarg  9                /* argument expected                 */

const char *dvi2tty = "@(#) dvi2tty.c  4.1 27/03/90 M.J.E. Mol (c) 1989, 1990";

void errorexit(int errorcode, long foo, int opcode)
{

    switch (errorcode) {
        case  illop : fprintf(stderr, "Illegal op-code found: %d\n", opcode);
                      break;
        case  stkof : fprintf(stderr, "Stack overflow\n");
                      break;
        case  stkuf : fprintf(stderr, "Stack underflow\n");
                      break;
        case  stkrq : fprintf(stderr, "Cannot create dvi stack\n");
                      break;
        case  lnerq : fprintf(stderr, "Cannot allocate memory\n");
                      break;
        case  badid : fprintf(stderr, "Id-byte is not correct: %d\n ", opcode);
                      break;
        case  bdsgn : fprintf(stderr, "Bad signature: %d (not 223)\n",
                                      (int) foo);
                      break;
        case  fwsgn : fprintf(stderr, "%d signature bytes (min. 4)\n",
                                      (int) foo);
                      break;
        case  nopre : fprintf(stderr, "Missing preamble\n");
                      break;
        case  nobop : fprintf(stderr, "Missing beginning-of-page command\n");
                      break;
        case  nopp  : fprintf(stderr, "Missing post-post command\n");
                      break;
        case  bdpre : fprintf(stderr, "Preamble occured inside a page\n");
                      break;
        case  bdbop : fprintf(stderr, "BOP-command occured inside a page\n");
                      break;
        case  bdpst : fprintf(stderr, "Postamble occured before end-of-page\n");
                      break;
        case  bdpp  : fprintf(stderr, "Postpost occured before post-command\n");
                      break;
        case  nopst : fprintf(stderr, "Missing postamble\n");
                      break;
        case  illch : fprintf(stderr, "Character code out of range, 0..127\n");
                      break;
        case  filop : fprintf(stderr, "Cannot open dvifile\n");
                      break;
        case  filcr : fprintf(stderr, "Cannot create outfile\n");
                      break;
        case  pipcr : fprintf(stderr, "Cannot create pipe to pager\n");
                      break;
        default     : fprintf(stderr, "Unknown error code\n");
                      break;
    };
    
    exit(errorcode);

}  /* errorexit */


