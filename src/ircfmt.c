/*-------------------------------------------------------------------*/
/* IRCFMT - mIRC formatting parser                                   */
/*                                                                   */
/* Parses an EBCDIC IRC message body and:                            */
/*   1. Strips mIRC formatting bytes so they cannot reach a 5250    */
/*      DSPF field as attribute bytes (anything < 0x40 EBCDIC is    */
/*      interpreted as a screen attribute by the workstation).      */
/*   2. Extracts a dominant single-character color hint suitable    */
/*      for the MBNCOL field - 'W' / 'R' / 'G' / 'Y' / 'B' / 'P' /  */
/*      'T' / '_' (default).                                         */
/*                                                                   */
/* Linked as a *MODULE into IRCNETD via CRTBNDC ... MODULE().        */
/* For Phase 6 we only expose two functions, declared in header     */
/* form here so IRCNETD can prototype them locally.                 */
/*                                                                   */
/* Recognised mIRC bytes (ASCII values, since by the time IRCFMT is */
/* called the line is already EBCDIC - but the codes were 1:1       */
/* preserved by the identity slots of the e2a/a2e tables):          */
/*                                                                   */
/*   0x02  Bold                                                      */
/*   0x03  Color: \x03NN[,MM]   (NN = fg, MM = bg, both 0..99)      */
/*   0x04  Hex color: \x04 RRGGBB[,RRGGBB]                          */
/*   0x0F  Reset                                                     */
/*   0x16  Reverse                                                   */
/*   0x1D  Italic                                                    */
/*   0x1E  Strikethrough                                             */
/*   0x1F  Underline                                                 */
/*                                                                   */
/* Rather than checking "EBCDIC byte 0x02 means bold", we operate   */
/* on raw byte values 0x02/0x03/0x0F/etc. - these slots are         */
/* deliberately left at identity in IRCNETD's translation tables.   */
/*                                                                   */
/* mIRC color number -> 5250 single-letter color hint:              */
/*    0 white    -> W       8 yellow      -> Y                       */
/*    1 black    -> _       9 lt green    -> G                       */
/*    2 blue     -> B      10 cyan        -> T                       */
/*    3 green    -> G      11 lt cyan     -> T                       */
/*    4 red      -> R      12 lt blue     -> B                       */
/*    5 brown    -> R      13 pink        -> P                       */
/*    6 purple   -> P      14 grey        -> W                       */
/*    7 orange   -> Y      15 lt grey     -> W                       */
/*-------------------------------------------------------------------*/

#include <string.h>

/*-------------------------------------------------------------------*/
/* Map an mIRC numeric color code (0-99) to a single-letter hint.    */
/* Returns 0 if the input is out of range.                           */
/*-------------------------------------------------------------------*/
static char mirc_color_letter(int code)
{
    static const char map[16] = {
        'W', '_', 'B', 'G', 'R', 'R', 'P', 'Y',
        'Y', 'G', 'T', 'T', 'B', 'P', 'W', 'W'
    };
    if (code < 0 || code > 15) return 0;
    return map[code];
}

/*-------------------------------------------------------------------*/
/* ircfmt_clean - strip mIRC formatting codes from src into dst,     */
/* returning the cleaned length and capturing the first explicit     */
/* foreground color found (one of W/R/G/Y/B/P/T) or '_' if none.     */
/*                                                                   */
/* dst and src may NOT overlap. dst is filled up to dst_max bytes;   */
/* the cleaned stream is truncated cleanly if it would overflow.     */
/* All bytes < 0x20 (ASCII control range) AND below 0x40 EBCDIC are  */
/* dropped - these are the dangerous attribute-byte values for a     */
/* 5250 DSPF char field.                                             */
/*                                                                   */
/* The src text is whatever IRCNETD passes - practically EBCDIC by   */
/* the time it gets here, but the mIRC marker bytes (0x02, 0x03,    */
/* 0x0F, 0x16, 0x1D, 0x1E, 0x1F) translate to themselves through    */
/* the identity slots of the tables.                                 */
/*-------------------------------------------------------------------*/
int ircfmt_clean(const unsigned char *src, int src_len,
                 unsigned char *dst, int dst_max,
                 char *out_color)
{
    int  in  = 0;
    int  out = 0;
    char dom = '_';

    while (in < src_len && out < dst_max) {
        unsigned char c = src[in];

        switch (c) {

        case 0x02:    /* bold      */
        case 0x0F:    /* reset     */
        case 0x16:    /* reverse   */
        case 0x1D:    /* italic    */
        case 0x1E:    /* strike    */
        case 0x1F:    /* underline */
            in++;
            break;

        case 0x03: {  /* color: \x03NN[,MM] */
            int fg = -1;
            int j;
            in++;
            /* Parse up to 2 ASCII digits (mIRC sends ASCII digits) */
            for (j = 0; j < 2 && in < src_len; j++, in++) {
                unsigned char d = src[in];
                if (d < '0' || d > '9') break;
                if (fg < 0) fg = 0;
                fg = fg * 10 + (d - '0');
            }
            /* Optional ,bg */
            if (in < src_len && src[in] == ',' &&
                in + 1 < src_len &&
                src[in+1] >= '0' && src[in+1] <= '9') {
                in++;
                for (j = 0; j < 2 && in < src_len; j++, in++) {
                    unsigned char d = src[in];
                    if (d < '0' || d > '9') break;
                }
            }
            if (fg >= 0 && dom == '_') {
                char letter = mirc_color_letter(fg);
                if (letter && letter != '_') dom = letter;
            }
            break;
        }

        case 0x04: {  /* hex color: \x04 RRGGBB[,RRGGBB] */
            int j;
            in++;
            for (j = 0; j < 6 && in < src_len; j++, in++) {
                unsigned char d = src[in];
                if (!((d >= '0' && d <= '9') ||
                      (d >= 'A' && d <= 'F') ||
                      (d >= 'a' && d <= 'f'))) break;
            }
            if (in < src_len && src[in] == ',') {
                in++;
                for (j = 0; j < 6 && in < src_len; j++, in++) {
                    unsigned char d = src[in];
                    if (!((d >= '0' && d <= '9') ||
                          (d >= 'A' && d <= 'F') ||
                          (d >= 'a' && d <= 'f'))) break;
                }
            }
            break;
        }

        default:
            /* Drop any other low control byte that would land as a    */
            /* screen-attribute on the 5250.                            */
            if (c < 0x40) {
                in++;
                break;
            }
            /* Otherwise keep the byte as-is. */
            dst[out++] = c;
            in++;
            break;
        }
    }

    if (out_color) *out_color = dom;
    return out;
}
