
#include "dvi2tty.h"
#include <sys/types.h>
#include <sys/stat.h>
#include "commands.h"

#define VERSIONID            2 /* dvi version number that pgm handles      */
#define VERTICALEPSILON 450000L /* crlf when increasing v more than this   */

#define rightmargin     152    /* nr of columns allowed to the right of h=0*/
#define leftmargin      -50    /* give some room for negative h-coordinate */
#define LINELEN         203    /* rightmargin - leftmargin + 1 */

#define MOVE            TRUE   /* if advancing h when outputing a rule     */
#define STAY            FALSE  /* if not advancing h when outputing a rule */

#define absolute        0      /* for seeking in files                     */
#define relative        1

#define FORM             12    /* formfeed                                 */
#define SPACE            32    /* space                                    */
#define DEL             127    /* delete                                   */

#define LASTCHAR        127    /* max dvi character, above are commands    */

#define IMIN(a, b)      (a<b ? a : b)
#define IMAX(a, b)      (a>b ? a : b)

#define get1()          num(parser, 1)
#define get2()          num(parser, 2)
#define get3()          num(parser, 3)
#define get4()          num(parser, 4)
#define sget1()         snum(parser, 1)
#define sget2()         snum(parser, 2)
#define sget3()         snum(parser, 3)
#define sget4()         snum(parser, 4)

#define ttywidth 80
#define espace 0

const char *dvistuff = "@(#) dvistuff.c  4.1 27/03/90 M.J.E. Mol (c) 1989, 1990";

/*---------------------------------------------------------------------------*/

typedef struct {
    int hh;
    int vv;
    int ww;
    int xx;
    int yy;
    int zz;
} stackitem;

typedef struct lineptr {        /* the lines of text to be output to outfile */
    int             vv;                 /* vertical position of the line     */
    int             charactercount;     /* pos of last char on line          */
    struct lineptr *prev;               /* preceding line                    */
    struct lineptr *next;               /* succeeding line                   */
    char            text[LINELEN+1];    /* leftmargin...rightmargin          */
} linetype;

typedef struct _font {
    int     num;
    struct _font * next;
    char  * name;
} font;

typedef struct _DVIParser {
    FILE       *infile;
    void       *output;
    int         opcode;             /* dvi-opcodes                               */
    long        foo;                /* register variable                         */
    
    int         h, v;               /* coordinates, horizontal and vertical      */
    int         w, x, y, z;         /* horizontal and vertical amounts           */
    
    int         pagecounter;        /* sequence page number counter              */
    int         backpointer;        /* pointer for offset to previous page       */
    int         pagenr;             /* TeX page number                           */
    int         stackmax;           /* stacksize required                        */
    
    int         charwidth;          /* aprox width of character                  */
    
    linetype   *currentline;        /* pointer to current line on current page   */
    linetype   *firstline;          /* pointer to first line on current page     */
    linetype   *lastline;           /* pointer to last line on current page      */
    int         firstcolumn;        /* 1st column with something to print        */
    
    stackitem  *stack;              /* stack for dvi-pushes                      */
    int         sidx;               /* stack pointer                             */
    
    font       *fonts;              /* List of fontnames defined                 */
    int         symbolfont;         /* true if font is a symbol font             */    
} DVIParser;

static void            postamble       (DVIParser *);
static void            preamble        (DVIParser *);
static void            walkpages       (DVIParser *);
static void            initpage        (DVIParser *);
static void            dopage          (DVIParser *);
static void            printpage       (DVIParser *);
static void            rule            (DVIParser *, bool, int, int);
static void            ruleaux         (DVIParser *, int, int, char);
static int             horizontalmove  (DVIParser *, int);
static int             skipnops        (DVIParser *);
static linetype    *   getline         (DVIParser *);
static linetype    *   findline        (DVIParser *);
static unsigned int    num             (DVIParser *, int);
static int             snum            (DVIParser *, int);
static void            dochar          (DVIParser *, char);
static void            symchar         (DVIParser *, char);
static void            normchar        (DVIParser *, char);
static void            outchar         (DVIParser *, unsigned char);
static void            putcharacter    (DVIParser *, int);
static void            setchar         (DVIParser *, int);
static void            fontdef         (DVIParser *, int);
static void            setfont         (DVIParser *, int);

