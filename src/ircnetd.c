/*-------------------------------------------------------------------*/
/* IRCNETD - IRC Network Engine for OS/400 V4R5+ (Phase 3)           */
/*                                                                   */
/* Owns the TCP socket. Parses incoming IRC lines, appends each one  */
/* as a MSGBUF record, and pings IRCEVTQ so the chat panel wakes up. */
/* Reads outbound IRC commands from IRCOUTQ; understands two control */
/* prefixes:                                                         */
/*                                                                   */
/*   'C' <payload>   - send <payload> as a raw IRC line (CRLF added) */
/*   'X'             - send QUIT and shut down cleanly               */
/*                                                                   */
/* Reconnects with exponential backoff (5/10/30/60 s, capped) unless */
/* an 'X' arrived on IRCOUTQ. The backoff sleep itself polls IRCOUTQ */
/* once per second so 'X' aborts a pending reconnect.                */
/*                                                                   */
/* Parameters:                                                       */
/*   1. Host       CHAR(64)  IRC server hostname or IP               */
/*   2. Port       CHAR(8)   TCP port (zoned digits)                 */
/*   3. Nick       CHAR(32)  IRC nick                                */
/*   4. Realname   CHAR(64)  (optional) IRC USER realname            */
/*                                                                   */
/* Compile:                                                          */
/*   CRTBNDC PGM(IRCCLIENT/IRCNETD)                                  */
/*           SRCFILE(IRCCLIENT/QCSRC) SRCMBR(IRCNETD)                */
/*           SYSIFCOPT(*IFSIO)                                       */
/*-------------------------------------------------------------------*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <decimal.h>
#include <recio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

/*-------------------------------------------------------------------*/
/* Constants                                                         */
/*-------------------------------------------------------------------*/
#define IRC_BUFSIZE     4096
#define IRC_LINE_MAX    1024
#define IRC_SEND_MAX    600
#define DNS_TIMEOUT     10
#define CONN_TIMEOUT    30
#define DNS_PORT        53
#define DEFAULT_PORT    6667
#define POLL_INTERVAL_US  100000   /* 100 ms - per loop iteration */
#define BACKOFF_INITIAL    5
#define BACKOFF_MAX        60
#define OUTQ_DATA_MAX    512

/*-------------------------------------------------------------------*/
/* OS/400 system API prototypes - dynamic program-call linkage.      */
/* No additional binding required at CRTBNDC time.                   */
/*-------------------------------------------------------------------*/
#pragma linkage(QRCVDTAQ, OS)
extern void QRCVDTAQ(char *qname,        /* CHAR(10) */
                     char *qlib,         /* CHAR(10) */
                     char *data_len,     /* PACKED(5,0) in/out */
                     char *data,         /* CHAR(*) out  */
                     char *wait_time);   /* PACKED(5,0) in   */

#pragma linkage(QSNDDTAQ, OS)
extern void QSNDDTAQ(char *qname,        /* CHAR(10) */
                     char *qlib,         /* CHAR(10) */
                     char *data_len,     /* PACKED(5,0) in   */
                     char *data);        /* CHAR(*) in       */

/*-------------------------------------------------------------------*/
/* IRCFMT module - linked in via CRTPGM (see build.clp).             */
/*-------------------------------------------------------------------*/
extern int ircfmt_clean(const unsigned char *src, int src_len,
                        unsigned char *dst, int dst_max,
                        char *out_color);

/*-------------------------------------------------------------------*/
/* MSGBUF record layout (must match msgbuf.pf MSGBUFR format)        */
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
/* Globals                                                            */
/*-------------------------------------------------------------------*/
static unsigned char a2e_tbl[256];
static unsigned char e2a_tbl[256];

static int           g_disconnect_requested = 0;
static decimal(9,0)  g_next_seq;       /* set in main() */
static decimal(9,0)  g_zero9 = (decimal(9,0))0;
static decimal(9,0)  g_one9  = (decimal(9,0))1;

