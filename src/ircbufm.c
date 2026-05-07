/*-------------------------------------------------------------------*/
/* IRCBUFM - MSGBUF Maintenance for IRC Client                       */
/*                                                                   */
/* ILE C helper for record-level access to MSGBUF. OPM CL cannot     */
/* write/update/delete PF records natively, so this program is       */
/* called from the network engine and the chat panel controller.    */
/*                                                                   */
/* Parameters (all by reference from CL):                            */
/*   1. Op       CHAR(1)   A=Append, R=Read by seq,                  */
/*                          N=Next-after-seq, T=Trim<=seq,           */
/*                          C=Count records                          */
/*   2. Seq      CHAR(9)   Line sequence (zoned).                    */
/*                          A: '000000000' = auto-assign, output     */
/*                             returns assigned seq.                 */
/*                          N: input is "after this seq".            */
/*                          T: input is "delete <= this seq".        */
/*                          C: output is the record count.           */
/*   3. Win      CHAR(4)   Window seq (zoned).                       */
/*   4. Ts       CHAR(8)   HH:MM:SS local time.                      */
/*   5. Kind     CHAR(1)   M/N/S/A/J/P/Q/T per plan.md  8.           */
/*   6. Nick     CHAR(32)  Sender nick.                              */
/*   7. Ncol     CHAR(1)   Nick color code (W/R/G/Y/B/P/T).          */
/*   8. Frags    CHAR(512) IRCFMT-encoded fragment list.             */
/*   9. Retc     CHAR(4)   '0000'=OK '0001'=not found                */
/*                          '0003'=I/O error                         */
/*                                                                   */
/* Compile:                                                          */
/*   CRTBNDC PGM(IRCCLIENT/IRCBUFM)                                  */
/*           SRCFILE(IRCCLIENT/QCSRC) SRCMBR(IRCBUFM)                */
/*-------------------------------------------------------------------*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <decimal.h>
#include <recio.h>

/*-------------------------------------------------------------------*/
/* Record layout matching MSGBUF PF (MSGBUFR format)                 */
/*-------------------------------------------------------------------*/
typedef _Packed struct {
    decimal(9,0) mbseq;
    decimal(4,0) mbwin;
    char         mbts[8];
    char         mbkind[1];
    char         mbnick[32];
    char         mbncol[1];
    char         mbfrags[512];
} MsgBufRec;

/*-------------------------------------------------------------------*/
/* Decimal/CHAR conversion helpers                                   */
/* CL passes numerics as zoned-decimal CHAR strings. We convert      */
/* on the way in/out.                                                */
/*-------------------------------------------------------------------*/
static decimal(9,0) char_to_dec9(const char *s)
{
    long long val = 0;
    int i;
    for (i = 0; i < 9; i++) {
        if (s[i] >= '0' && s[i] <= '9')
            val = val * 10 + (s[i] - '0');
    }
    return (decimal(9,0))val;
}

static decimal(4,0) char_to_dec4(const char *s)
{
    int val = 0;
    int i;
    for (i = 0; i < 4; i++) {
        if (s[i] >= '0' && s[i] <= '9')
            val = val * 10 + (s[i] - '0');
    }
    return (decimal(4,0))val;
}

static void dec9_to_char(char *s, decimal(9,0) v)
{
    long long val = (long long)v;
    int i;
    if (val < 0) val = 0;
    for (i = 8; i >= 0; i--) {
        s[i] = (char)('0' + (val % 10));
        val /= 10;
    }
}

static void dec4_to_char(char *s, decimal(4,0) v)
{
    int val = (int)v;
    int i;
    if (val < 0) val = 0;
    for (i = 3; i >= 0; i--) {
        s[i] = (char)('0' + (val % 10));
        val /= 10;
    }
}

/*-------------------------------------------------------------------*/
/* Copy raw bytes out from a record field, blank-padding excess.     */
/* Used to return CHAR fields back to CL caller.                     */
/*-------------------------------------------------------------------*/
static void copy_out(char *dest, const char *src, int len)
{
    memcpy(dest, src, len);
}