static void appendCharacterToData(uint8_t c, CFMutableDataRef data)
{
    CFDataAppendBytes(data, &c, 1);
}

static void freefonts(DVIParser *parser)
{
    font *fnt = parser->fonts;
    while (fnt != NULL) {
        font *next = fnt->next;
        free(fnt->name);
        free(fnt);
        fnt = next;
    }
    parser->fonts = NULL;
}

static void freestack(DVIParser *parser)
{
    free(parser->stack);
    parser->stack = NULL;
}

/*---------------------------------------------------------------------------*/

CFStringRef CreateStringWithContentsOfDVIFile(CFStringRef absolutePath)
{    
    DVIParser parser;
    memset(&parser, 0, sizeof(DVIParser));
    size_t pathlen = CFStringGetMaximumSizeOfFileSystemRepresentation(absolutePath);
    char *pathbuf = malloc(pathlen);
    if (NULL == pathbuf)
        return NULL;
    
    (void) CFStringGetFileSystemRepresentation(absolutePath, pathbuf, pathlen);
    
    parser.infile = fopen(pathbuf, "r");
    free(pathbuf);
    pathbuf = NULL;
    
    if (NULL == parser.infile)
        return NULL;
    
    parser.output = CFDataCreateMutable(kCFAllocatorDefault, 0);
    postamble(&parser);                            /* seek and process the postamble */
    /* note that walkpages *must* immediately follow preamble */
    preamble(&parser);                             /* process preamble               */
    walkpages(&parser);                            /* time to do the actual work!    */
    
    freefonts(&parser);
    freestack(&parser);
    fclose(parser.infile);
    
    CFStringRef str = CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, parser.output, kCFStringEncodingISOLatin1);
    CFRelease(parser.output);
        
    return str;
}

/*---------------------------------------------------------------------------*/

static void postamble(DVIParser *parser)            /* find and process postamble, use random access */
{
    off_t size;
    int  count;
    struct stat st;

    fstat (fileno(parser->infile), &st);
    size = st.st_size;                   /* get size of file          */
    count = -1;
    do {              /* back file up past signature bytes (223), to id-byte */
        if (size == 0)
            errorexit(nopst, parser->foo, parser->opcode);
        size--;
        fseek(parser->infile, size, absolute);
        parser->opcode = (int) get1();
        count++;
    } while (parser->opcode == TRAILER);
    if (count < 4) {                            /* must have 4 trailer bytes */
         parser->foo = count;
         errorexit(fwsgn, parser->foo, parser->opcode);
    }
    if (parser->opcode != VERSIONID)
        errorexit(badid, parser->foo, parser->opcode);
    fseek(parser->infile, size-4, absolute);       /* back up to back-pointer       */
    fseek(parser->infile, sget4(), absolute);      /* and to start of postamble   */
    if (get1() != POST)
        errorexit(nopst, parser->foo, parser->opcode);
    fseek(parser->infile, 20L, relative); /* lastpageoffset, numerator, denominator */
                                   /* magnification, maxpageheight           */
    
    int maxpagewidth = sget4();
    /* hack here: zero charwidth causes SIGFPE on x86 */
    parser->charwidth = maxpagewidth > 0 ? maxpagewidth / (ttywidth + espace) : 500000; 
    
    parser->stackmax = (int) get2();
    if ((parser->stack = (stackitem *) malloc(parser->stackmax * sizeof(stackitem))) == NULL)
       errorexit(stkrq, parser->foo, parser->opcode);

    /* get2() -- totalpages */
    /* fontdefs  do fontdefs in flight ... */

} /* postamble */

/*---------------------------------------------------------------------------*/

