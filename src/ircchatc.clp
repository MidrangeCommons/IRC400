             /*-----------------------------------------------*/
             /* IRCCHATC - Chat Panel Controller (Phase 7)    */
             /*                                               */
             /* Phase 7 adds half-screen input mode:          */
             /*   F11 toggles between CHATIN (1-line) and     */
             /*   CHATBIG (9 stacked input lines, rows 14-22) */
             /*                                               */
             /* In big mode the CHATBUF/KINDBUF are rotated   */
             /* so the newest 9 lines occupy ledger slots 1-9 */
             /* (display rows 4-12). Slots 10-19 are hidden   */
             /* by CHATBIG's overlay so we don't care about   */
             /* them. ENTER in big mode concatenates BIG01..  */
             /* BIG09 (trimmed via *BCAT) and dispatches a    */
             /* single PRIVMSG to the current channel, then   */
             /* clears the BIG fields and returns to small.   */
             /*-----------------------------------------------*/
             PGM        PARM(&PWIN &PCHAN &PNICK)

             DCLF       FILE(IRCCLIENT/IRCCHATD)

             DCL        VAR(&PWIN)   TYPE(*CHAR) LEN(4)
             DCL        VAR(&PCHAN)  TYPE(*CHAR) LEN(64)
             DCL        VAR(&PNICK)  TYPE(*CHAR) LEN(32)

             DCL        VAR(&CHATBUF) TYPE(*CHAR) LEN(1444)
             DCL        VAR(&KINDBUF) TYPE(*CHAR) LEN(57)
             DCL        VAR(&MAXSEQ)  TYPE(*CHAR) LEN(9)
             DCL        VAR(&SYSNAME) TYPE(*CHAR) LEN(8)

             DCL        VAR(&MODE)   TYPE(*CHAR) LEN(1) VALUE('S')

             DCL        VAR(&CMD)    TYPE(*CHAR) LEN(800)
             DCL        VAR(&CMDLEN) TYPE(*DEC)  LEN(5 0)
             DCL        VAR(&OQNAME) TYPE(*CHAR) LEN(10) +
                                       VALUE('IRCOUTQ')
             DCL        VAR(&OQLIB)  TYPE(*CHAR) LEN(10) +
                                       VALUE('IRCCLIENT')

             DCL        VAR(&EQNAME) TYPE(*CHAR) LEN(10) +
                                       VALUE('IRCEVTQ')
             DCL        VAR(&EQLIB)  TYPE(*CHAR) LEN(10) +
                                       VALUE('IRCCLIENT')
             DCL        VAR(&EQDATA) TYPE(*CHAR) LEN(80)
             DCL        VAR(&EQLEN)  TYPE(*DEC)  LEN(5 0)
             DCL        VAR(&EQWAIT) TYPE(*DEC)  LEN(5 0) VALUE(2)

             DCL        VAR(&INLEN)  TYPE(*DEC)  LEN(3 0)
             DCL        VAR(&CHLEN)  TYPE(*DEC)  LEN(3 0)
             DCL        VAR(&PAYLEN) TYPE(*DEC)  LEN(3 0)

             DCL        VAR(&BODY)    TYPE(*CHAR) LEN(700)
             DCL        VAR(&BODYLEN) TYPE(*DEC)  LEN(5 0)
             DCL        VAR(&BODYSTR) TYPE(*DEC)  LEN(5 0)
             DCL        VAR(&BODYEFF) TYPE(*DEC)  LEN(5 0)

             DCL        VAR(&FIRST5) TYPE(*CHAR) LEN(5)
             DCL        VAR(&FIRST6) TYPE(*CHAR) LEN(6)
             DCL        VAR(&FIRST7) TYPE(*CHAR) LEN(7)

             OVRDSPF    FILE(IRCCHATD) DTAQ(IRCCLIENT/IRCEVTQ)
             MONMSG     MSGID(CPF0000)

             RTVNETA    SYSNAME(&SYSNAME)
             CHGVAR     VAR(&S1SYS) VALUE(&SYSNAME)
             CHGVAR     VAR(&S1WIN) VALUE(&PCHAN)
             CHGVAR     VAR(&S1NCK) VALUE(&PNICK)
             CHGVAR     VAR(&B1SYS) VALUE(&SYSNAME)
             CHGVAR     VAR(&B1WIN) VALUE(&PCHAN)
             CHGVAR     VAR(&B1NCK) VALUE(&PNICK)
             CHGVAR     VAR(&STSMSG) VALUE(' ')
             CHGVAR     VAR(&INPUT) VALUE(' ')

 PAINT:
             CALL       PGM(IRCCLIENT/IRCCHATL) +
                          PARM(&PWIN &CHATBUF &KINDBUF &MAXSEQ)

             /* Big mode: rotate buffer so newest 9 land in    */
             /* slots 1-9 (display rows 4-12). Slots 10-19 are */
             /* hidden by CHATBIG's overlay.                   */
             IF         COND(&MODE *EQ 'B') THEN(DO)
               CHGVAR     VAR(&CHATBUF) VALUE(%SST(&CHATBUF 761 684) +
                            *CAT %SST(&CHATBUF 1 760))
               CHGVAR     VAR(&KINDBUF) VALUE(%SST(&KINDBUF 31 27) +
                            *CAT %SST(&KINDBUF 1 30))
             ENDDO

             CHGVAR     VAR(&TS01) VALUE(%SST(&CHATBUF    1  8))
             CHGVAR     VAR(&NK01) VALUE(%SST(&CHATBUF    9 16))
             CHGVAR     VAR(&MS01) VALUE(%SST(&CHATBUF   25 52))
             CHGVAR     VAR(&IN11) VALUE(%SST(&KINDBUF  1 1) *EQ '1')
             CHGVAR     VAR(&IN12) VALUE(%SST(&KINDBUF  2 1) *EQ '1')
             CHGVAR     VAR(&IN13) VALUE(%SST(&KINDBUF  3 1) *EQ '1')
             CHGVAR     VAR(&TS02) VALUE(%SST(&CHATBUF   77  8))
             CHGVAR     VAR(&NK02) VALUE(%SST(&CHATBUF   85 16))
             CHGVAR     VAR(&MS02) VALUE(%SST(&CHATBUF  101 52))
             CHGVAR     VAR(&IN14) VALUE(%SST(&KINDBUF  4 1) *EQ '1')
             CHGVAR     VAR(&IN15) VALUE(%SST(&KINDBUF  5 1) *EQ '1')
             CHGVAR     VAR(&IN16) VALUE(%SST(&KINDBUF  6 1) *EQ '1')
             CHGVAR     VAR(&TS03) VALUE(%SST(&CHATBUF  153  8))
             CHGVAR     VAR(&NK03) VALUE(%SST(&CHATBUF  161 16))
             CHGVAR     VAR(&MS03) VALUE(%SST(&CHATBUF  177 52))
             CHGVAR     VAR(&IN17) VALUE(%SST(&KINDBUF  7 1) *EQ '1')
             CHGVAR     VAR(&IN18) VALUE(%SST(&KINDBUF  8 1) *EQ '1')
             CHGVAR     VAR(&IN19) VALUE(%SST(&KINDBUF  9 1) *EQ '1')
             CHGVAR     VAR(&TS04) VALUE(%SST(&CHATBUF  229  8))
             CHGVAR     VAR(&NK04) VALUE(%SST(&CHATBUF  237 16))
             CHGVAR     VAR(&MS04) VALUE(%SST(&CHATBUF  253 52))
             CHGVAR     VAR(&IN20) VALUE(%SST(&KINDBUF 10 1) *EQ '1')
             CHGVAR     VAR(&IN21) VALUE(%SST(&KINDBUF 11 1) *EQ '1')
             CHGVAR     VAR(&IN22) VALUE(%SST(&KINDBUF 12 1) *EQ '1')
             CHGVAR     VAR(&TS05) VALUE(%SST(&CHATBUF  305  8))
             CHGVAR     VAR(&NK05) VALUE(%SST(&CHATBUF  313 16))
             CHGVAR     VAR(&MS05) VALUE(%SST(&CHATBUF  329 52))
             CHGVAR     VAR(&IN23) VALUE(%SST(&KINDBUF 13 1) *EQ '1')
             CHGVAR     VAR(&IN24) VALUE(%SST(&KINDBUF 14 1) *EQ '1')
             CHGVAR     VAR(&IN25) VALUE(%SST(&KINDBUF 15 1) *EQ '1')
             CHGVAR     VAR(&TS06) VALUE(%SST(&CHATBUF  381  8))
             CHGVAR     VAR(&NK06) VALUE(%SST(&CHATBUF  389 16))
             CHGVAR     VAR(&MS06) VALUE(%SST(&CHATBUF  405 52))
             CHGVAR     VAR(&IN26) VALUE(%SST(&KINDBUF 16 1) *EQ '1')
             CHGVAR     VAR(&IN27) VALUE(%SST(&KINDBUF 17 1) *EQ '1')
             CHGVAR     VAR(&IN28) VALUE(%SST(&KINDBUF 18 1) *EQ '1')
             CHGVAR     VAR(&TS07) VALUE(%SST(&CHATBUF  457  8))
             CHGVAR     VAR(&NK07) VALUE(%SST(&CHATBUF  465 16))
             CHGVAR     VAR(&MS07) VALUE(%SST(&CHATBUF  481 52))
             CHGVAR     VAR(&IN29) VALUE(%SST(&KINDBUF 19 1) *EQ '1')
             CHGVAR     VAR(&IN30) VALUE(%SST(&KINDBUF 20 1) *EQ '1')
             CHGVAR     VAR(&IN31) VALUE(%SST(&KINDBUF 21 1) *EQ '1')
             CHGVAR     VAR(&TS08) VALUE(%SST(&CHATBUF  533  8))
             CHGVAR     VAR(&NK08) VALUE(%SST(&CHATBUF  541 16))
             CHGVAR     VAR(&MS08) VALUE(%SST(&CHATBUF  557 52))
             CHGVAR     VAR(&IN32) VALUE(%SST(&KINDBUF 22 1) *EQ '1')
             CHGVAR     VAR(&IN33) VALUE(%SST(&KINDBUF 23 1) *EQ '1')
             CHGVAR     VAR(&IN34) VALUE(%SST(&KINDBUF 24 1) *EQ '1')
             CHGVAR     VAR(&TS09) VALUE(%SST(&CHATBUF  609  8))
             CHGVAR     VAR(&NK09) VALUE(%SST(&CHATBUF  617 16))
             CHGVAR     VAR(&MS09) VALUE(%SST(&CHATBUF  633 52))
             CHGVAR     VAR(&IN35) VALUE(%SST(&KINDBUF 25 1) *EQ '1')
             CHGVAR     VAR(&IN36) VALUE(%SST(&KINDBUF 26 1) *EQ '1')
             CHGVAR     VAR(&IN37) VALUE(%SST(&KINDBUF 27 1) *EQ '1')
             CHGVAR     VAR(&TS10) VALUE(%SST(&CHATBUF  685  8))
             CHGVAR     VAR(&NK10) VALUE(%SST(&CHATBUF  693 16))
             CHGVAR     VAR(&MS10) VALUE(%SST(&CHATBUF  709 52))
             CHGVAR     VAR(&IN38) VALUE(%SST(&KINDBUF 28 1) *EQ '1')
             CHGVAR     VAR(&IN39) VALUE(%SST(&KINDBUF 29 1) *EQ '1')
             CHGVAR     VAR(&IN40) VALUE(%SST(&KINDBUF 30 1) *EQ '1')
             CHGVAR     VAR(&TS11) VALUE(%SST(&CHATBUF  761  8))
             CHGVAR     VAR(&NK11) VALUE(%SST(&CHATBUF  769 16))
             CHGVAR     VAR(&MS11) VALUE(%SST(&CHATBUF  785 52))
             CHGVAR     VAR(&IN41) VALUE(%SST(&KINDBUF 31 1) *EQ '1')
             CHGVAR     VAR(&IN42) VALUE(%SST(&KINDBUF 32 1) *EQ '1')
             CHGVAR     VAR(&IN43) VALUE(%SST(&KINDBUF 33 1) *EQ '1')
             CHGVAR     VAR(&TS12) VALUE(%SST(&CHATBUF  837  8))
             CHGVAR     VAR(&NK12) VALUE(%SST(&CHATBUF  845 16))
             CHGVAR     VAR(&MS12) VALUE(%SST(&CHATBUF  861 52))
             CHGVAR     VAR(&IN44) VALUE(%SST(&KINDBUF 34 1) *EQ '1')
             CHGVAR     VAR(&IN45) VALUE(%SST(&KINDBUF 35 1) *EQ '1')
             CHGVAR     VAR(&IN46) VALUE(%SST(&KINDBUF 36 1) *EQ '1')
             CHGVAR     VAR(&TS13) VALUE(%SST(&CHATBUF  913  8))
             CHGVAR     VAR(&NK13) VALUE(%SST(&CHATBUF  921 16))
             CHGVAR     VAR(&MS13) VALUE(%SST(&CHATBUF  937 52))
             CHGVAR     VAR(&IN47) VALUE(%SST(&KINDBUF 37 1) *EQ '1')
             CHGVAR     VAR(&IN48) VALUE(%SST(&KINDBUF 38 1) *EQ '1')
             CHGVAR     VAR(&IN49) VALUE(%SST(&KINDBUF 39 1) *EQ '1')
             CHGVAR     VAR(&TS14) VALUE(%SST(&CHATBUF  989  8))
             CHGVAR     VAR(&NK14) VALUE(%SST(&CHATBUF  997 16))
             CHGVAR     VAR(&MS14) VALUE(%SST(&CHATBUF 1013 52))
             CHGVAR     VAR(&IN50) VALUE(%SST(&KINDBUF 40 1) *EQ '1')
             CHGVAR     VAR(&IN51) VALUE(%SST(&KINDBUF 41 1) *EQ '1')
             CHGVAR     VAR(&IN52) VALUE(%SST(&KINDBUF 42 1) *EQ '1')
             CHGVAR     VAR(&TS15) VALUE(%SST(&CHATBUF 1065  8))
             CHGVAR     VAR(&NK15) VALUE(%SST(&CHATBUF 1073 16))
             CHGVAR     VAR(&MS15) VALUE(%SST(&CHATBUF 1089 52))
             CHGVAR     VAR(&IN53) VALUE(%SST(&KINDBUF 43 1) *EQ '1')
             CHGVAR     VAR(&IN54) VALUE(%SST(&KINDBUF 44 1) *EQ '1')
             CHGVAR     VAR(&IN55) VALUE(%SST(&KINDBUF 45 1) *EQ '1')
             CHGVAR     VAR(&TS16) VALUE(%SST(&CHATBUF 1141  8))
             CHGVAR     VAR(&NK16) VALUE(%SST(&CHATBUF 1149 16))
             CHGVAR     VAR(&MS16) VALUE(%SST(&CHATBUF 1165 52))
             CHGVAR     VAR(&IN56) VALUE(%SST(&KINDBUF 46 1) *EQ '1')
             CHGVAR     VAR(&IN57) VALUE(%SST(&KINDBUF 47 1) *EQ '1')
             CHGVAR     VAR(&IN58) VALUE(%SST(&KINDBUF 48 1) *EQ '1')
             CHGVAR     VAR(&TS17) VALUE(%SST(&CHATBUF 1217  8))
             CHGVAR     VAR(&NK17) VALUE(%SST(&CHATBUF 1225 16))
             CHGVAR     VAR(&MS17) VALUE(%SST(&CHATBUF 1241 52))
             CHGVAR     VAR(&IN59) VALUE(%SST(&KINDBUF 49 1) *EQ '1')
             CHGVAR     VAR(&IN60) VALUE(%SST(&KINDBUF 50 1) *EQ '1')
             CHGVAR     VAR(&IN61) VALUE(%SST(&KINDBUF 51 1) *EQ '1')
             CHGVAR     VAR(&TS18) VALUE(%SST(&CHATBUF 1293  8))
             CHGVAR     VAR(&NK18) VALUE(%SST(&CHATBUF 1301 16))
             CHGVAR     VAR(&MS18) VALUE(%SST(&CHATBUF 1317 52))
             CHGVAR     VAR(&IN62) VALUE(%SST(&KINDBUF 52 1) *EQ '1')
             CHGVAR     VAR(&IN63) VALUE(%SST(&KINDBUF 53 1) *EQ '1')
             CHGVAR     VAR(&IN64) VALUE(%SST(&KINDBUF 54 1) *EQ '1')
             CHGVAR     VAR(&TS19) VALUE(%SST(&CHATBUF 1369  8))
             CHGVAR     VAR(&NK19) VALUE(%SST(&CHATBUF 1377 16))
             CHGVAR     VAR(&MS19) VALUE(%SST(&CHATBUF 1393 52))
             CHGVAR     VAR(&IN65) VALUE(%SST(&KINDBUF 55 1) *EQ '1')
             CHGVAR     VAR(&IN66) VALUE(%SST(&KINDBUF 56 1) *EQ '1')
             CHGVAR     VAR(&IN67) VALUE(%SST(&KINDBUF 57 1) *EQ '1')

             /* Split-view chat lines for big mode (rows 4-12).    */
             /* When MODE=B, CHATBUF/KINDBUF have already been     */
             /* rotated so lines 1-9 are the newest 9. Indicators  */
             /* 70-96 carry the per-row color bits to CHATBIG.     */
             CHGVAR     VAR(&TST01) VALUE(%SST(&CHATBUF    1  8))
             CHGVAR     VAR(&NKT01) VALUE(%SST(&CHATBUF    9 16))
             CHGVAR     VAR(&MST01) VALUE(%SST(&CHATBUF   25 52))
             CHGVAR     VAR(&IN70) VALUE(%SST(&KINDBUF  1 1) *EQ '1')
             CHGVAR     VAR(&IN71) VALUE(%SST(&KINDBUF  2 1) *EQ '1')
             CHGVAR     VAR(&IN72) VALUE(%SST(&KINDBUF  3 1) *EQ '1')
             CHGVAR     VAR(&TST02) VALUE(%SST(&CHATBUF   77  8))
             CHGVAR     VAR(&NKT02) VALUE(%SST(&CHATBUF   85 16))
             CHGVAR     VAR(&MST02) VALUE(%SST(&CHATBUF  101 52))
             CHGVAR     VAR(&IN73) VALUE(%SST(&KINDBUF  4 1) *EQ '1')
             CHGVAR     VAR(&IN74) VALUE(%SST(&KINDBUF  5 1) *EQ '1')
             CHGVAR     VAR(&IN75) VALUE(%SST(&KINDBUF  6 1) *EQ '1')
             CHGVAR     VAR(&TST03) VALUE(%SST(&CHATBUF  153  8))
             CHGVAR     VAR(&NKT03) VALUE(%SST(&CHATBUF  161 16))
             CHGVAR     VAR(&MST03) VALUE(%SST(&CHATBUF  177 52))
             CHGVAR     VAR(&IN76) VALUE(%SST(&KINDBUF  7 1) *EQ '1')
             CHGVAR     VAR(&IN77) VALUE(%SST(&KINDBUF  8 1) *EQ '1')
             CHGVAR     VAR(&IN78) VALUE(%SST(&KINDBUF  9 1) *EQ '1')
             CHGVAR     VAR(&TST04) VALUE(%SST(&CHATBUF  229  8))
             CHGVAR     VAR(&NKT04) VALUE(%SST(&CHATBUF  237 16))
             CHGVAR     VAR(&MST04) VALUE(%SST(&CHATBUF  253 52))
             CHGVAR     VAR(&IN79) VALUE(%SST(&KINDBUF 10 1) *EQ '1')
             CHGVAR     VAR(&IN80) VALUE(%SST(&KINDBUF 11 1) *EQ '1')
             CHGVAR     VAR(&IN81) VALUE(%SST(&KINDBUF 12 1) *EQ '1')
             CHGVAR     VAR(&TST05) VALUE(%SST(&CHATBUF  305  8))
             CHGVAR     VAR(&NKT05) VALUE(%SST(&CHATBUF  313 16))
             CHGVAR     VAR(&MST05) VALUE(%SST(&CHATBUF  329 52))
             CHGVAR     VAR(&IN82) VALUE(%SST(&KINDBUF 13 1) *EQ '1')
             CHGVAR     VAR(&IN83) VALUE(%SST(&KINDBUF 14 1) *EQ '1')
             CHGVAR     VAR(&IN84) VALUE(%SST(&KINDBUF 15 1) *EQ '1')
             CHGVAR     VAR(&TST06) VALUE(%SST(&CHATBUF  381  8))
             CHGVAR     VAR(&NKT06) VALUE(%SST(&CHATBUF  389 16))
             CHGVAR     VAR(&MST06) VALUE(%SST(&CHATBUF  405 52))
             CHGVAR     VAR(&IN85) VALUE(%SST(&KINDBUF 16 1) *EQ '1')
             CHGVAR     VAR(&IN86) VALUE(%SST(&KINDBUF 17 1) *EQ '1')
             CHGVAR     VAR(&IN87) VALUE(%SST(&KINDBUF 18 1) *EQ '1')
             CHGVAR     VAR(&TST07) VALUE(%SST(&CHATBUF  457  8))
             CHGVAR     VAR(&NKT07) VALUE(%SST(&CHATBUF  465 16))
             CHGVAR     VAR(&MST07) VALUE(%SST(&CHATBUF  481 52))
             CHGVAR     VAR(&IN88) VALUE(%SST(&KINDBUF 19 1) *EQ '1')
             CHGVAR     VAR(&IN89) VALUE(%SST(&KINDBUF 20 1) *EQ '1')
             CHGVAR     VAR(&IN90) VALUE(%SST(&KINDBUF 21 1) *EQ '1')
             CHGVAR     VAR(&TST08) VALUE(%SST(&CHATBUF  533  8))
             CHGVAR     VAR(&NKT08) VALUE(%SST(&CHATBUF  541 16))
             CHGVAR     VAR(&MST08) VALUE(%SST(&CHATBUF  557 52))
             CHGVAR     VAR(&IN91) VALUE(%SST(&KINDBUF 22 1) *EQ '1')
             CHGVAR     VAR(&IN92) VALUE(%SST(&KINDBUF 23 1) *EQ '1')
             CHGVAR     VAR(&IN93) VALUE(%SST(&KINDBUF 24 1) *EQ '1')
             CHGVAR     VAR(&TST09) VALUE(%SST(&CHATBUF  609  8))
             CHGVAR     VAR(&NKT09) VALUE(%SST(&CHATBUF  617 16))
             CHGVAR     VAR(&MST09) VALUE(%SST(&CHATBUF  633 52))
             CHGVAR     VAR(&IN94) VALUE(%SST(&KINDBUF 25 1) *EQ '1')
             CHGVAR     VAR(&IN95) VALUE(%SST(&KINDBUF 26 1) *EQ '1')
             CHGVAR     VAR(&IN96) VALUE(%SST(&KINDBUF 27 1) *EQ '1')

             /* Big mode: skip SNDF CHATOUT to avoid the           */
             /* CHATOUT-vs-CHATBIG overlap conflict at rows 14-22. */
             /* Rely on whatever CHATOUT was on screen before F11  */
             /* to remain visible in rows 4-12 above CHATBIG.      */
             IF         COND(&MODE *EQ 'B') THEN(DO)
               SNDF       RCDFMT(CHATBIG)
               MONMSG     MSGID(CPF0000)
               GOTO       CMDLBL(WAIT)
             ENDDO

             SNDF       RCDFMT(CHATOUT)
             MONMSG     MSGID(CPF0000)
             CHGVAR     VAR(&INPUT) VALUE(' ')
             SNDF       RCDFMT(CHATIN)
             MONMSG     MSGID(CPF0000)

 WAIT:
             CHGVAR     VAR(&EQLEN) VALUE(80)
             CHGVAR     VAR(&EQWAIT) VALUE(2)
             CALL       PGM(QRCVDTAQ) +
                          PARM(&EQNAME &EQLIB &EQLEN &EQDATA +
                               &EQWAIT)

             IF         COND(&EQLEN *EQ 0) THEN(GOTO CMDLBL(REPAINT))
             /* Engine wake is 1 byte 'X' from ircnetd. */
             /* If wake, just refresh and bail.         */
             IF         COND((&EQLEN *EQ 1) *AND +
                          (%SST(&EQDATA 1 1) *EQ 'X')) +
                          THEN(GOTO CMDLBL(REPAINT))

             IF         COND(&MODE *EQ 'B') THEN(DO)
               RCVF       RCDFMT(CHATBIG)
               GOTO       CMDLBL(POSTRCV)
             ENDDO
             RCVF       RCDFMT(CHATIN)
 POSTRCV:

             IF         COND(&IN03 *EQ '1') THEN(GOTO CMDLBL(END))
             IF         COND(&IN12 *EQ '1') THEN(GOTO CMDLBL(END))
             IF         COND(&IN05 *EQ '1') THEN(GOTO CMDLBL(PAINT))

             IF         COND((&IN68 *EQ '1') *AND +
                          (&MODE *EQ 'S')) THEN(DO)
               CHGVAR     VAR(&MODE) VALUE('B')
               GOTO       CMDLBL(PAINT)
             ENDDO
             IF         COND((&IN68 *EQ '1') *AND +
                          (&MODE *EQ 'B')) THEN(DO)
               CHGVAR     VAR(&MODE) VALUE('S')
               GOTO       CMDLBL(PAINT)
             ENDDO

             IF         COND(&MODE *EQ 'B') THEN(GOTO +
                          CMDLBL(BIGSEND))

             /*--------------------------------------------------*/
             /* Small mode: existing single-line dispatch.       */
             /*--------------------------------------------------*/

             CHGVAR     VAR(&INLEN) VALUE(76)
 TRIN:       IF         COND(&INLEN *EQ 0) THEN(GOTO CMDLBL(TRIN1))
             IF         COND(%SST(&INPUT &INLEN 1) *NE ' ') +
                          THEN(GOTO CMDLBL(TRIN1))
             CHGVAR     VAR(&INLEN) VALUE(&INLEN - 1)
             GOTO       CMDLBL(TRIN)
 TRIN1:

             IF         COND(&INLEN *EQ 0) THEN(GOTO CMDLBL(PAINT))

             IF         COND(%SST(&INPUT 1 1) *NE '/') THEN(GOTO +
                          CMDLBL(SAY))

             CHGVAR     VAR(&FIRST5) VALUE(%SST(&INPUT 1 5))
             CHGVAR     VAR(&FIRST6) VALUE(%SST(&INPUT 1 6))
             CHGVAR     VAR(&FIRST7) VALUE(%SST(&INPUT 1 7))

             IF         COND((&FIRST5 *EQ '/quit') *AND +
                          ((&INLEN *EQ 5) *OR +
                           (%SST(&INPUT 6 1) *EQ ' '))) +
                          THEN(DO)
               CHGVAR     VAR(&CMD) VALUE('X')
               CHGVAR     VAR(&CMDLEN) VALUE(1)
               CALL       PGM(QSNDDTAQ) +
                            PARM(&OQNAME &OQLIB &CMDLEN &CMD)
               GOTO       CMDLBL(END)
             ENDDO

             IF         COND(&FIRST7 *EQ '/quote ') THEN(DO)
               IF         COND(&INLEN *LE 7) THEN(DO)
                 CHGVAR     VAR(&STSMSG) +
                              VALUE('Usage: /quote raw-IRC-command')
                 GOTO       CMDLBL(PAINT)
               ENDDO
               CHGVAR     VAR(&PAYLEN) VALUE(&INLEN - 7)
               CHGVAR     VAR(&CMD) VALUE('C' *CAT +
                            %SST(&INPUT 8 &PAYLEN))
               CHGVAR     VAR(&CMDLEN) VALUE(&INLEN - 6)
               CALL       PGM(QSNDDTAQ) +
                            PARM(&OQNAME &OQLIB &CMDLEN &CMD)
               GOTO       CMDLBL(PAINT)
             ENDDO

             IF         COND(&FIRST6 *EQ '/join ') THEN(DO)
               IF         COND(&INLEN *LE 6) THEN(DO)
                 CHGVAR     VAR(&STSMSG) +
                              VALUE('Usage: /join #channel')
                 GOTO       CMDLBL(PAINT)
               ENDDO
               CHGVAR     VAR(&PAYLEN) VALUE(&INLEN - 6)
               CHGVAR     VAR(&CMD) VALUE('CJOIN ' *CAT +
                            %SST(&INPUT 7 &PAYLEN))
               CHGVAR     VAR(&CMDLEN) VALUE(&INLEN)
               CALL       PGM(QSNDDTAQ) +
                            PARM(&OQNAME &OQLIB &CMDLEN &CMD)
               GOTO       CMDLBL(PAINT)
             ENDDO

             CHGVAR     VAR(&STSMSG) +
                          VALUE('Unknown command. Try +
                          /quit /quote /join')
             GOTO       CMDLBL(PAINT)

 SAY:
             CHGVAR     VAR(&CHLEN) VALUE(64)
 TRCH:       IF         COND(&CHLEN *EQ 0) THEN(GOTO CMDLBL(TRCH1))
             IF         COND(%SST(&PCHAN &CHLEN 1) *NE ' ') +
                          THEN(GOTO CMDLBL(TRCH1))
             CHGVAR     VAR(&CHLEN) VALUE(&CHLEN - 1)
             GOTO       CMDLBL(TRCH)
 TRCH1:

             IF         COND(&CHLEN *EQ 0) THEN(DO)
               CHGVAR     VAR(&STSMSG) +
                          VALUE('No current channel. /join #x first.')
               GOTO       CMDLBL(PAINT)
             ENDDO

             CHGVAR     VAR(&CMD) VALUE('CPRIVMSG ' *CAT +
                          %SST(&PCHAN 1 &CHLEN) *CAT ' :' *CAT +
                          %SST(&INPUT 1 &INLEN))
             CHGVAR     VAR(&CMDLEN) VALUE(&CHLEN + &INLEN + 11)
             CALL       PGM(QSNDDTAQ) +
                          PARM(&OQNAME &OQLIB &CMDLEN &CMD)
             GOTO       CMDLBL(PAINT)

 BIGSEND:
             /*--------------------------------------------------*/
             /* Big mode submit: concat 9 input lines via *BCAT  */
             /* (left operand auto-trimmed of trailing blanks +  */
             /* one space inserted), then trim trailing blanks   */
             /* of the result and dispatch as one PRIVMSG.       */
             /*--------------------------------------------------*/
             CHGVAR     VAR(&STSMSG) VALUE(' ')

             CHGVAR     VAR(&BODY) VALUE(&BIG01 *BCAT &BIG02 +
                          *BCAT &BIG03 *BCAT &BIG04 *BCAT +
                          &BIG05 *BCAT &BIG06 *BCAT &BIG07 +
                          *BCAT &BIG08 *BCAT &BIG09)

             CHGVAR     VAR(&BODYLEN) VALUE(700)
 TRBOD:      IF         COND(&BODYLEN *EQ 0) THEN(GOTO +
                          CMDLBL(TRBOD1))
             IF         COND(%SST(&BODY &BODYLEN 1) *NE ' ') +
                          THEN(GOTO CMDLBL(TRBOD1))
             CHGVAR     VAR(&BODYLEN) VALUE(&BODYLEN - 1)
             GOTO       CMDLBL(TRBOD)
 TRBOD1:

             IF         COND(&BODYLEN *EQ 0) THEN(DO)
               /* Empty: collapse without sending */
               CHGVAR     VAR(&MODE) VALUE('S')
               GOTO       CMDLBL(PAINT)
             ENDDO

             /* Trim leading blanks: BIG01 may have started past   */
             /* col 1 if the cursor was offset when typing began.  */
             CHGVAR     VAR(&BODYSTR) VALUE(1)
 TRBLED:     IF         COND(&BODYSTR *GT &BODYLEN) THEN(GOTO +
                          CMDLBL(TRBLED1))
             IF         COND(%SST(&BODY &BODYSTR 1) *NE ' ') +
                          THEN(GOTO CMDLBL(TRBLED1))
             CHGVAR     VAR(&BODYSTR) VALUE(&BODYSTR + 1)
             GOTO       CMDLBL(TRBLED)
 TRBLED1:

             CHGVAR     VAR(&BODYEFF) VALUE(&BODYLEN - &BODYSTR + 1)
             IF         COND(&BODYEFF *LE 0) THEN(DO)
               CHGVAR     VAR(&MODE) VALUE('S')
               GOTO       CMDLBL(PAINT)
             ENDDO

             CHGVAR     VAR(&CHLEN) VALUE(64)
 TRCB:       IF         COND(&CHLEN *EQ 0) THEN(GOTO CMDLBL(TRCB1))
             IF         COND(%SST(&PCHAN &CHLEN 1) *NE ' ') +
                          THEN(GOTO CMDLBL(TRCB1))
             CHGVAR     VAR(&CHLEN) VALUE(&CHLEN - 1)
             GOTO       CMDLBL(TRCB)
 TRCB1:

             IF         COND(&CHLEN *EQ 0) THEN(DO)
               CHGVAR     VAR(&STSMSG) +
                          VALUE('No current channel. /join #x first.')
               GOTO       CMDLBL(PAINT)
             ENDDO

             CHGVAR     VAR(&CMD) VALUE('CPRIVMSG ' *CAT +
                          %SST(&PCHAN 1 &CHLEN) *CAT ' :' *CAT +
                          %SST(&BODY &BODYSTR &BODYEFF))
             CHGVAR     VAR(&CMDLEN) VALUE(&CHLEN + &BODYEFF + 11)
             CALL       PGM(QSNDDTAQ) +
                          PARM(&OQNAME &OQLIB &CMDLEN &CMD)

             /* Clear BIG fields, switch to small */
             CHGVAR     VAR(&BIG01) VALUE(' ')
             CHGVAR     VAR(&BIG02) VALUE(' ')
             CHGVAR     VAR(&BIG03) VALUE(' ')
             CHGVAR     VAR(&BIG04) VALUE(' ')
             CHGVAR     VAR(&BIG05) VALUE(' ')
             CHGVAR     VAR(&BIG06) VALUE(' ')
             CHGVAR     VAR(&BIG07) VALUE(' ')
             CHGVAR     VAR(&BIG08) VALUE(' ')
             CHGVAR     VAR(&BIG09) VALUE(' ')
             CHGVAR     VAR(&MODE) VALUE('S')
             GOTO       CMDLBL(PAINT)

 REPAINT:
             /* In big mode we don't refresh: a SNDF CHATOUT    */
             /* would clobber CHATBIG's input fields.           */
             IF         COND(&MODE *EQ 'B') THEN(GOTO +
                          CMDLBL(WAIT))

             CALL       PGM(IRCCLIENT/IRCCHATL) +
                          PARM(&PWIN &CHATBUF &KINDBUF &MAXSEQ)

             CHGVAR     VAR(&TS01) VALUE(%SST(&CHATBUF    1  8))
             CHGVAR     VAR(&NK01) VALUE(%SST(&CHATBUF    9 16))
             CHGVAR     VAR(&MS01) VALUE(%SST(&CHATBUF   25 52))
             CHGVAR     VAR(&IN11) VALUE(%SST(&KINDBUF  1 1) *EQ '1')
             CHGVAR     VAR(&IN12) VALUE(%SST(&KINDBUF  2 1) *EQ '1')
             CHGVAR     VAR(&IN13) VALUE(%SST(&KINDBUF  3 1) *EQ '1')
             CHGVAR     VAR(&TS02) VALUE(%SST(&CHATBUF   77  8))
             CHGVAR     VAR(&NK02) VALUE(%SST(&CHATBUF   85 16))
             CHGVAR     VAR(&MS02) VALUE(%SST(&CHATBUF  101 52))
             CHGVAR     VAR(&IN14) VALUE(%SST(&KINDBUF  4 1) *EQ '1')
             CHGVAR     VAR(&IN15) VALUE(%SST(&KINDBUF  5 1) *EQ '1')
             CHGVAR     VAR(&IN16) VALUE(%SST(&KINDBUF  6 1) *EQ '1')
             CHGVAR     VAR(&TS03) VALUE(%SST(&CHATBUF  153  8))
             CHGVAR     VAR(&NK03) VALUE(%SST(&CHATBUF  161 16))
             CHGVAR     VAR(&MS03) VALUE(%SST(&CHATBUF  177 52))
             CHGVAR     VAR(&IN17) VALUE(%SST(&KINDBUF  7 1) *EQ '1')
             CHGVAR     VAR(&IN18) VALUE(%SST(&KINDBUF  8 1) *EQ '1')
             CHGVAR     VAR(&IN19) VALUE(%SST(&KINDBUF  9 1) *EQ '1')
             CHGVAR     VAR(&TS04) VALUE(%SST(&CHATBUF  229  8))
             CHGVAR     VAR(&NK04) VALUE(%SST(&CHATBUF  237 16))
             CHGVAR     VAR(&MS04) VALUE(%SST(&CHATBUF  253 52))
             CHGVAR     VAR(&IN20) VALUE(%SST(&KINDBUF 10 1) *EQ '1')
             CHGVAR     VAR(&IN21) VALUE(%SST(&KINDBUF 11 1) *EQ '1')
             CHGVAR     VAR(&IN22) VALUE(%SST(&KINDBUF 12 1) *EQ '1')
             CHGVAR     VAR(&TS05) VALUE(%SST(&CHATBUF  305  8))
             CHGVAR     VAR(&NK05) VALUE(%SST(&CHATBUF  313 16))
             CHGVAR     VAR(&MS05) VALUE(%SST(&CHATBUF  329 52))
             CHGVAR     VAR(&IN23) VALUE(%SST(&KINDBUF 13 1) *EQ '1')
             CHGVAR     VAR(&IN24) VALUE(%SST(&KINDBUF 14 1) *EQ '1')
             CHGVAR     VAR(&IN25) VALUE(%SST(&KINDBUF 15 1) *EQ '1')
             CHGVAR     VAR(&TS06) VALUE(%SST(&CHATBUF  381  8))
             CHGVAR     VAR(&NK06) VALUE(%SST(&CHATBUF  389 16))
             CHGVAR     VAR(&MS06) VALUE(%SST(&CHATBUF  405 52))
             CHGVAR     VAR(&IN26) VALUE(%SST(&KINDBUF 16 1) *EQ '1')
             CHGVAR     VAR(&IN27) VALUE(%SST(&KINDBUF 17 1) *EQ '1')
             CHGVAR     VAR(&IN28) VALUE(%SST(&KINDBUF 18 1) *EQ '1')
             CHGVAR     VAR(&TS07) VALUE(%SST(&CHATBUF  457  8))
             CHGVAR     VAR(&NK07) VALUE(%SST(&CHATBUF  465 16))
             CHGVAR     VAR(&MS07) VALUE(%SST(&CHATBUF  481 52))
             CHGVAR     VAR(&IN29) VALUE(%SST(&KINDBUF 19 1) *EQ '1')
             CHGVAR     VAR(&IN30) VALUE(%SST(&KINDBUF 20 1) *EQ '1')
             CHGVAR     VAR(&IN31) VALUE(%SST(&KINDBUF 21 1) *EQ '1')
             CHGVAR     VAR(&TS08) VALUE(%SST(&CHATBUF  533  8))
             CHGVAR     VAR(&NK08) VALUE(%SST(&CHATBUF  541 16))
             CHGVAR     VAR(&MS08) VALUE(%SST(&CHATBUF  557 52))
             CHGVAR     VAR(&IN32) VALUE(%SST(&KINDBUF 22 1) *EQ '1')
             CHGVAR     VAR(&IN33) VALUE(%SST(&KINDBUF 23 1) *EQ '1')
             CHGVAR     VAR(&IN34) VALUE(%SST(&KINDBUF 24 1) *EQ '1')
             CHGVAR     VAR(&TS09) VALUE(%SST(&CHATBUF  609  8))
             CHGVAR     VAR(&NK09) VALUE(%SST(&CHATBUF  617 16))
             CHGVAR     VAR(&MS09) VALUE(%SST(&CHATBUF  633 52))
             CHGVAR     VAR(&IN35) VALUE(%SST(&KINDBUF 25 1) *EQ '1')
             CHGVAR     VAR(&IN36) VALUE(%SST(&KINDBUF 26 1) *EQ '1')
             CHGVAR     VAR(&IN37) VALUE(%SST(&KINDBUF 27 1) *EQ '1')
             CHGVAR     VAR(&TS10) VALUE(%SST(&CHATBUF  685  8))
             CHGVAR     VAR(&NK10) VALUE(%SST(&CHATBUF  693 16))
             CHGVAR     VAR(&MS10) VALUE(%SST(&CHATBUF  709 52))
             CHGVAR     VAR(&IN38) VALUE(%SST(&KINDBUF 28 1) *EQ '1')
             CHGVAR     VAR(&IN39) VALUE(%SST(&KINDBUF 29 1) *EQ '1')
             CHGVAR     VAR(&IN40) VALUE(%SST(&KINDBUF 30 1) *EQ '1')
             CHGVAR     VAR(&TS11) VALUE(%SST(&CHATBUF  761  8))
             CHGVAR     VAR(&NK11) VALUE(%SST(&CHATBUF  769 16))
             CHGVAR     VAR(&MS11) VALUE(%SST(&CHATBUF  785 52))
             CHGVAR     VAR(&IN41) VALUE(%SST(&KINDBUF 31 1) *EQ '1')
             CHGVAR     VAR(&IN42) VALUE(%SST(&KINDBUF 32 1) *EQ '1')
             CHGVAR     VAR(&IN43) VALUE(%SST(&KINDBUF 33 1) *EQ '1')
             CHGVAR     VAR(&TS12) VALUE(%SST(&CHATBUF  837  8))
             CHGVAR     VAR(&NK12) VALUE(%SST(&CHATBUF  845 16))
             CHGVAR     VAR(&MS12) VALUE(%SST(&CHATBUF  861 52))
             CHGVAR     VAR(&IN44) VALUE(%SST(&KINDBUF 34 1) *EQ '1')
             CHGVAR     VAR(&IN45) VALUE(%SST(&KINDBUF 35 1) *EQ '1')
             CHGVAR     VAR(&IN46) VALUE(%SST(&KINDBUF 36 1) *EQ '1')
             CHGVAR     VAR(&TS13) VALUE(%SST(&CHATBUF  913  8))
             CHGVAR     VAR(&NK13) VALUE(%SST(&CHATBUF  921 16))
             CHGVAR     VAR(&MS13) VALUE(%SST(&CHATBUF  937 52))
             CHGVAR     VAR(&IN47) VALUE(%SST(&KINDBUF 37 1) *EQ '1')
             CHGVAR     VAR(&IN48) VALUE(%SST(&KINDBUF 38 1) *EQ '1')
             CHGVAR     VAR(&IN49) VALUE(%SST(&KINDBUF 39 1) *EQ '1')
             CHGVAR     VAR(&TS14) VALUE(%SST(&CHATBUF  989  8))
             CHGVAR     VAR(&NK14) VALUE(%SST(&CHATBUF  997 16))
             CHGVAR     VAR(&MS14) VALUE(%SST(&CHATBUF 1013 52))
             CHGVAR     VAR(&IN50) VALUE(%SST(&KINDBUF 40 1) *EQ '1')
             CHGVAR     VAR(&IN51) VALUE(%SST(&KINDBUF 41 1) *EQ '1')
             CHGVAR     VAR(&IN52) VALUE(%SST(&KINDBUF 42 1) *EQ '1')
             CHGVAR     VAR(&TS15) VALUE(%SST(&CHATBUF 1065  8))
             CHGVAR     VAR(&NK15) VALUE(%SST(&CHATBUF 1073 16))
             CHGVAR     VAR(&MS15) VALUE(%SST(&CHATBUF 1089 52))
             CHGVAR     VAR(&IN53) VALUE(%SST(&KINDBUF 43 1) *EQ '1')
             CHGVAR     VAR(&IN54) VALUE(%SST(&KINDBUF 44 1) *EQ '1')
             CHGVAR     VAR(&IN55) VALUE(%SST(&KINDBUF 45 1) *EQ '1')
             CHGVAR     VAR(&TS16) VALUE(%SST(&CHATBUF 1141  8))
             CHGVAR     VAR(&NK16) VALUE(%SST(&CHATBUF 1149 16))
             CHGVAR     VAR(&MS16) VALUE(%SST(&CHATBUF 1165 52))
             CHGVAR     VAR(&IN56) VALUE(%SST(&KINDBUF 46 1) *EQ '1')
             CHGVAR     VAR(&IN57) VALUE(%SST(&KINDBUF 47 1) *EQ '1')
             CHGVAR     VAR(&IN58) VALUE(%SST(&KINDBUF 48 1) *EQ '1')
             CHGVAR     VAR(&TS17) VALUE(%SST(&CHATBUF 1217  8))
             CHGVAR     VAR(&NK17) VALUE(%SST(&CHATBUF 1225 16))
             CHGVAR     VAR(&MS17) VALUE(%SST(&CHATBUF 1241 52))
             CHGVAR     VAR(&IN59) VALUE(%SST(&KINDBUF 49 1) *EQ '1')
             CHGVAR     VAR(&IN60) VALUE(%SST(&KINDBUF 50 1) *EQ '1')
             CHGVAR     VAR(&IN61) VALUE(%SST(&KINDBUF 51 1) *EQ '1')
             CHGVAR     VAR(&TS18) VALUE(%SST(&CHATBUF 1293  8))
             CHGVAR     VAR(&NK18) VALUE(%SST(&CHATBUF 1301 16))
             CHGVAR     VAR(&MS18) VALUE(%SST(&CHATBUF 1317 52))
             CHGVAR     VAR(&IN62) VALUE(%SST(&KINDBUF 52 1) *EQ '1')
             CHGVAR     VAR(&IN63) VALUE(%SST(&KINDBUF 53 1) *EQ '1')
             CHGVAR     VAR(&IN64) VALUE(%SST(&KINDBUF 54 1) *EQ '1')
             CHGVAR     VAR(&TS19) VALUE(%SST(&CHATBUF 1369  8))
             CHGVAR     VAR(&NK19) VALUE(%SST(&CHATBUF 1377 16))
             CHGVAR     VAR(&MS19) VALUE(%SST(&CHATBUF 1393 52))
             CHGVAR     VAR(&IN65) VALUE(%SST(&KINDBUF 55 1) *EQ '1')
             CHGVAR     VAR(&IN66) VALUE(%SST(&KINDBUF 56 1) *EQ '1')
             CHGVAR     VAR(&IN67) VALUE(%SST(&KINDBUF 57 1) *EQ '1')

             SNDF       RCDFMT(CHATOUT)
             MONMSG     MSGID(CPF0000)
             GOTO       CMDLBL(WAIT)

 END:        ENDPGM