/*-------------------------------------------------------------------*/
/* EBCDIC <-> ASCII tables (CCSID 37 <-> 819) - same as Phase 2      */
/*-------------------------------------------------------------------*/
static void init_tables(void)
{
    int i;

    for (i = 0; i < 256; i++) {
        a2e_tbl[i] = (unsigned char)i;
        e2a_tbl[i] = (unsigned char)i;
    }

    a2e_tbl[0x20] = 0x40;  a2e_tbl[0x21] = 0x5A;  a2e_tbl[0x22] = 0x7F;
    a2e_tbl[0x23] = 0x7B;  a2e_tbl[0x24] = 0x5B;  a2e_tbl[0x25] = 0x6C;
    a2e_tbl[0x26] = 0x50;  a2e_tbl[0x27] = 0x7D;  a2e_tbl[0x28] = 0x4D;
    a2e_tbl[0x29] = 0x5D;  a2e_tbl[0x2A] = 0x5C;  a2e_tbl[0x2B] = 0x4E;
    a2e_tbl[0x2C] = 0x6B;  a2e_tbl[0x2D] = 0x60;  a2e_tbl[0x2E] = 0x4B;
    a2e_tbl[0x2F] = 0x61;
    for (i = 0; i < 10; i++) a2e_tbl[0x30 + i] = 0xF0 + i;
    a2e_tbl[0x3A] = 0x7A;  a2e_tbl[0x3B] = 0x5E;  a2e_tbl[0x3C] = 0x4C;
    a2e_tbl[0x3D] = 0x7E;  a2e_tbl[0x3E] = 0x6E;  a2e_tbl[0x3F] = 0x6F;
    a2e_tbl[0x40] = 0x7C;
    for (i = 0; i < 9; i++) a2e_tbl[0x41 + i] = 0xC1 + i;
    for (i = 0; i < 9; i++) a2e_tbl[0x4A + i] = 0xD1 + i;
    for (i = 0; i < 8; i++) a2e_tbl[0x53 + i] = 0xE2 + i;
    a2e_tbl[0x5B] = 0xBA;  a2e_tbl[0x5C] = 0xE0;  a2e_tbl[0x5D] = 0xBB;
    a2e_tbl[0x5E] = 0xB0;  a2e_tbl[0x5F] = 0x6D;  a2e_tbl[0x60] = 0x79;
    for (i = 0; i < 9; i++) a2e_tbl[0x61 + i] = 0x81 + i;
    for (i = 0; i < 9; i++) a2e_tbl[0x6A + i] = 0x91 + i;
    for (i = 0; i < 8; i++) a2e_tbl[0x73 + i] = 0xA2 + i;
    a2e_tbl[0x7B] = 0xC0;  a2e_tbl[0x7C] = 0x4F;  a2e_tbl[0x7D] = 0xD0;
    a2e_tbl[0x7E] = 0xA1;
    a2e_tbl[0x09] = 0x05;  a2e_tbl[0x0A] = 0x25;  a2e_tbl[0x0D] = 0x0D;

    for (i = 0; i < 256; i++) {
        if (a2e_tbl[i] != (unsigned char)i || i == 0) {
            e2a_tbl[a2e_tbl[i]] = (unsigned char)i;
        }
    }
    e2a_tbl[0x0D] = 0x0D;
    e2a_tbl[0x25] = 0x0A;
    e2a_tbl[0x15] = 0x0A;
}

static void translate_a2e(unsigned char *buf, int len)
{
    int i;
    for (i = 0; i < len; i++) buf[i] = a2e_tbl[buf[i]];
}

static void translate_e2a(unsigned char *buf, int len)
{
    int i;
    for (i = 0; i < len; i++) buf[i] = e2a_tbl[buf[i]];
}

static void trim_right(char *s)
{
    int n = (int)strlen(s);
    while (n > 0 && (s[n-1] == ' '  || s[n-1] == 0x40 ||
                     s[n-1] == '\0' || s[n-1] == 0x00))
        s[--n] = '\0';
}

/*-------------------------------------------------------------------*/
/* MSGBUF helpers                                                    */
/*-------------------------------------------------------------------*/
static void load_max_seq(void)
{
    _RFILE   *fp;
    MsgBufRec rec;
    _RIOFB_T *fb;
    decimal(9,0) max_seq = g_zero9;

    fp = _Ropen("IRCCLIENT/MSGBUF", "rr");
    if (!fp) {
        g_next_seq = g_one9;
        return;
    }
    fb = _Rreadf(fp, (char *)&rec, sizeof(rec), __DFT);
    while (fb->num_bytes == sizeof(rec)) {
        if (rec.mbseq > max_seq) max_seq = rec.mbseq;
        fb = _Rreadn(fp, (char *)&rec, sizeof(rec), __DFT);
    }
    _Rclose(fp);
    g_next_seq = max_seq + g_one9;
}

