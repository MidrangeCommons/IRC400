/*-------------------------------------------------------------------*/
/* IRCSRVM - IRC Server Physical File Maintenance Helper             */
/*                                                                   */
/* ILE C program for CRUD operations on the IRCSRVR PF.              */
/* OPM CL cannot write/update/delete PF records natively, so this    */
/* helper is called from the menu programs. Mirrors NTPSRVM.         */
/*                                                                   */
/* Parameters (all by reference from CL):                            */
/*   1. Op       CHAR(1)   A=Add U=Update D=Delete R=Read            */
/*                          T=Toggle active L=List-after-seq         */
/*   2. Seq      CHAR(3)   Sequence/priority (zoned)                 */
/*   3. Name     CHAR(32)  Friendly name                             */
/*   4. Host     CHAR(64)  Hostname or IP                            */
/*   5. Port     CHAR(5)   TCP port (zoned)                          */
/*   6. Nick     CHAR(32)  Preferred nick                            */
/*   7. Active   CHAR(1)   '1' or '0'                                */
/*   8. Desc     CHAR(30)  Description                               */
/*   9. Retc     CHAR(4)   '0000'=OK '0001'=not found                */
/*                          '0002'=duplicate '0003'=I/O error        */
/*                                                                   */
/* Compile:                                                          */
/*   CRTBNDC PGM(IRCCLIENT/IRCSRVM)                                  */
/*           SRCFILE(IRCCLIENT/QCSRC) SRCMBR(IRCSRVM)                */
/*-------------------------------------------------------------------*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <decimal.h>
#include <recio.h>

/*-------------------------------------------------------------------*/
/* Record layout matching IRCSRVR PF (IRCSRVRR format)               */
/*-------------------------------------------------------------------*/
typedef _Packed struct {
    decimal(3,0) isseq;
    char         isname[32];
    char         ishost[64];
    decimal(5,0) isport;
    char         isnick[32];
    char         isact[1];
    char         isdesc[30];
} IrcSrvRec;

/*-------------------------------------------------------------------*/
/* Copy src into dest, blank-padding dest to destlen.                */
/* Trims trailing blanks/nulls from src first.                       */
/*-------------------------------------------------------------------*/
static void pad_blank(char *dest, const char *src,
                      int destlen, int srclen)
{
    int copylen;
    int i;

    copylen = srclen;
    if (copylen > destlen) copylen = destlen;

    while (copylen > 0 &&
           (src[copylen-1] == ' ' ||
            src[copylen-1] == 0x40 ||
            src[copylen-1] == '\0'))
        copylen--;

    memcpy(dest, src, copylen);
    for (i = copylen; i < destlen; i++)
        dest[i] = ' ';
}

/*-------------------------------------------------------------------*/
/* Numeric conversion helpers                                        */
/*-------------------------------------------------------------------*/
static decimal(3,0) char_to_dec3(const char *s)
{
    int val = 0;
    int i;
    for (i = 0; i < 3; i++) {
        if (s[i] >= '0' && s[i] <= '9')
            val = val * 10 + (s[i] - '0');
    }
    return (decimal(3,0))val;
}

static decimal(5,0) char_to_dec5(const char *s)
{
    int val = 0;
    int i;
    for (i = 0; i < 5; i++) {
        if (s[i] >= '0' && s[i] <= '9')
            val = val * 10 + (s[i] - '0');
    }
    return (decimal(5,0))val;
}

static void dec3_to_char(char *s, decimal(3,0) v)
{
    int val = (int)v;
    int i;
    if (val < 0) val = 0;
    for (i = 2; i >= 0; i--) {
        s[i] = (char)('0' + (val % 10));
        val /= 10;
    }
}

static void dec5_to_char(char *s, decimal(5,0) v)
{
    int val = (int)v;
    int i;
    if (val < 0) val = 0;
    for (i = 4; i >= 0; i--) {
        s[i] = (char)('0' + (val % 10));
        val /= 10;
    }
}

/*-------------------------------------------------------------------*/
/* Sequential scan to exact key match. Same V4R4 caveat as           */
/* NTPSRVM: avoids _Rlocate cursor unreliability.                    */
/*-------------------------------------------------------------------*/
static int read_by_key(_RFILE *fp, IrcSrvRec *rec,
                       decimal(3,0) seqkey)
{
    _RIOFB_T *fb;

    fb = _Rreadf(fp, (char *)rec, sizeof(*rec), __DFT);
    while (fb->num_bytes == sizeof(*rec)) {
        if (rec->isseq == seqkey) return 1;
        if (rec->isseq > seqkey)  return 0;
        fb = _Rreadn(fp, (char *)rec, sizeof(*rec), __DFT);
    }
    return 0;
}