/*-------------------------------------------------------------------*/
/* Main entry                                                        */
/*-------------------------------------------------------------------*/
int main(int argc, char *argv[])
{
    char  op;
    char *seq;
    char *win;
    char *ts;
    char *kind;
    char *nick;
    char *ncol;
    char *frags;
    char *retc;

    decimal(9,0) seqkey;
    decimal(9,0) zero9 = (decimal(9,0))0;
    decimal(9,0) one9  = (decimal(9,0))1;
    long long count;

    _RFILE   *fp;
    MsgBufRec rec;
    _RIOFB_T *fb;

    if (argc < 10) return 1;

    op    = argv[1][0];
    seq   = argv[2];
    win   = argv[3];
    ts    = argv[4];
    kind  = argv[5];
    nick  = argv[6];
    ncol  = argv[7];
    frags = argv[8];
    retc  = argv[9];

    memcpy(retc, "0000", 4);

    fp = _Ropen("IRCCLIENT/MSGBUF", "rr+");
    if (fp == NULL) {
        memcpy(retc, "0003", 4);
        return 0;
    }

    seqkey = char_to_dec9(seq);

    switch (op) {

    case 'A': /* Append a new record */
        /* Auto-assign seq if caller passed all zeros.        */
        /* _Rreadl is not used: NTPSRVM proves that _Rreadf + */
        /* _Rreadn is the reliable V4R4 path for keyed PFs.   */
        if (seqkey == zero9) {
            decimal(9,0) maxseq = zero9;
            fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
            while (fb->num_bytes == sizeof(rec)) {
                if (rec.mbseq > maxseq) maxseq = rec.mbseq;
                fb = _Rreadn(fp, (char *)&rec, sizeof(rec),
                             __DFT);
            }
            seqkey = maxseq + one9;
        }

        memset(&rec, ' ', sizeof(rec));
        rec.mbseq    = seqkey;
        rec.mbwin    = char_to_dec4(win);
        memcpy(rec.mbts,    ts,    8);
        rec.mbkind[0]   = kind[0];
        memcpy(rec.mbnick,  nick,  32);
        rec.mbncol[0]   = ncol[0];
        memcpy(rec.mbfrags, frags, 512);

        fb = _Rwrite(fp, (char *)&rec, sizeof(rec));
        if (fb->num_bytes != sizeof(rec)) {
            memcpy(retc, "0003", 4);
        } else {
            dec9_to_char(seq, seqkey);
        }
        break;

    case 'R': /* Read by exact seq                                   */
        /* Sequential scan since V4R4 _Rlocate cursor positioning   */
        /* on packed-decimal keys is unreliable.                     */
        fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
        while (fb->num_bytes == sizeof(rec)) {
            if (rec.mbseq == seqkey) {
                dec4_to_char(win, rec.mbwin);
                copy_out(ts,    rec.mbts,    8);
                kind[0] = rec.mbkind[0];
                copy_out(nick,  rec.mbnick,  32);
                ncol[0] = rec.mbncol[0];
                copy_out(frags, rec.mbfrags, 512);
                _Rclose(fp);
                return 0;
            }
            if (rec.mbseq > seqkey) break;
            fb = _Rreadn(fp, (char *)&rec, sizeof(rec), __DFT);
        }
        memcpy(retc, "0001", 4);
        break;

    case 'N': /* Read first record with seq > input seq              */
        fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
        while (fb->num_bytes == sizeof(rec)) {
            if (rec.mbseq > seqkey) {
                dec9_to_char(seq, rec.mbseq);
                dec4_to_char(win, rec.mbwin);
                copy_out(ts,    rec.mbts,    8);
                kind[0] = rec.mbkind[0];
                copy_out(nick,  rec.mbnick,  32);
                ncol[0] = rec.mbncol[0];
                copy_out(frags, rec.mbfrags, 512);
                _Rclose(fp);
                return 0;
            }
            fb = _Rreadn(fp, (char *)&rec, sizeof(rec), __DFT);
        }
        memcpy(retc, "0001", 4);
        break;

    case 'T': /* Trim: delete records with seq <= input seq          */
        fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
        while (fb->num_bytes == sizeof(rec) && rec.mbseq <= seqkey) {
            _Rdelete(fp);
            fb = _Rreadn(fp, (char *)&rec, sizeof(rec), __DFT);
        }
        break;

    case 'C': /* Count records - returned in seq parameter           */
        count = 0;
        fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
        while (fb->num_bytes == sizeof(rec)) {
            count++;
            fb = _Rreadn(fp, (char *)&rec, sizeof(rec), __DFT);
        }
        dec9_to_char(seq, (decimal(9,0))count);
        break;

    default:
        memcpy(retc, "0003", 4);
        break;
    }

    _Rclose(fp);
    return 0;
}