/*-------------------------------------------------------------------*/
/* Append a record to MSGBUF. Inputs are EBCDIC; the caller is       */
/* responsible for any necessary translation (see read loop).        */
/*                                                                   */
/* In Phase 3 we store raw EBCDIC text directly in MBFRAGS - the     */
/* IRCFMT-encoded fragment format arrives in Phase 6.                */
/*-------------------------------------------------------------------*/
static void msgbuf_append(int win, char kind,
                          const char *nick, char line_color,
                          const char *frags, int frags_len)
{
    _RFILE   *fp;
    MsgBufRec rec;
    _RIOFB_T *fb;
    time_t    now;
    struct tm *lt;
    int       nick_len;

    fp = _Ropen("IRCCLIENT/MSGBUF", "rr+");
    if (!fp) {
        printf("[msgbuf] open failed for append\n");
        return;
    }

    memset(&rec, ' ', sizeof(rec));

    rec.mbseq = g_next_seq;
    g_next_seq = g_next_seq + g_one9;

    rec.mbwin = (decimal(4,0))win;

    /* mbts is char[8], no NUL terminator. sprintf-then-memcpy via   */
    /* a 16-byte scratch buffer avoids the off-by-one overflow that  */
    /* writing "HH:MM:SS\0" (9 bytes) into mbts[8] would cause.      */
    now = time(NULL);
    lt  = localtime(&now);
    {
        char tsbuf[16];
        int  tslen;
        if (lt) {
            tslen = sprintf(tsbuf, "%02d:%02d:%02d",
                            lt->tm_hour, lt->tm_min, lt->tm_sec);
        } else {
            tslen = sprintf(tsbuf, "00:00:00");
        }
        if (tslen > 8) tslen = 8;
        memcpy(rec.mbts, tsbuf, tslen);
    }

    rec.mbkind[0] = kind;

    if (nick) {
        nick_len = (int)strlen(nick);
        if (nick_len > 32) nick_len = 32;
        memcpy(rec.mbnick, nick, nick_len);
    }

    /* MBNCOL holds the dominant line color hint extracted by IRCFMT. */
    rec.mbncol[0] = (line_color != 0) ? line_color : 'W';

    if (frags && frags_len > 0) {
        if (frags_len > 512) frags_len = 512;
        memcpy(rec.mbfrags, frags, frags_len);
    }

    fb = _Rwrite(fp, (char *)&rec, sizeof(rec));
    if (fb->num_bytes != sizeof(rec)) {
        printf("[msgbuf] write failed (rc=%d)\n",
               (int)fb->num_bytes);
    }
    _Rclose(fp);
}

/*-------------------------------------------------------------------*/
/* IPC helpers                                                       */
/*-------------------------------------------------------------------*/
static void evtq_wakeup(void)
{
    char qname[10];
    char qlib[10];
    decimal(5,0) dlen = (decimal(5,0))1;
    char data[1];

    memset(qname, ' ', 10); memcpy(qname, "IRCEVTQ",   7);
    memset(qlib,  ' ', 10); memcpy(qlib,  "IRCCLIENT", 9);
    data[0] = 'X';

    QSNDDTAQ(qname, qlib, (char *)&dlen, data);
}

/*-------------------------------------------------------------------*/
/* Non-blocking IRCOUTQ check. Returns bytes received (0 if empty).  */
/* Output buffer holds raw EBCDIC bytes from CL caller.              */
/*-------------------------------------------------------------------*/
static int outq_check(char *buf, int max_len)
{
    char qname[10];
    char qlib[10];
    decimal(5,0) dlen;
    decimal(5,0) wait = (decimal(5,0))0;

    memset(qname, ' ', 10); memcpy(qname, "IRCOUTQ",   7);
    memset(qlib,  ' ', 10); memcpy(qlib,  "IRCCLIENT", 9);
    dlen = (decimal(5,0))max_len;

    QRCVDTAQ(qname, qlib, (char *)&dlen, buf, (char *)&wait);
    return (int)dlen;
}