static void preamble(DVIParser *parser)                 /* process preamble, use random access       */
{

    fseek(parser->infile, 0L, absolute);       /* read the parser->infile from the start   */
    if ((parser->opcode = skipnops(parser)) != PRE)
        errorexit(nopre, parser->foo, parser->opcode);
    parser->opcode = (int) get1();        /* check id in preamble, ignore rest of it */
    if (parser->opcode != VERSIONID)
        errorexit(badid, parser->foo, parser->opcode);
    fseek(parser->infile, 12L, relative);  /* numerator, denominator, magnification */
    fseek(parser->infile, get1(), relative);         /* skip job identification     */

} /* preamble */

/*----------------------------------------------------------------------------*/

static void walkpages(DVIParser *parser)                  /* process the pages in the DVI-file */
{
    parser->pagecounter = 0L;
    while ((parser->opcode = skipnops(parser)) != POST) {
        if (parser->opcode != BOP)              /* should be at start of page now    */
            errorexit(nobop, parser->foo, parser->opcode);
        else {
            parser->pagecounter++;
            parser->pagenr = sget4();           /* get TeX page number               */
            fseek(parser->infile, 36L, relative); /* skip page header */
            parser->backpointer = sget4();      /* get previous page offset          */

            initpage(parser);
            dopage(parser);
            printpage(parser);
        }
    }

} /* walkpages */

/*---------------------------------------------------------------------------*/

static void initpage(DVIParser *parser)
{

    parser->h = 0L;  parser->v = 0L;                        /* initialize coordinates   */
    parser->x = 0L;  parser->w = 0L;  parser->y = 0L;  parser->z = 0L;      /* initialize amounts       */
    parser->sidx = 0;                               /* initialize stack         */
    parser->currentline = getline(parser);                /* initialize list of lines */
    parser->currentline->vv = 0L;
    parser->firstline   = parser->currentline;
    parser->lastline    = parser->currentline;
    parser->firstcolumn = rightmargin;
    if (parser->backpointer != -1)              /* not FORM at first page   */
        appendCharacterToData('\n', parser->output);

} /* initpage */

/*----------------------------------------------------------------------------*/

