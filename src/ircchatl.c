/*-------------------------------------------------------------------*/
/* IRCCHATL - Chat Line Loader for IRC Client                        */
/*                                                                   */
/* Phase 6: every chat row is split into three segments so the DSPF  */
/* can colour the nick area independently of the timestamp and the   */
/* message body. Each row is still 76 bytes wide; the layout within  */
/* a row is:                                                         */
/*                                                                   */
/*    bytes  0..7    timestamp     "HH:MM:SS"     (always WHT)       */
/*    bytes  8..23   nick segment  "<nick>" / "***" / "--> nick"     */
/*                                  (16 chars, blank-padded)         */
/*    bytes 24..75   message body  IRCFMT-cleaned text (52 chars)    */
/*                                                                   */
/* The nick segment's colour is driven by a per-row 2-bit indicator  */
/* code emitted in a parallel KINDBUF parameter:                     */
/*                                                                   */
/*    "00"   system / numeric        -> WHT (default)                */
/*    "01"   PRIVMSG / ACTION        -> YLW                          */
/*    "10"   JOIN / PART / QUIT /                                    */
/*           TOPIC                   -> GRN                          */
/*    "11"   NOTICE                  -> TRQ                          */
/*                                                                   */
/* IRCCHATC sets indicators IN_HI/IN_LO per row from KINDBUF and     */
/* lets DDS conditional COLOR keywords pick the colour.              */
/*                                                                   */
/* Parameters (all by reference from CL):                            */
/*   1. Window seq      CHAR(4)    zoned, e.g. '0000' = status       */
/*   2. CHATBUF         CHAR(1444) 19 rows * 76 cols, packed         */
/*   3. KINDBUF         CHAR(38)   19 rows * 2 indicator bits        */
/*   4. Max seq seen    CHAR(9)    zoned - high-water for caller     */
/*                                                                   */
/* Compile:                                                          */
/*   CRTBNDC PGM(IRCCLIENT/IRCCHATL)                                 */
/*           SRCFILE(IRCCLIENT/QCSRC) SRCMBR(IRCCHATL)               */
/*-------------------------------------------------------------------*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <decimal.h>
#include <recio.h>

#define TS_W   8
#define NK_W  16
#define MS_W  52
#define LINE_W (TS_W + NK_W + MS_W)   /* 76 */
#define LINE_N 19
#define BUF_SZ (LINE_W * LINE_N)
#define KIND_PER_ROW 3            /* one bit per colour: YLW, GRN, TRQ */
#define KIND_BUF_SZ  (KIND_PER_ROW * LINE_N)

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
/* Numeric conversion helpers                                        */
/*-------------------------------------------------------------------*/
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

/*-------------------------------------------------------------------*/
/* Trim trailing blanks/nulls from a fixed-length field.             */
/*-------------------------------------------------------------------*/
static int trim_len(const char *s, int max)
{
    int n = max;
    while (n > 0 && (s[n-1] == ' '  || s[n-1] == 0x40 ||
                     s[n-1] == '\0' || s[n-1] == 0x00))
        n--;
    return n;
}

/*-------------------------------------------------------------------*/
/* Map MBKIND -> 3-char indicator triplet (currently unused; the     */
/* DSPF uses static fixed COLOR per field). Kept around for the      */
/* future "dynamic per-kind colour" enhancement.                     */
/*-------------------------------------------------------------------*/
static void kind_to_bits(char k, char out[KIND_PER_ROW])
{
    out[0] = out[1] = out[2] = '0';
    switch (k) {
    case 'M':
    case 'A':
        out[0] = '1'; return;
    case 'J':
    case 'P':
    case 'Q':
    case 'T':
        out[1] = '1'; return;
    case 'N':
        out[2] = '1'; return;
    case 'S':
    default:
        return;
    }
}

/*-------------------------------------------------------------------*/
/* Build the nick-segment text (16 chars, blank-padded) from a       */
/* MSGBUF record. The shape depends on MBKIND:                       */
/*                                                                   */
/*   M / A   "<nick>"                                                */
/*   J       "--> nick"                                              */
/*   P / Q   "<-- nick"                                              */
/*   N       "-nick-"                                                */
/*   T       "*topic*"                                               */
/*   S       "***"                                                   */
/*-------------------------------------------------------------------*/
static void format_nick(char out[NK_W], const MsgBufRec *rec)
{
    char tmp[NK_W + 8];
    int  written = 0;
    int  nick_len = trim_len(rec->mbnick, 32);

    memset(tmp, ' ', sizeof(tmp));

    switch (rec->mbkind[0]) {
    case 'M':
    case 'A':
        if (nick_len > 0) {
            tmp[written++] = '<';
            if (written + nick_len > NK_W - 1)
                nick_len = NK_W - 1 - written;
            memcpy(tmp + written, rec->mbnick, nick_len);
            written += nick_len;
            if (written < NK_W) tmp[written++] = '>';
        }
        break;

    case 'J':
        memcpy(tmp + written, "--> ", 4);
        written += 4;
        if (nick_len > 0 && written + nick_len <= NK_W) {
            memcpy(tmp + written, rec->mbnick, nick_len);
            written += nick_len;
        }
        break;

    case 'P':
    case 'Q':
        memcpy(tmp + written, "<-- ", 4);
        written += 4;
        if (nick_len > 0 && written + nick_len <= NK_W) {
            memcpy(tmp + written, rec->mbnick, nick_len);
            written += nick_len;
        }
        break;

    case 'N':
        if (nick_len > 0) {
            tmp[written++] = '-';
            if (written + nick_len > NK_W - 1)
                nick_len = NK_W - 1 - written;
            memcpy(tmp + written, rec->mbnick, nick_len);
            written += nick_len;
            if (written < NK_W) tmp[written++] = '-';
        }
        break;

    case 'T':
        memcpy(tmp + written, "*topic*", 7);
        written += 7;
        break;

    case 'S':
    default:
        memcpy(tmp + written, "***", 3);
        written += 3;
        break;
    }

    if (written > NK_W) written = NK_W;
    memcpy(out, tmp, written);
    if (written < NK_W)
        memset(out + written, ' ', NK_W - written);
}