/*-------------------------------------------------------------------*/
/* DNS resolver - Phase 2 implementation, unchanged                  */
/*-------------------------------------------------------------------*/
static int resolve_with_timeout(const char *host,
                                struct in_addr *result,
                                int timeout_sec)
{
    unsigned char qbuf[512];
    unsigned char rbuf[512];
    int qlen, rc, sock, fromlen, labellen;
    int i, ancount;
    unsigned int rdlen, rtype;
    struct sockaddr_in dns;
    struct sockaddr_in from;
    struct timeval tv;
    fd_set rfds;
    const char *p;
    const char *dot;
    unsigned char *q;
    unsigned long addr;

    /* Try inet_addr first - it accepts EBCDIC on OS/400 directly. */
    addr = inet_addr((char *)host);
    if (addr != 0xFFFFFFFF) {
        result->s_addr = addr;
        return 0;
    }

    memset(qbuf, 0, sizeof(qbuf));
    qbuf[0] = 0x12; qbuf[1] = 0x34;
    qbuf[2] = 0x01; qbuf[3] = 0x00;
    qbuf[4] = 0x00; qbuf[5] = 0x01;

    q = qbuf + 12;
    p = host;
    while (*p) {
        dot = p;
        while (*dot && *dot != '.' && *dot != 0x4B) dot++;
        labellen = (int)(dot - p);
        if (labellen <= 0 || labellen > 63) return -1;
        *q++ = (unsigned char)labellen;
        memcpy(q, p, labellen);
        translate_e2a(q, labellen);
        q += labellen;
        p = (*dot == '.' || *dot == 0x4B) ? dot + 1 : dot;
    }
    *q++ = 0;
    *q++ = 0x00; *q++ = 0x01;
    *q++ = 0x00; *q++ = 0x01;
    qlen = (int)(q - qbuf);

    sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) return -1;

    memset(&dns, 0, sizeof(dns));
    dns.sin_family = AF_INET;
    dns.sin_port   = htons(DNS_PORT);
    dns.sin_addr.s_addr = inet_addr("1.1.1.1");

    rc = sendto(sock, (char *)qbuf, qlen, 0,
                (struct sockaddr *)&dns, sizeof(dns));
    if (rc < 0) { close(sock); return -1; }

    FD_ZERO(&rfds);
    FD_SET(sock, &rfds);
    tv.tv_sec  = timeout_sec;
    tv.tv_usec = 0;
    rc = select(sock + 1, &rfds, NULL, NULL, &tv);
    if (rc <= 0) { close(sock); return -1; }

    fromlen = sizeof(from);
    rc = recvfrom(sock, (char *)rbuf, sizeof(rbuf), 0,
                  (struct sockaddr *)&from, &fromlen);
    close(sock);
    if (rc < 12) return -1;
    if (rbuf[0] != 0x12 || rbuf[1] != 0x34) return -1;
    if ((rbuf[2] & 0x80) == 0) return -1;
    if ((rbuf[3] & 0x0F) != 0) return -1;

    ancount = (rbuf[6] << 8) | rbuf[7];
    if (ancount == 0) return -1;

    q = rbuf + 12;
    while (*q) {
        if ((*q & 0xC0) == 0xC0) { q += 2; break; }
        q += *q + 1;
    }
    if (*q == 0) q++;
    q += 4;

    for (i = 0; i < ancount; i++) {
        if ((*q & 0xC0) == 0xC0) { q += 2; }
        else {
            while (*q) q += *q + 1;
            q++;
        }
        rtype = (q[0] << 8) | q[1];
        rdlen = (q[8] << 8) | q[9];
        q += 10;
        if (rtype == 1 && rdlen == 4) {
            memcpy(result, q, 4);
            return 0;
        }
        q += rdlen;
        if (q >= rbuf + rc) return -1;
    }
    return -1;
}

/*-------------------------------------------------------------------*/
/* TCP connect with select() timeout                                 */
/*-------------------------------------------------------------------*/
static int connect_with_timeout(struct sockaddr_in *addr, int timeout_sec)
{
    int sock;
    int result;
    int err;
    int errlen;
    fd_set wfds, efds;
    struct timeval tv;
    int yes = 1;
    int no  = 0;

    sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) return -1;

    if (ioctl(sock, FIONBIO, &yes) < 0) {
        close(sock);
        return -1;
    }

    result = connect(sock, (struct sockaddr *)addr, sizeof(*addr));
    if (result < 0 && errno != EINPROGRESS && errno != EWOULDBLOCK) {
        close(sock);
        return -1;
    }

    if (result < 0) {
        FD_ZERO(&wfds); FD_SET(sock, &wfds);
        FD_ZERO(&efds); FD_SET(sock, &efds);
        tv.tv_sec  = timeout_sec;
        tv.tv_usec = 0;

        result = select(sock + 1, NULL, &wfds, &efds, &tv);
        if (result <= 0) {
            close(sock);
            return -1;
        }
        err    = 0;
        errlen = sizeof(err);
        if (getsockopt(sock, SOL_SOCKET, SO_ERROR,
                       (char *)&err, &errlen) < 0 || err != 0) {
            close(sock);
            return -1;
        }
    }

    ioctl(sock, FIONBIO, &no);
    return sock;
}