static void dopage(DVIParser *parser)
{

    while ((parser->opcode = (int) get1()) != EOP) {    /* process page until eop */
        if (parser->opcode <= LASTCHAR)
            dochar(parser, (char) parser->opcode);
        else if ((parser->opcode >= FONT_00) && (parser->opcode <= FONT_63)) 
            setfont(parser, parser->opcode - FONT_00);
        else if (parser->opcode > POST_POST)
            errorexit(illop, parser->foo, parser->opcode);
        else
            switch (parser->opcode) {
                case SET1     : setchar(parser, get1()); break;
                case SET2     : setchar(parser, get2()); break;
                case SET3     : setchar(parser, get3()); break;
                case SET4     : setchar(parser, get4()); break;
                case SET_RULE : { int height = sget4();
                                  rule(parser, MOVE, sget4(), height); break;
                                }
                case PUT1     : putcharacter(parser, get1()); break;
                case PUT2     : putcharacter(parser, get2()); break;
                case PUT3     : putcharacter(parser, get3()); break;
                case PUT4     : putcharacter(parser, get4()); break;
                case PUT_RULE : { int height = sget4();
                                  rule(parser, STAY, sget4(), height); break;
                                }
                case NOP      : break;  /* no-op */
                case BOP      : errorexit(bdbop, parser->foo, parser->opcode); break;
/*              case EOP      : break;  strange place to have EOP */
                case PUSH     : if (parser->sidx >= parser->stackmax)            /* push */
                                     errorexit(stkof, parser->foo, parser->opcode);
                                parser->stack[parser->sidx].hh = parser->h;
                                parser->stack[parser->sidx].vv = parser->v;
                                parser->stack[parser->sidx].ww = parser->w;
                                parser->stack[parser->sidx].xx = parser->x;
                                parser->stack[parser->sidx].yy = parser->y;
                                parser->stack[parser->sidx].zz = parser->z;
                                parser->sidx++;
                                break;
                case POP      : if (parser->sidx == 0)                   /* pop */
                                    errorexit(stkuf, parser->foo, parser->opcode);
                                parser->sidx--;
                                parser->h = parser->stack[parser->sidx].hh;
                                parser->v = parser->stack[parser->sidx].vv;
                                parser->w = parser->stack[parser->sidx].ww;
                                parser->x = parser->stack[parser->sidx].xx;
                                parser->y = parser->stack[parser->sidx].yy;
                                parser->z = parser->stack[parser->sidx].zz;
                                break;
                case RIGHT1   : (void) horizontalmove(parser, sget1()); break;
                case RIGHT2   : (void) horizontalmove(parser, sget2()); break;
                case RIGHT3   : (void) horizontalmove(parser, sget3()); break;
                case RIGHT4   : (void) horizontalmove(parser, sget4()); break;
                case W0       : parser->h += parser->w; break;
                case W1       : parser->w = horizontalmove(parser, sget1()); break;
                case W2       : parser->w = horizontalmove(parser, sget2()); break;
                case W3       : parser->w = horizontalmove(parser, sget3()); break;
                case W4       : parser->w = horizontalmove(parser, sget4()); break;
                case X0       : parser->h += parser->x; break;
                case X1       : parser->x = horizontalmove(parser, sget1()); break;
                case X2       : parser->x = horizontalmove(parser, sget2()); break;
                case X3       : parser->x = horizontalmove(parser, sget3()); break;
                case X4       : parser->x = horizontalmove(parser, sget4()); break;
                case DOWN1    : parser->v += sget1(); break;
                case DOWN2    : parser->v += sget2(); break;
                case DOWN3    : parser->v += sget3(); break;
                case DOWN4    : parser->v += sget4(); break;
                case Y0       : parser->v += parser->y; break;
                case Y1       : parser->y = sget1(); parser->v += parser->y; break;
                case Y2       : parser->y = sget2(); parser->v += parser->y; break;
                case Y3       : parser->y = sget3(); parser->v += parser->y; break;
                case Y4       : parser->y = sget4(); parser->v += parser->y; break;
                case Z0       : parser->v += parser->z; break;
                case Z1       : parser->z = sget1(); parser->v += parser->z; break;
                case Z2       : parser->z = sget2(); parser->v += parser->z; break;
                case Z3       : parser->z = sget3(); parser->v += parser->z; break;
                case Z4       : parser->z = sget4(); parser->v += parser->z; break;
                case FNT1     :
                case FNT2     :
                case FNT3     :
                case FNT4     : setfont(parser, num(parser, parser->opcode - FNT1 + 1));
                                break;
                case XXX1     : fseek(parser->infile, get1(), relative); break;
                case XXX2     : fseek(parser->infile, get2(), relative); break;
                case XXX3     : fseek(parser->infile, get3(), relative); break;
                case XXX4     : fseek(parser->infile, get4(), relative); break;
                case FNT_DEF1 :
                case FNT_DEF2 :
                case FNT_DEF3 :
                case FNT_DEF4 : fontdef(parser, parser->opcode - FNT_DEF1 + 1);
                                break;
                case PRE      : errorexit(bdpre, parser->foo, parser->opcode); break;
                case POST     : errorexit(bdpst, parser->foo, parser->opcode); break;
                case POST_POST: errorexit(bdpp, parser->foo, parser->opcode); break;
            }
    }

} /* dopage */

/*---------------------------------------------------------------------------*/

