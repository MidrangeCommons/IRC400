# QSN — IBM i Dynamic Screen Manager API reference

Working notes on the `Qsn*` (Workstation User / Dynamic Screen Manager, DSM) family — what it is, why we need it for Phase 5b of IRC400, and how to call it from ILE C on V4R5.

> ⚠️ This is a working document. The first draft was written from memory; the V4R5-specific section at the bottom (§10) is grounded in the **actual** `qsnapi.h` shipped on `192.168.1.101` (V4R5M0, copyright 1993–1994), pulled via `CPYTOSTMF` + FTP and inspected at `/tmp/qsnapi-ascii.h` on the dev host. Where the two sections disagree, §10 wins.

## 1. Naming and history

`Qsn` is the prefix for IBM's **Dynamic Screen Manager** APIs. The `Q` is the standard OS/400 system-service prefix; `Sn` is documented in different IBM sources as "Session" or "Screen" (the docs use both interchangeably). The shipped `*MODULE` / `*PGM` objects in `QSYS` are spelled in upper case (`QSNCRTCMD`, `QSNWRTDTA`, `QSNREADIN`, …); the C-language declarations are mixed case (`QsnCrtCmdBuf`, `QsnWrtDta`, `QsnReadInvited`, …).

DSM was added in OS/400 V2R3 to give 5250 application writers a path between two earlier extremes:

| Layer | What it gives you | What it costs |
|---|---|---|
| **DDS / DSPF + RPG/CL `SNDRCVF`** | Declarative screen layout, automatic field handling, IBM-managed I/O cycle. | All flush timing is glued to the AID round-trip — *you cannot update the screen except in response to user input*. |
| **5250 data stream directly** | Total control. | You write your own data-stream encoder (orders, SBA, RA, IC, MDT bits, etc.). Almost nobody does this. |
| **`Qsn*` DSM APIs** | A C-level abstraction over the data stream — buffers, fields, cursor, reads, AID handling — without losing the ability to flush on your schedule. | You manage handles and buffers yourself; you reimplement what DDS gave you for free; the prototypes are not friendly. |