/*-------------------------------------------------------------------*/
/* Send an EBCDIC-encoded line over TCP, translating on the way.     */
/*-------------------------------------------------------------------*/
static int irc_send_line(int sock, const char *ebcdic, int len)
{
    unsigned char wire[IRC_SEND_MAX];
    int wlen = len;
    if (wlen <= 0) return 0;
    if (wlen > (int)sizeof(wire)) wlen = sizeof(wire);
    memcpy(wire, ebcdic, wlen);
    translate_e2a(wire, wlen);
    return send(sock, (char *)wire, wlen, 0);
}

/*-------------------------------------------------------------------*/
/* Line reader                                                       */
/*-------------------------------------------------------------------*/
typedef struct {
    unsigned char buf[IRC_BUFSIZE];
    int           len;
    int           closed;
} LineReader;

/*-------------------------------------------------------------------*/
/* Non-blocking line reader. Socket must be set non-blocking before  */
/* the first call (run_session does this after connect succeeds).    */
/*                                                                   */
/* Returns:                                                          */
/*   > 0   line length, line copied to *out                          */
/*   = 0   no full line ready right now - caller should select again */
/*   < 0   socket closed or fatal error                              */
/*-------------------------------------------------------------------*/
static int next_line(int sock, LineReader *lr,
                     unsigned char *out, int outsize)
{
    int i, n, copylen;
    int recv_attempted = 0;

    for (;;) {
        for (i = 0; i + 1 < lr->len; i++) {
            if (lr->buf[i] == 0x0D && lr->buf[i+1] == 0x0A) {
                copylen = i;
                if (copylen > outsize - 1) copylen = outsize - 1;
                memcpy(out, lr->buf, copylen);
                out[copylen] = 0;
                memmove(lr->buf, lr->buf + i + 2,
                        lr->len - (i + 2));
                lr->len -= (i + 2);
                return copylen;
            }
        }

        if (recv_attempted) return 0;

        if (lr->len >= (int)sizeof(lr->buf)) {
            lr->len = 0;
            return -1;
        }
        if (lr->closed) return -1;

        n = recv(sock, (char *)(lr->buf + lr->len),
                 sizeof(lr->buf) - lr->len, 0);
        if (n == 0) {
            lr->closed = 1;
            return -1;
        }
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK ||
                errno == EINTR) {
                return 0;
            }
            lr->closed = 1;
            return -1;
        }
        lr->len += n;
        recv_attempted = 1;
    }
}

/*-------------------------------------------------------------------*/
/* IRC parser                                                        */
/*-------------------------------------------------------------------*/
#define MAX_PARAMS 16

typedef struct {
    char prefix[256];
    char command[32];
    char params[MAX_PARAMS][256];
    int  nparams;
    char trailing[512];
    int  has_trailing;
} IrcMsg;

static void parse_irc(const char *line, IrcMsg *m)
{
    const char *p = line;
    int  i;

    memset(m, 0, sizeof(*m));

    if (*p == ':') {
        p++;
        i = 0;
        while (*p && *p != ' ' && i < (int)sizeof(m->prefix) - 1)
            m->prefix[i++] = *p++;
        m->prefix[i] = '\0';
        while (*p == ' ') p++;
    }

    i = 0;
    while (*p && *p != ' ' && i < (int)sizeof(m->command) - 1)
        m->command[i++] = *p++;
    m->command[i] = '\0';
    while (*p == ' ') p++;

    while (*p && m->nparams < MAX_PARAMS) {
        if (*p == ':') {
            p++;
            i = 0;
            while (*p && i < (int)sizeof(m->trailing) - 1)
                m->trailing[i++] = *p++;
            m->trailing[i] = '\0';
            m->has_trailing = 1;
            break;
        }
        i = 0;
        while (*p && *p != ' '
               && i < (int)sizeof(m->params[0]) - 1)
            m->params[m->nparams][i++] = *p++;
        m->params[m->nparams][i] = '\0';
        m->nparams++;
        while (*p == ' ') p++;
    }
}

/*-------------------------------------------------------------------*/
/* Map an IRC command to a single-byte MBKIND for MSGBUF.            */
/* Numerics (3 ASCII digits, EBCDIC 0xF0..0xF9) classify as system.  */
/*-------------------------------------------------------------------*/
static char kind_for(const char *command)
{
    if (strcmp(command, "PRIVMSG") == 0) return 'M';
    if (strcmp(command, "NOTICE")  == 0) return 'N';
    if (strcmp(command, "JOIN")    == 0) return 'J';
    if (strcmp(command, "PART")    == 0) return 'P';
    if (strcmp(command, "QUIT")    == 0) return 'Q';
    if (strcmp(command, "TOPIC")   == 0) return 'T';
    return 'S';   /* numeric, ERROR, MODE, NICK, etc. */
}