static void printpage(DVIParser *parser)       /* 'end of page', writes lines of page to output file */
{
    int  i, j;
    unsigned char ch;

    if (parser->sidx != 0)
        fprintf(stderr, "dvi2tty: warning - stack not empty at eop.\n");
    for (parser->currentline = parser->firstline; parser->currentline != nil;
          parser->currentline = parser->currentline->next) {
        if (parser->currentline != parser->firstline) {
            parser->foo = ((parser->currentline->vv - parser->currentline->prev->vv)/VERTICALEPSILON)-1;
            if (parser->foo > 3)
                parser->foo = 3;        /* linespacings not too large */
            for (i = 1; i <= (int) parser->foo; i++)
                appendCharacterToData('\n', parser->output);
        }
        if (parser->currentline->charactercount >= leftmargin) {
            parser->foo = ttywidth - 2;
            for (i = parser->firstcolumn, j = 1; i <= parser->currentline->charactercount;
                   i++, j++) {
                ch = parser->currentline->text[i - leftmargin];
                if (ch >= SPACE)
                    appendCharacterToData(ch, parser->output);
            } 
        }
        appendCharacterToData('\n', parser->output);
    } 

    parser->currentline = parser->firstline;
    while (parser->currentline->next != nil) {
        parser->currentline = parser->currentline->next;
        free(parser->currentline->prev);
    }
    free(parser->currentline);              /* free last line */
    parser->currentline = nil;

} /* printpage */

static void rule(DVIParser *parser, bool moving, int rulewt, int ruleht)
{   /* output a rule (vertical or horizontal), increment h if moving is true */
    char ch;               /* character to set rule with            */
    int saveh = 0, savev;
                              /* rule   --   starts up the recursive routine */
    if (!moving)
        saveh = parser->h;
    if ((ruleht <= 0) || (rulewt <= 0))
        parser->h += rulewt;
    else {
        savev = parser->v;
        if ((ruleht / rulewt) > 0)         /* value < 1 truncates to 0 */
            ch = '|';
        else if (ruleht > (VERTICALEPSILON / 2))
            ch = '=';
        else
            ch = '_';
        ruleaux(parser, rulewt, ruleht, ch);
        parser->v = savev;
    }
    if (!moving)
        parser->h = saveh;

} /* rule */

static void ruleaux(DVIParser *parser, int rulewt, int ruleht, char ch)     /* recursive  that does the job */
{
    int wt, lmh, rmh;

    wt = rulewt;
    lmh = parser->h;                        /* save left margin                      */
    if (parser->h < 0) {                    /* let rules that start at negative h    */
        wt -= parser->h;                    /* start at coordinate 0, but let it     */
        parser->h = 0;                      /*   have the right length               */
    }
    while (wt > 0) {                /* output the part of the rule that      */
        rmh = parser->h;                    /*   goes on this line                   */
        outchar(parser, ch);
        wt -= (parser->h-rmh);              /* decrease the width left on line       */
    }
    ruleht -= VERTICALEPSILON;      /* decrease the height                   */
    if (ruleht > VERTICALEPSILON) { /* still more vertical?                  */
        rmh = parser->h;                    /* save current h (right margin)         */
        parser->h = lmh;                    /* restore left margin                   */
        parser->v -= (VERTICALEPSILON + VERTICALEPSILON / 10);
        ruleaux(parser, rulewt, ruleht, ch);
        parser->h = rmh;                    /* restore right margin                  */
    }

} /* ruleaux */

/*----------------------------------------------------------------------------*/

static int horizontalmove(DVIParser *parser, int amount)
{

    if (labs(amount) > parser->charwidth / 4L) {

        parser->foo = 3*parser->charwidth / 4;
        if (amount > 0)
            amount = ((amount+parser->foo) / parser->charwidth) * parser->charwidth;
        else
#if defined(VMS)
            amount = (ROUND( (float) (amount-parser->foo) / charwidth) + 1)* charwidth;
#else
            amount = ((amount-parser->foo) / parser->charwidth) * parser->charwidth;
#endif
        parser->h += amount;
        return amount;
    }
    else
        return 0;

}   /* horizontalmove */

/*----------------------------------------------------------------------------*/

static int skipnops(DVIParser *parser)                      /* skips by no-op commands  */
{
    int opcode;

    while ((opcode = (int) num(parser, 1)) == NOP);
    return opcode;

} /* skipnops */

/*----------------------------------------------------------------------------*/