The Phase 5 problem we hit (chat region won't repaint between AIDs in pure CL) is the canonical reason to drop down to DSM. There is no CL-level workaround on V4R5 — IBM's own newer "subfile auto-refresh" recipes from V5R3+ also bottom out in DSM.

## 2. Conceptual model

DSM exposes the workstation as three resources you create and manage by handle:

1. **Command buffer** — an in-memory accumulator for output orders (write-data, set-cursor, define-field, etc.). You build a buffer with multiple `QsnWrtXxx` calls, then transmit it.
2. **Input buffer** — an in-memory destination for input data returned by reads (modified field contents, AID code, cursor position).
3. **Standard I/O handle** ("Std I/O") — the open connection to the workstation device, used to issue puts/reads.

The typical lifecycle of a screen:

```
QsnOpenStdIO(...)    -> stdio_h
QsnCrtCmdBuf(...)    -> cmd_buf_h
QsnCrtInpBuf(...)    -> inp_buf_h

loop:
  QsnClrBuf(cmd_buf_h)
  QsnWrtDta / QsnWrtSF / QsnSetFld / ... into cmd_buf_h
  QsnPutBuf(stdio_h, cmd_buf_h)            <-- flushes to workstation NOW
  QsnReadInvited(stdio_h, inp_buf_h, ...)  <-- blocks (or polls a dtaq)
  inspect inp_buf_h: AID code, field data
endloop

QsnCloseStdIO(stdio_h)
```

The crucial difference from CL: `QsnPutBuf` is a *push* — it transmits whatever you've written into the command buffer right then, with no requirement that an invited read be pending or that a paired AID round-trip is in flight. That single primitive is the missing piece for live-refresh.

## 3. The functions you'll actually use

What follows are the families that matter for an IRC client. Names are correct; argument lists are summarised — always compare against `qsnapi.h` before coding.

### 3.1 Standard I/O lifecycle

```c
int QsnOpenStdIO(...);             /* returns Std I/O handle */
int QsnCloseStdIO(int handle, ...);
```

Opens a "standard" workstation I/O handle bound to the current job's display device. There are also `QsnOpenStream` and `QsnOpenSrcMbr` variants for off-device redirection (used by spool emulators). For an interactive panel like ours, `QsnOpenStdIO` is the right one.

### 3.2 Command buffer (output side)

```c
int QsnCrtCmdBuf(...);                      /* returns cmd_buf_h */
int QsnDltBuf(int buf_h, ...);
int QsnClrBuf(int buf_h, ...);              /* reset for next iteration */

int QsnWrtDta(buf_h, data, len, ...);       /* raw data + implicit SBA */
int QsnSetCsrAdr(buf_h, row, col, ...);     /* explicit cursor position */
int QsnSetFld(buf_h, row, col, len, attr, ...);  /* declare an input field */
int QsnWrtSF(buf_h, ...);                   /* write structured field */
int QsnPutBuf(stdio_h, buf_h, ...);         /* TRANSMIT the buffer */
```

`QsnPutBuf` is what makes the chat region actually update on a 1-byte engine wake. It composes the command buffer into a 5250 write data stream and sends it. The workstation paints the new fields immediately. No AID required.

There is also `QsnWrtTDS` (Write Transmit Data Stream) which is essentially `QsnPutBuf` for an externally-built data stream. **(uncertain — some IBM docs treat `QsnPutBuf` and `QsnWrtTDS` as synonyms, others as cousins; in practice for our use case `QsnPutBuf` is the right name to look up first.)**

### 3.3 Input buffer (input side)

```c
int QsnCrtInpBuf(...);                  /* inp_buf_h */
int QsnReadInvited(stdio_h, inp_buf_h,
                   timer, dtaq_name, dtaq_lib, ...);
int QsnReadMDT(stdio_h, inp_buf_h, ...);
int QsnReadKey(stdio_h, inp_buf_h, ...);

int QsnRtvAID(inp_buf_h, &aid_byte);
int QsnRtvFldDta(inp_buf_h, field_id, &data, &len);
int QsnRtvCsrAdr(inp_buf_h, &row, &col);
```

The interesting one is **`QsnReadInvited`** with the data-queue parameters. Behaviour:

- The function posts an invited read on the workstation.
- It returns either when the workstation reports an AID, **or** when something is enqueued on the named data queue, **or** when the optional timer expires.
- In all cases the program decides what to do next — it is not stuck waiting for a synchronous AID round trip.

This is the primitive that pure CL cannot offer. `SNDRCVF` posts a synchronous read; `WAIT` *can* take a queue but, as we saw, the message-class behaviour around timeouts isn't usable from CL on V4R5.

### 3.4 Data conversion helpers

ILE C strings are EBCDIC; the 5250 wire is also EBCDIC, so for plain text fields you don't need conversion. For literal screen attribute bytes (`0x20`–`0x3F` field-attribute range, `0x1D` SF order, `0x11` SBA, `0x13` IC, etc.) DSM has helpers like:

```c
int QsnSetAtr(buf_h, attribute_byte, ...);   /* DSPATR equivalents */
int QsnSetCol(buf_h, color_byte, ...);       /* COLOR(...) equivalents */
```

Useful when we get to Phase 6b (per-slot color overlay) and want to skip the indicator-driven DDS approach altogether — define each chat-line slot as a DSM field with its color attribute, then mutate the attribute per refresh.

## 4. Compile-time wiring

In ILE C source:

```c
#include <qsnapi.h>
```

The header lives at `/QIBM/include/qsnapi.h` on the IFS, and inside QSYSINC source PFs (`QSYSINC/H/QSNAPI` member) — both are populated by Option 13 of 5722-SS1 (System Openness Includes), which we already require for sockets.

For `CRTBNDC` / `CRTPGM`, the QSN service program is in the **standard** ILE C runtime binding directory **`QSYS/QC2LE`** — i.e., it's auto-resolved without any extra `BNDDIR()` parameter. **(uncertain on V4R5)**: some references explicitly add `BNDSRVPGM(QSYS/QC2LE)` or `BNDDIR(QC2LE)`. If the linker complains about unresolved `Qsn*` symbols, add:

```
CRTPGM PGM(IRCCLIENT/IRCNETD)
       MODULE(IRCCLIENT/IRCNETD IRCCLIENT/IRCFMT)
       ENTMOD(IRCCLIENT/IRCNETD)
       BNDDIR(QC2LE)
```

Or, for the chat-panel module specifically (which is the one that needs DSM):

```
BNDSRVPGM(QSYS/QC2LE) ACTGRP(*CALLER)
```

## 5. Error handling

Every `Qsn*` call returns an integer; non-zero is an error. The detailed message is left on the program's message queue and can be retrieved with `QMHRCVPM` (Receive Program Message). For Phase 5b we'll typically just log via `printf` to spool and bail to the simpler refresh-on-AID path on any DSM error — the program degrades to Phase 5a behaviour rather than crashing.

There is also an Error Code parameter convention used by most newer IBM APIs (a structure with reserved bytes + message ID + replacement data). DSM predates the common pattern in places, so signatures vary; check the header.

## 6. How Phase 5b will use this

Sketch of `qsn_read.c` — the wrapper that replaces the `SNDF` / `QRCVDTAQ` / `RCVF` triplet in `IRCCHATC`:

```c
/* PARM 1: window seq         CHAR(4)   in        */
/* PARM 2: line-array buffer  CHAR(1444) in/out   - 19 chat lines */
/* PARM 3: input buffer       CHAR(76)  out       - the user's typed line */
/* PARM 4: aid byte           CHAR(1)   out       - F3, F5, F12, Enter, … */
/* PARM 5: result code        CHAR(4)   out       */

int main(int argc, char *argv[]) {
    static int initialised = 0;
    static int stdio_h, cmd_buf_h, inp_buf_h;

    if (!initialised) {
        QsnOpenStdIO(...);
        QsnCrtCmdBuf(...);
        QsnCrtInpBuf(...);
        initialised = 1;
    }

    /* 1. Build chat region into the command buffer from PARM 2 */
    QsnClrBuf(cmd_buf_h, ...);
    for (row = 4; row <= 22; row++) {
        QsnSetCsrAdr(cmd_buf_h, row, 2, ...);
        QsnWrtDta(cmd_buf_h,
                  &chat_lines[(row - 4) * 76], 76, ...);
    }
    /* (header, separator, F-key legend already painted on prior calls; */
    /*  we only repaint the volatile region.)                            */

    /* 2. Flush to workstation NOW. */
    QsnPutBuf(stdio_h, cmd_buf_h, ...);

    /* 3. Issue a read with both a timer AND IRCEVTQ tied. */
    QsnReadInvited(stdio_h, inp_buf_h,
                   2 /* sec */,
                   "IRCEVTQ   ", "IRCCLIENT ",
                   ...);

    /* 4. Decode what woke us. */
    QsnRtvAID(inp_buf_h, &aid);
    if (aid == 0) {
        /* Timer or DTAQ wake — caller will reload chat_lines and recall us. */
        argv[4][0] = '_';            /* "no AID, just refresh" */
        return 0;
    }

    /* AID press — extract the input field and AID code into PARMs 3 & 4. */
    QsnRtvFldDta(inp_buf_h, INPUT_FIELD_ID, argv[2], &len);
    argv[3][0] = aid;                /* 0xF3 / 0xF4 / 0x7D etc. */
    return 0;
}
```

`IRCCHATC` then becomes:

```cl
LOOP:
    /* refresh chat_lines from MSGBUF as before */
    CALL IRCCHATL ...

    CALL QSN_READ PARM(&PWIN &CHATBUF &INPUT &AID &RC)

    IF (&AID *EQ '_') GOTO LOOP                 /* timer or wake */
    IF (&AID = X'F3') GOTO END                  /* F3 */
    ...
    /* dispatch &INPUT exactly as before */
```

The wrapper hides the DSM complexity; CL stays simple.

## 7. Pitfalls observed and predicted

- **Buffer reuse across invocations.** The handles must persist across calls, otherwise every iteration tears down and rebuilds the open. A `static int initialised` (as above) is the standard pattern; alternatively, `IRCCHATC` can hold the handles and pass them in.
- **Activation group**. Qsn handles are scoped to the activation group. If `IRCCHATC` runs in `*NEW` (default) and `qsn_read` in `*CALLER`, every CALL builds a new AG and the static handles are useless. Pin both to the same activation group with `ACTGRP(IRCCHATC)` on `CRTPGM`.
- **Input-field IDs**. `QsnSetFld` returns a numeric field ID; that number is what you pass to `QsnRtvFldDta` to read it back. Save it once at startup; re-use forever.
- **Cursor management**. After a refresh the cursor will jump to wherever DSM thinks it should go (often the home position). Save it with `QsnRtvCsrAdr` before flushing and restore with `QsnSetCsrAdr` on the cmd buffer to avoid "the cursor keeps stealing focus from row 24" UX bug.
- **Workstation state ownership**. Once a program opens a Std I/O handle on the device, mixing it with DCLF + SNDF/RCVF on the same DSPF is asking for trouble. Either DSM owns the screen for the chat panel's lifetime, or DDS does — not both.
- **AID byte encoding**. The AID byte returned by `QsnRtvAID` is the workstation's binary code (e.g. F3 = `0xF3`, Enter = `0x7D`, F12 = `0xF4`, Help = `0xF1`). Do **not** confuse with the DDS CA-keyword indicator numbers (03, 12, 01) — those are DDS's accounting; DSM gives you the raw protocol byte.

## 8. Cross-references

- **Plan §11.1** — predicted that pure-CL invited-read with WAITRCD on V4R5 wouldn't fly and that this fallback would be required. Confirmed.
- **Phase 5a** (already shipped) — laid the data-queue scaffolding (`IRCEVTQ` MAXLEN(80), `OVRDSPF DTAQ`, two-format DSPF). Phase 5b's `QsnReadInvited` reuses the same `IRCEVTQ` parameter without changes.
- **Phase 6b** — the DSM `QsnSetAtr` / `QsnSetCol` path is an attractive alternative to the indicator-driven DDS overlay, since the colour can be set per-slot per-refresh purely from C. Worth re-evaluating before committing 1200+ lines of generated DDS.
- `feedback_v4r5_invite.md` (memory) — running notes on what didn't work in CL and why DSM is needed.

## 9. Reading list (when implementing)

When the time comes for Phase 5b, the canonical references in order of usefulness:

1. **The IBM-supplied header** at `/QIBM/include/qsnapi.h` (or `QSYSINC/H/QSNAPI` member). This is ground truth for prototypes on the actual box.
2. **IBM i Information Center → Programming → APIs → Workstation User APIs** (Dynamic Screen Manager). The on-line docs include a worked "menu program" example that maps cleanly to a chat panel.
3. **Scott Klement's articles** on DSM (search `klement.com qsn`). Free, practical, and call out the pitfalls IBM's docs gloss over.
4. **`midrange.com` archives** — the comp.sys.ibm.as400.misc threads from 1998–2005 are gold for V4Rx-specific quirks.

Skip the RPG-flavoured DSM tutorials (they exist) — DSM was always intended for C; the RPG bindings exist but cost more than they save.