/*-------------------------------------------------------------------*/
/* Extract the sender nick from "nick!user@host" prefix; falls back  */
/* to the full prefix if no '!' is present (servers without user).   */
/*-------------------------------------------------------------------*/
static void prefix_to_nick(const char *prefix, char *nick_out, int max)
{
    int i;
    memset(nick_out, 0, max);
    for (i = 0; i < max - 1 && prefix[i] && prefix[i] != '!'; i++)
        nick_out[i] = prefix[i];
}

/*-------------------------------------------------------------------*/
/* Compose a flat display string for MBFRAGS from a parsed IRC msg,  */
/* then run it through IRCFMT to strip mIRC formatting bytes (so     */
/* nothing < 0x40 reaches the DSPF chat field as an attribute byte). */
/* Returns cleaned length and writes the dominant color letter into  */
/* *out_color.                                                       */
/*-------------------------------------------------------------------*/
static int compose_frags(const IrcMsg *m, char *out, int max,
                         char *out_color)
{
    char raw[600];
    int  raw_len = 0;
    int  i;

    /* For PRIVMSG/NOTICE the trailing IS the message body.          */
    if ((strcmp(m->command, "PRIVMSG") == 0 ||
         strcmp(m->command, "NOTICE")  == 0) && m->has_trailing) {
        int n = (int)strlen(m->trailing);
        if (n > (int)sizeof(raw)) n = sizeof(raw);
        memcpy(raw, m->trailing, n);
        raw_len = n;
    }
    else {
        /* Join command + params + trailing into one readable line.  */
        int n = (int)strlen(m->command);
        if (n > (int)sizeof(raw) - raw_len) n = sizeof(raw) - raw_len;
        memcpy(raw + raw_len, m->command, n);
        raw_len += n;
        for (i = 0; i < m->nparams && raw_len < (int)sizeof(raw) - 1; i++) {
            raw[raw_len++] = ' ';
            n = (int)strlen(m->params[i]);
            if (n > (int)sizeof(raw) - raw_len) n = sizeof(raw) - raw_len;
            memcpy(raw + raw_len, m->params[i], n);
            raw_len += n;
        }
        if (m->has_trailing && raw_len < (int)sizeof(raw) - 2) {
            raw[raw_len++] = ' ';
            raw[raw_len++] = ':';
            n = (int)strlen(m->trailing);
            if (n > (int)sizeof(raw) - raw_len) n = sizeof(raw) - raw_len;
            memcpy(raw + raw_len, m->trailing, n);
            raw_len += n;
        }
    }

    return ircfmt_clean((const unsigned char *)raw, raw_len,
                        (unsigned char *)out, max, out_color);
}

/*-------------------------------------------------------------------*/
/* Outbound queue dispatch.                                          */
/* Entry format: byte 0 = type ('C' = command, 'X' = exit).          */
/* Returns 1 if an exit was requested, 0 otherwise.                  */
/*-------------------------------------------------------------------*/
static int dispatch_outq(int sock, const char *data, int len)
{
    char buf[IRC_SEND_MAX];
    int  payload_len;
    int  out_len;

    if (len <= 0) return 0;

    switch (data[0]) {

    case 'X':
        printf("[outq] X (shutdown) received\n");
        irc_send_line(sock, "QUIT :IRC400 client shutdown\r\n", 30);
        g_disconnect_requested = 1;
        return 1;

    case 'C':
        payload_len = len - 1;
        if (payload_len <= 0) return 0;
        if (payload_len > (int)sizeof(buf) - 2)
            payload_len = sizeof(buf) - 2;
        memcpy(buf, data + 1, payload_len);
        buf[payload_len]     = '\r';
        buf[payload_len + 1] = '\n';
        out_len = payload_len + 2;
        if (irc_send_line(sock, buf, out_len) < 0) {
            printf("[outq] send failed (errno=%d)\n", errno);
        } else {
            /* Echo to spool, sans CRLF, for debugging */
            buf[payload_len] = '\0';
            printf("[send] %s\n", buf);
        }
        return 0;

    default:
        printf("[outq] unknown type 0x%02X (len=%d)\n",
               (unsigned char)data[0], len);
        return 0;
    }
}