/*-------------------------------------------------------------------*/
/* Build the message-body text (52 chars, blank-padded). For PRIVMSG */
/* and NOTICE this is just the trimmed fragment text. For other      */
/* kinds we add a tail clause where useful (e.g. " joined" after a   */
/* JOIN, the channel name from MBFRAGS for PART/QUIT).               */
/*-------------------------------------------------------------------*/
static void format_msg(char out[MS_W], const MsgBufRec *rec)
{
    int frag_len = trim_len(rec->mbfrags, 512);
    int copy     = frag_len < MS_W ? frag_len : MS_W;

    memset(out, ' ', MS_W);
    if (copy > 0) memcpy(out, rec->mbfrags, copy);
}

/*-------------------------------------------------------------------*/
/* Build TS+NICK+MSG packed into one 76-char row.                    */
/*-------------------------------------------------------------------*/
static void format_row(char out[LINE_W], const MsgBufRec *rec)
{
    /* Timestamp */
    memcpy(out, rec->mbts, TS_W);

    /* Nick */
    format_nick(out + TS_W, rec);

    /* Message */
    format_msg(out + TS_W + NK_W, rec);
}

/*-------------------------------------------------------------------*/
/* Main                                                              */
/*-------------------------------------------------------------------*/
int main(int argc, char *argv[])
{
    char            *win_arg;
    char            *buf_out;
    char            *kind_out;
    char            *maxseq_out;
    decimal(4,0)     win;
    _RFILE          *fp;
    MsgBufRec        rec;
    _RIOFB_T        *fb;
    decimal(9,0)     max_seq;
    decimal(9,0)     zero9 = (decimal(9,0))0;
    char             ring[LINE_N][LINE_W];
    char             kring[LINE_N][KIND_PER_ROW];
    int              ring_used = 0;
    int              ring_head = 0;
    int              i, src_idx, dst_row;

    if (argc < 5) return 1;
    win_arg    = argv[1];
    buf_out    = argv[2];
    kind_out   = argv[3];
    maxseq_out = argv[4];

    win     = char_to_dec4(win_arg);
    max_seq = zero9;

    /* Default output: blank chat region, all-WHT kind bits */
    memset(buf_out, ' ', BUF_SZ);
    memset(kind_out, '0', KIND_BUF_SZ);
    memset(ring, ' ', sizeof(ring));
    memset(kring, '0', sizeof(kring));

    fp = _Ropen("IRCCLIENT/MSGBUF", "rr");
    if (!fp) {
        dec9_to_char(maxseq_out, max_seq);
        return 0;
    }

    fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
    while (fb->num_bytes == sizeof(rec)) {
        if (rec.mbwin == win) {
            format_row(ring[ring_head], &rec);
            kind_to_bits(rec.mbkind[0], kring[ring_head]);
            ring_head = (ring_head + 1) % LINE_N;
            if (ring_used < LINE_N) ring_used++;
            if (rec.mbseq > max_seq) max_seq = rec.mbseq;
        }
        fb = _Rreadn(fp, (char *)&rec, sizeof(rec), __DFT);
    }
    _Rclose(fp);

    /*---------------------------------------------------------------*/
    /* Lay out the ring into the output buffers in chronological     */
    /* order. Newer lines occupy the bottom rows; if the ring is not */
    /* full, the leading rows remain blank with WHT bits ('00').     */
    /*---------------------------------------------------------------*/
    {
        int oldest = (ring_used < LINE_N) ? 0 : ring_head;
        for (i = 0; i < ring_used; i++) {
            src_idx = (oldest + i) % LINE_N;
            dst_row = LINE_N - ring_used + i;
            memcpy(buf_out  + dst_row * LINE_W,
                   ring[src_idx], LINE_W);
            memcpy(kind_out + dst_row * KIND_PER_ROW,
                   kring[src_idx], KIND_PER_ROW);
        }
    }

    dec9_to_char(maxseq_out, max_seq);
    return 0;
}