/*-------------------------------------------------------------------*/
/* Main entry                                                        */
/*-------------------------------------------------------------------*/
int main(int argc, char *argv[])
{
    char  op;
    char *seqc;
    char *name;
    char *host;
    char *portc;
    char *nick;
    char *act;
    char *desc;
    char *retc;

    decimal(3,0) seqkey;
    _RFILE   *fp;
    IrcSrvRec rec;
    _RIOFB_T *fb;

    if (argc < 10) return 1;

    op    = argv[1][0];
    seqc  = argv[2];
    name  = argv[3];
    host  = argv[4];
    portc = argv[5];
    nick  = argv[6];
    act   = argv[7];
    desc  = argv[8];
    retc  = argv[9];

    memcpy(retc, "0000", 4);

    seqkey = char_to_dec3(seqc);

    fp = _Ropen("IRCCLIENT/IRCSRVR", "rr+");
    if (fp == NULL) {
        memcpy(retc, "0003", 4);
        return 0;
    }

    switch (op) {

    case 'A': /* Add */
        if (read_by_key(fp, &rec, seqkey)) {
            memcpy(retc, "0002", 4);
            break;
        }
        memset(&rec, ' ', sizeof(rec));
        rec.isseq = seqkey;
        pad_blank(rec.isname, name, 32, 32);
        pad_blank(rec.ishost, host, 64, 64);
        rec.isport = char_to_dec5(portc);
        pad_blank(rec.isnick, nick, 32, 32);
        rec.isact[0] = act[0];
        pad_blank(rec.isdesc, desc, 30, 30);

        fb = _Rwrite(fp, (char *)&rec, sizeof(rec));
        if (fb->num_bytes != sizeof(rec)) {
            memcpy(retc, "0003", 4);
        }
        break;

    case 'R': /* Read */
        if (!read_by_key(fp, &rec, seqkey)) {
            memcpy(retc, "0001", 4);
            break;
        }
        pad_blank(name,  rec.isname, 32, 32);
        pad_blank(host,  rec.ishost, 64, 64);
        dec5_to_char(portc, rec.isport);
        pad_blank(nick,  rec.isnick, 32, 32);
        act[0] = rec.isact[0];
        pad_blank(desc,  rec.isdesc, 30, 30);
        break;

    case 'U': /* Update */
        if (!read_by_key(fp, &rec, seqkey)) {
            memcpy(retc, "0001", 4);
            break;
        }
        pad_blank(rec.isname, name, 32, 32);
        pad_blank(rec.ishost, host, 64, 64);
        rec.isport = char_to_dec5(portc);
        pad_blank(rec.isnick, nick, 32, 32);
        rec.isact[0] = act[0];
        pad_blank(rec.isdesc, desc, 30, 30);

        fb = _Rupdate(fp, (char *)&rec, sizeof(rec));
        if (fb->num_bytes != sizeof(rec)) {
            memcpy(retc, "0003", 4);
        }
        break;

    case 'D': /* Delete */
        if (!read_by_key(fp, &rec, seqkey)) {
            memcpy(retc, "0001", 4);
            break;
        }
        fb = _Rdelete(fp);
        if (fb->num_bytes == 0) {
            memcpy(retc, "0003", 4);
        }
        break;

    case 'T': /* Toggle active */
        if (!read_by_key(fp, &rec, seqkey)) {
            memcpy(retc, "0001", 4);
            break;
        }
        rec.isact[0] = (rec.isact[0] == '1') ? '0' : '1';
        fb = _Rupdate(fp, (char *)&rec, sizeof(rec));
        if (fb->num_bytes != sizeof(rec)) {
            memcpy(retc, "0003", 4);
        }
        break;

    case 'L': /* List next: read first record with seq > input seq  */
        fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
        while (fb->num_bytes == sizeof(rec)) {
            if (rec.isseq > seqkey) break;
            fb = _Rreadn(fp, (char *)&rec, sizeof(rec), __DFT);
        }
        if (fb->num_bytes != sizeof(rec)) {
            memcpy(retc, "0001", 4);
            break;
        }
        dec3_to_char(seqc,  rec.isseq);
        pad_blank(name,  rec.isname, 32, 32);
        pad_blank(host,  rec.ishost, 64, 64);
        dec5_to_char(portc, rec.isport);
        pad_blank(nick,  rec.isnick, 32, 32);
        act[0] = rec.isact[0];
        pad_blank(desc,  rec.isdesc, 30, 30);
        break;

    default:
        memcpy(retc, "0003", 4);
        break;
    }

    _Rclose(fp);
    return 0;
}