/*-------------------------------------------------------------------*/
/* Interruptible sleep - returns early if 'X' lands on IRCOUTQ.      */
/*-------------------------------------------------------------------*/
static void interruptible_sleep(int seconds)
{
    char outq_buf[OUTQ_DATA_MAX];
    int  i, got;

    for (i = 0; i < seconds && !g_disconnect_requested; i++) {
        sleep(1);
        got = outq_check(outq_buf, sizeof(outq_buf));
        if (got > 0 && outq_buf[0] == 'X') {
            printf("[outq] X received during backoff\n");
            g_disconnect_requested = 1;
        }
    }
}

/*-------------------------------------------------------------------*/
/* Run a single connection lifetime: DNS, TCP, register, poll loop.  */
/*                                                                   */
/* Returns:                                                          */
/*   0 - clean exit (g_disconnect_requested set, do not reconnect)   */
/*   1 - connection lost, reconnect requested                        */
/*   2 - fatal (e.g. DNS failure on first try)                       */
/*-------------------------------------------------------------------*/
static int run_session(const char *host, int port,
                       const char *nick, const char *real)
{
    struct sockaddr_in addr;
    int            sock;
    LineReader     lr;
    unsigned char  line[IRC_LINE_MAX];
    unsigned char  eline[IRC_LINE_MAX];
    char           buf[IRC_SEND_MAX];
    int            len;
    IrcMsg         msg;
    char           outq_buf[OUTQ_DATA_MAX];
    int            outq_len;
    fd_set         rfds;
    struct timeval tv;
    int            sel;
    char           sender_nick[64];
    char           frags[600];
    int            frags_len;
    char           sysline[600];
    int            sysline_len;
    int            line_count = 0;
    int            should_exit;
    char           line_color;

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(port);

    printf("[dns] resolving %s ...\n", host);
    if (resolve_with_timeout(host, &addr.sin_addr, DNS_TIMEOUT) != 0) {
        printf("[dns] FAILED\n");
        sysline_len = sprintf(sysline,
                              "*** DNS lookup failed for %s", host);
        msgbuf_append(0, 'S', "system", 'B', sysline, sysline_len);
        evtq_wakeup();
        return 1;
    }
    printf("[dns] %s -> %s\n", host, inet_ntoa(addr.sin_addr));

    printf("[tcp] connecting...\n");
    sock = connect_with_timeout(&addr, CONN_TIMEOUT);
    if (sock < 0) {
        printf("[tcp] connect failed (errno=%d)\n", errno);
        sysline_len = sprintf(sysline,
                              "*** TCP connect failed (errno=%d)",
                              errno);
        msgbuf_append(0, 'S', "system", 'B', sysline, sysline_len);
        evtq_wakeup();
        return 1;
    }
    printf("[tcp] connected\n");
    sysline_len = sprintf(sysline, "*** Connected to %s",
                          inet_ntoa(addr.sin_addr));
    msgbuf_append(0, 'S', "system", 'B', sysline, sysline_len);
    evtq_wakeup();

    /* Set socket non-blocking for the read loop.  next_line() relies */
    /* on recv() returning EAGAIN rather than stalling on a partial   */
    /* line while we still have IRCOUTQ work to drain.                */
    {
        int yes = 1;
        ioctl(sock, FIONBIO, &yes);
    }

    /* Registration */
    len = sprintf(buf, "NICK %s\r\n", nick);
    if (irc_send_line(sock, buf, len) < 0) {
        close(sock);
        return 1;
    }
    printf("[send] NICK %s\n", nick);

    len = sprintf(buf, "USER %s 0 * :%s\r\n", nick, real);
    if (irc_send_line(sock, buf, len) < 0) {
        close(sock);
        return 1;
    }
    printf("[send] USER %s 0 * :%s\n", nick, real);

    /*---------------------------------------------------------------*/
    /* Main poll loop                                                */
    /*---------------------------------------------------------------*/
    memset(&lr, 0, sizeof(lr));
    should_exit = 0;

    while (!g_disconnect_requested && !should_exit) {

        /* 1. Drain IRCOUTQ (non-blocking, may have multiple entries) */
        for (;;) {
            outq_len = outq_check(outq_buf, sizeof(outq_buf));
            if (outq_len <= 0) break;
            if (dispatch_outq(sock, outq_buf, outq_len)) {
                should_exit = 1;
                break;
            }
        }
        if (should_exit) break;

        /* 2. Wait briefly for socket activity (100 ms) */
        FD_ZERO(&rfds);
        FD_SET(sock, &rfds);
        tv.tv_sec  = 0;
        tv.tv_usec = POLL_INTERVAL_US;
        sel = select(sock + 1, &rfds, NULL, NULL, &tv);
        if (sel < 0) {
            if (errno == EINTR) continue;
            printf("[tcp] select errno=%d\n", errno);
            close(sock);
            return 1;
        }
        if (sel == 0) continue;   /* timeout, loop */

        /* 3. Drain whatever the socket has (may be many lines) */
        for (;;) {
            len = next_line(sock, &lr, line, sizeof(line));
            if (len < 0) {
                printf("[tcp] connection closed (after %d lines)\n",
                       line_count);
                close(sock);
                sysline_len = sprintf(sysline,
                    "*** Connection lost - will reconnect");
                msgbuf_append(0, 'S', "system", 'B',
                              sysline, sysline_len);
                evtq_wakeup();
                return 1;
            }
            if (len == 0) break;       /* no more complete lines */
            line_count++;

            if (len >= (int)sizeof(eline)) len = sizeof(eline) - 1;
            memcpy(eline, line, len);
            eline[len] = 0;
            translate_a2e(eline, len);
            printf("[recv] %s\n", (char *)eline);

            parse_irc((const char *)eline, &msg);

            if (strcmp(msg.command, "PING") == 0) {
                const char *arg = msg.has_trailing ? msg.trailing
                    : (msg.nparams > 0 ? msg.params[0] : "");
                len = sprintf(buf, "PONG :%s\r\n", arg);
                irc_send_line(sock, buf, len);
                printf("[send] PONG :%s\n", arg);
                /* PINGs are not interesting enough to log to MSGBUF */
            } else {
                prefix_to_nick(msg.prefix, sender_nick,
                               sizeof(sender_nick));
                line_color = '_';
                frags_len = compose_frags(&msg, frags, sizeof(frags),
                                          &line_color);
                msgbuf_append(0, kind_for(msg.command),
                              sender_nick, line_color,
                              frags, frags_len);
                evtq_wakeup();

                if (strcmp(msg.command, "ERROR") == 0) {
                    printf("[err] server ERROR; closing\n");
                    close(sock);
                    return 1;
                }
            }
        }
    }

    /* Clean shutdown */
    close(sock);
    return 0;
}