static linetype *getline(DVIParser *parser)             /* returns an initialized line-object */
{
    int  i;
    linetype *temp;

    if ((temp = (linetype *) malloc(sizeof(linetype))) == NULL) 
        errorexit(lnerq, parser->foo, parser->opcode);
    temp->charactercount = leftmargin - 1;
    temp->prev = nil;
    temp->next = nil;
    for (i = 0; i < LINELEN; i++)
        temp->text[i] = ' ';
    temp->text[i] = '\0';
    return temp;

} /* getline */

/*----------------------------------------------------------------------------*/

static linetype *findline(DVIParser *parser)            /* find best fit line were text should go */
{                               /* and generate new line if needed        */
    linetype *temp;
    int topd, botd;

    if (parser->v <= parser->firstline->vv) {                      /* above first line */
        if (parser->firstline->vv - parser->v > VERTICALEPSILON) {
            temp = getline(parser);
            temp->next = parser->firstline;
            parser->firstline->prev = temp;
            temp->vv = parser->v;
            parser->firstline = temp;
        }
        return parser->firstline;
    }

    if (parser->v >= parser->lastline->vv) {                       /* below last line */
        if (parser->v - parser->lastline->vv > VERTICALEPSILON) {
            temp = getline(parser);
            temp->prev = parser->lastline;
            parser->lastline->next = temp;
            temp->vv = parser->v;
            parser->lastline = temp;
        }
        return parser->lastline;
    }

    temp = parser->lastline;                               /* in between two lines */
    while ((temp->vv > parser->v) && (temp != parser->firstline))
        temp = temp->prev;

    /* temp->vv < v < temp->next->vv --- temp is above, temp->next is below */
    topd = parser->v - temp->vv;
    botd = temp->next->vv - parser->v;
    if ((topd < VERTICALEPSILON) || (botd < VERTICALEPSILON))
        if (topd < botd)                           /* take best fit */
            return temp;
        else
            return temp->next;

    /* no line fits suitable, generate a new one */
    parser->currentline = getline(parser);
    parser->currentline->next = temp->next;
    parser->currentline->prev = temp;
    temp->next->prev = parser->currentline;
    temp->next = parser->currentline;
    parser->currentline->vv = parser->v;
    return parser->currentline;

} /* findline */

/*----------------------------------------------------------------------------*/

static unsigned int num(DVIParser *parser, int size)
{
    int i;
    unsigned int x = 0;

    for (i = 0; i < size; i++)
        x = (x << 8) + (unsigned) getc(parser->infile);
    return x;

} /* num */


static int snum(DVIParser *parser, int size)
{
    int i;
    int x = 0;

    x = getc(parser->infile);
    if (x & 0x80)
        x -= 0x100;
    for (i = 1; i < size; i++)
        x = (x << 8) + (unsigned) getc(parser->infile);
    return x;

} /* snum */

/*----------------------------------------------------------------------------*/

static void dochar(DVIParser *parser, char ch)
{

    if (parser->symbolfont == TRUE)
        symchar(parser, ch);
    else
        normchar(parser, ch);

    return;

} /* dochar */

static void symchar(DVIParser *parser, char ch)                     /* output ch to appropriate line */
{

    switch (ch) {       /* can do a lot more on MSDOS machines ... */
       case   0: ch = '-'; break;
       case   1: ch = '.'; break;
       case   2: ch = 'x'; break;
       case   3: ch = '*'; break;
       case  13: ch = 'O'; break;
       case  14: ch = 'O'; break;
       case  15: ch = 'o'; break;
       case  24: ch = '~'; break;
       case 102: ch = '{'; break;
       case 103: ch = '}'; break;
       case 104: ch = '<'; break;
       case 105: ch = '>'; break;
       case 106: ch = '|'; break;
       case 110: ch = '\\'; break;
    }
    outchar(parser, ch);

    return;

} /* symchar */