/*-------------------------------------------------------------------*/
/* Main: argument parsing, init, outer reconnect loop                */
/*-------------------------------------------------------------------*/
int main(int argc, char *argv[])
{
    char host[128];
    char port_s[16];
    char nick[64];
    char real[128];
    int  port;
    int  rc;
    int  backoff = BACKOFF_INITIAL;

    if (argc < 4) {
        printf("IRCNETD - IRC Network Engine (Phase 3)\n\n");
        printf("Usage:\n");
        printf("  CALL PGM(LIB/IRCNETD)\n");
        printf("    PARM(host port nick [realname])\n");
        return 1;
    }

    init_tables();

    memset(host,   0, sizeof(host));
    memset(port_s, 0, sizeof(port_s));
    memset(nick,   0, sizeof(nick));
    memset(real,   0, sizeof(real));

    strncpy(host,   argv[1], sizeof(host)   - 1);
    strncpy(port_s, argv[2], sizeof(port_s) - 1);
    strncpy(nick,   argv[3], sizeof(nick)   - 1);
    if (argc >= 5) strncpy(real, argv[4], sizeof(real) - 1);
    else            strcpy(real, "IRC400 client");

    trim_right(host);
    trim_right(port_s);
    trim_right(nick);
    trim_right(real);

    port = atoi(port_s);
    if (port <= 0 || port > 65535) port = DEFAULT_PORT;

    printf("=========================================\n");
    printf(" IRCNETD (Phase 3)\n");
    printf("=========================================\n");
    printf("  Host: %s:%d\n", host, port);
    printf("  Nick: %s\n", nick);
    printf("  Real: %s\n", real);
    printf("-----------------------------------------\n");

    load_max_seq();
    printf("[msgbuf] resuming at seq %ld\n", (long)g_next_seq);

    /*---------------------------------------------------------------*/
    /* Outer reconnect loop                                          */
    /*---------------------------------------------------------------*/
    while (!g_disconnect_requested) {
        rc = run_session(host, port, nick, real);

        if (rc == 0 || g_disconnect_requested) {
            printf("[main] clean exit requested\n");
            break;
        }
        if (rc == 2) {
            printf("[main] fatal error, exiting\n");
            break;
        }

        printf("[main] reconnect in %d seconds\n", backoff);
        interruptible_sleep(backoff);

        backoff *= 2;
        if (backoff > BACKOFF_MAX) backoff = BACKOFF_MAX;
    }

    printf("=========================================\n");
    printf(" IRCNETD ended.\n");
    printf("=========================================\n");
    return 0;
}