static void normchar(DVIParser *parser, char ch)
{

    switch (ch) {
        case 11  :  outchar(parser, 'f'); ch = 'f'; break;  /* ligature        */
        case 12  :  outchar(parser, 'f'); ch = 'i'; break;  /* ligature        */
        case 13  :  outchar(parser, 'f'); ch = 'l'; break;  /* ligature        */
        case 14  :  outchar(parser, 'f'); outchar(parser, 'f');
                                  ch = 'i'; break;  /* ligature        */
        case 15  :  outchar(parser, 'f'); outchar(parser, 'f');
                                  ch = 'l'; break;  /* ligature        */
        case 16  :  ch = 'i'; break;
        case 17  :  ch = 'j'; break;
        case 25  :  ch = 0xdf; break;
        case 26  :  ch = 0xe6; break;
        case 27  :  outchar(parser, 'o'); ch = 'e'; break;  /* Dane/Norw oe    */
        case 28  :  ch = 0xf8; break;
        case 29  :  ch = 0xc6; break;
        case 30  :  outchar(parser, 'O'); ch = 'E'; break;  /* Dane/Norw OE    */
        case 31  :  ch = 0xd8; break;
        case 92  :  ch = '"'; break;  /* \ from `` */
        case 123 :  ch = '-'; break;  /* { from -- */
        case 124 :  ch = '_'; break;  /* | from --- */
        case 125 :  ch = '"'; break;  /* } from \H */
        case 126 :  ch = '"'; break;  /* ~ from \~ */
        case 127 :  ch = '"'; break;  /* DEL from \" */
#if 0
        case 18  :  ch = '`'; break   /* from \` */
        case 19  :  ch = ''''; break  /* from \' */
        case 20  :  ch = '~'; break   /* from \v */
        case 21  :  ch = '~'; break   /* from \u */
        case 22  :  ch = '~'; break   /* from \= */
        case 24  :  ch = ','; break   /* from \c */
        case 94  :  ch = '^'; break   /* ^ from \^ */
        case 95  :  ch = '`'; break   /* _ from \. */
#endif
    }
    outchar(parser, ch); 

    return;

} /*normchar */

static void outchar(DVIParser *parser, unsigned char ch)                     /* output ch to appropriate line */
{
    int i, j;

    if (labs(parser->v - parser->currentline->vv) > VERTICALEPSILON / 2L)
        parser->currentline = findline(parser);

#if 0
    j = (int) (((double) h / (double) maxpagewidth) * (ttywidth-1)) + 1;
#else
    j = (int) (parser->h / parser->charwidth);
#endif
    if (j > rightmargin)     /* leftmargin <= j <= rightmargin */
        j = rightmargin;
    else if (j < leftmargin)
        j = leftmargin;
    parser->foo = leftmargin - 1;
    /*
     * This code does not really belong here ...
     */
    /*-------------------------------------------------------------*/
    /* The following is very specialized code, it handles some eu- */
    /* ropean characters.  These are: a, o, u with two dots ("a &  */
    /* "o & "u), and a with a circle (Oa).  TeX outputs these by   */
    /* first issuing the dots or circle and then backspace and set */
    /* the a, o, or u.  When dvitty finds an a, o, or u it sear-   */
    /* ches in the near vicinity for the character codes that re-  */
    /* present circle or dots and if one is found the correspon-   */
    /* ding Latin-1 character replaces the special character code. */
    /*-------------------------------------------------------------*/
    if ((ch == 'a') || (ch == 'A') || (ch == 'o') || (ch == 'O') ||
          (ch == 'u') || (ch == 'U')) {
        for (i = IMAX(leftmargin, j-2);
             i <= IMIN(rightmargin, j+2);
             i++)
            if ((parser->currentline->text[i - leftmargin] == 127) ||
                (parser->currentline->text[i - leftmargin] == 34) ||
                (parser->currentline->text[i - leftmargin] == 23))
                parser->foo = i;
        if (parser->foo >= leftmargin) {
            j = (int) parser->foo;
            switch (parser->currentline->text[j - leftmargin]) {
                case 127 : case 34:
                           if (ch == 'a')
                               ch = 0xe4;
                           else if (ch == 'A')      /* dots ... */
                               ch = 0xc4;
                           else if (ch == 'o')
                               ch = 0xf6;
                           else if (ch == 'O')
                               ch = 0xd6;
                           else if (ch == 'u')
                               ch = 0xfc;
                           else if (ch == 'U')
                               ch = 0xdc;
                           break;
                case 23  : if (ch == 'a')
                               ch = 0xe5;
                           else if (ch == 'A')      /* circle */
                               ch = 0xc5;
                           break;
            }
        }
    }

    /*----------------- end of 'Scandinavian code' ----------------*/
    if (parser->foo == leftmargin-1)
        while ((parser->currentline->text[j - leftmargin] != SPACE)
               && (j < rightmargin)) {
            j++;
            parser->h += parser->charwidth;
        }
    if ( ((ch >= SPACE) && (ch != DEL)) || (ch == 23) ) {
        if (j < rightmargin)
            parser->currentline->text[j - leftmargin] = ch;
        else
            parser->currentline->text[rightmargin - leftmargin] = '@';
        if (j > parser->currentline->charactercount)
            parser->currentline->charactercount = j;
        if (j < parser->firstcolumn)
            parser->firstcolumn = j;
        parser->h += parser->charwidth;
    }

} /* outchar */

/*----------------------------------------------------------------------------*/

static void putcharacter(DVIParser *parser, int charnr)            /* output character, don't change h */
{
    int saveh;

    saveh = parser->h;
    if ((charnr >= 0) && (charnr <= LASTCHAR))
        outchar(parser, (char) charnr);
    else
        setchar(parser, charnr);
    parser->h = saveh;

} /* putcharacter */

/*----------------------------------------------------------------------------*/

static void setchar(DVIParser *parser, int charnr)
{    /* should print characters with character code>127 from current font */
     /* note that the parameter is a dummy, since ascii-chars are<=127    */

    outchar(parser, (unsigned char)(charnr));

} /* setchar */


/*----------------------------------------------------------------------------*/

static void fontdef(DVIParser *parser, int x)
{
    int i;
    char * name;
    font * fnt;
    int namelen;
    int fntnum;
    int new = 0;

    fntnum = num(parser, x);
    (void) get4();                      /* checksum */
    (void) get4();                      /* scale */
    (void) get4();                      /* design */
    namelen = (int) get1() + (int) get1();
    fnt = parser->fonts;
    while (fnt != NULL && fnt->num != fntnum)       /* does fontnum exist */
        fnt = fnt->next;
    if (fnt == NULL) {
        if ((fnt = (font *) malloc(sizeof(font))) == NULL) {
            perror("fontdef");
            exit(EXIT_FAILURE);
        }
        fnt->num = fntnum;
        new = 1;
    }
    else
        free(fnt->name);    /* free old name */
    if ((name = (char *) malloc((namelen + 1) * sizeof(char))) == NULL) {
        perror("fontdef");
        exit(EXIT_FAILURE);
    }
    
    for (i = 0; i < namelen; i++)
        name[i] = get1();
    name[namelen] = '\0';
    fnt->name = name;
    if (new) {
        fnt->next = parser->fonts;
        parser->fonts = fnt;
    }

    return;

} /* fontdef */

static void setfont(DVIParser *parser, int fntnum)
{
    font * fnt;
    char * s;

    fnt = parser->fonts;
    while (fnt != NULL && fnt->num != fntnum)
        fnt = fnt->next;
    if (fnt == NULL) {
        /* error : font not found */
        parser->symbolfont = FALSE;
        return;
    }

    s = fnt->name;
    while ((s = strchr(s, 's')) != NULL) {
        if (strncmp("sy", s, 2) == 0) {
            parser->symbolfont = TRUE;
            return;
        }
	s++;	/* New line to fix bug; font names with 's' would hang */
    }
   
    parser->symbolfont = FALSE;
    return;

} /* setfont */
   