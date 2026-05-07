             /*-----------------------------------------------*/
             /* IRCTEST2 - Phase 3 acceptance test            */
             /*                                               */
             /* Drives the network engine through IRCOUTQ and */
             /* checks that MSGBUF is populated.              */
             /*                                               */
             /*   1. Trim MSGBUF clean                        */
             /*   2. Submit IRCNETD batch job (Libera Chat)   */
             /*   3. Wait 15 s for register + MOTD            */
             /*   4. Send 'CJOIN #IRC400-test' to IRCOUTQ     */
             /*   5. Wait 5 s for JOIN echo + NAMES           */
             /*   6. Send 'CPRIVMSG ...' to IRCOUTQ           */
             /*   7. Wait 5 s                                 */
             /*   8. Send 'X' for clean shutdown              */
             /*   9. Wait 3 s                                 */
             /*  10. Count MSGBUF records via IRCBUFM 'C' op  */
             /*                                               */
             /* The hard-coded server/nick make this a self-  */
             /* contained smoke test. Inspect the IRCNETD     */
             /* spool (WRKSPLF) to confirm the [recv] /       */
             /* [send] traffic looks healthy.                 */
             /*                                               */
             /* Run:                                          */
             /*   ADDLIBLE LIB(IRCCLIENT)                     */
             /*   CALL PGM(IRCCLIENT/IRCTEST2)                */
             /*-----------------------------------------------*/
             PGM

             DCL        VAR(&MSG)   TYPE(*CHAR) LEN(80)
             DCL        VAR(&CMD)   TYPE(*CHAR) LEN(80)
             DCL        VAR(&CLEN)  TYPE(*DEC)  LEN(5 0)

             /* IRCBUFM parameter block */
             DCL        VAR(&OP)    TYPE(*CHAR) LEN(1)
             DCL        VAR(&SEQ)   TYPE(*CHAR) LEN(9)
             DCL        VAR(&WIN)   TYPE(*CHAR) LEN(4)  +
                                     VALUE('0000')
             DCL        VAR(&TS)    TYPE(*CHAR) LEN(8)  +
                                     VALUE('00:00:00')
             DCL        VAR(&KIND)  TYPE(*CHAR) LEN(1)  VALUE('S')
             DCL        VAR(&NICK)  TYPE(*CHAR) LEN(32)
             DCL        VAR(&NCOL)  TYPE(*CHAR) LEN(1)  VALUE('W')
             DCL        VAR(&FRAGS) TYPE(*CHAR) LEN(512)
             DCL        VAR(&RETC)  TYPE(*CHAR) LEN(4)

             /* QSNDDTAQ API params (V4R5 has no SNDDTAQ CL)        */
             DCL        VAR(&QNAME) TYPE(*CHAR) LEN(10) +
                                     VALUE('IRCOUTQ')
             DCL        VAR(&QLIB)  TYPE(*CHAR) LEN(10) +
                                     VALUE('IRCCLIENT')

             CHGVAR     VAR(&MSG) VALUE('IRCTEST2 start')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             /*-----------------------------------------------*/
             /* Step 1: Trim MSGBUF                           */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&OP)  VALUE('T')
             CHGVAR     VAR(&SEQ) VALUE('999999999')
             CALL       PGM(IRCCLIENT/IRCBUFM) +
                          PARM(&OP &SEQ &WIN &TS &KIND +
                               &NICK &NCOL &FRAGS &RETC)

             /*-----------------------------------------------*/
             /* Step 2: Submit IRCNETD batch job              */
             /*-----------------------------------------------*/
             SBMJOB     CMD(CALL PGM(IRCCLIENT/IRCNETD) +
                          PARM('irc.libera.chat' '6667' +
                               'IRC400T' +
                               'IRC400 Phase 3 test')) +
                          JOB(IRCNETD)
             MONMSG     MSGID(CPF0000) EXEC(DO)
               CHGVAR     VAR(&MSG) +
                            VALUE('FAIL SBMJOB IRCNETD')
               SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
               GOTO       CMDLBL(END)
             ENDDO

             CHGVAR     VAR(&MSG) +
                          VALUE('IRCNETD submitted, +
                          waiting 15s for register...')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
             DLYJOB     DLY(15)

             /*-----------------------------------------------*/
             /* Step 3: JOIN a channel                        */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&CMD) +
                          VALUE('CJOIN #IRC400-test')
             CHGVAR     VAR(&CLEN) VALUE(18)
             CALL       PGM(QSNDDTAQ) +
                          PARM(&QNAME &QLIB &CLEN &CMD)
             CHGVAR     VAR(&MSG) +
                          VALUE('Sent JOIN, waiting 5s...')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
             DLYJOB     DLY(5)

             /*-----------------------------------------------*/
             /* Step 4: PRIVMSG to the channel                */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&CMD) +
                          VALUE('CPRIVMSG #IRC400-test +
                          :Hello from V4R5')
             CHGVAR     VAR(&CLEN) VALUE(38)
             CALL       PGM(QSNDDTAQ) +
                          PARM(&QNAME &QLIB &CLEN &CMD)
             CHGVAR     VAR(&MSG) +
                          VALUE('Sent PRIVMSG, waiting 5s...')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
             DLYJOB     DLY(5)

             /*-----------------------------------------------*/
             /* Step 5: Graceful shutdown                     */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&CMD)  VALUE('X')
             CHGVAR     VAR(&CLEN) VALUE(1)
             CALL       PGM(QSNDDTAQ) +
                          PARM(&QNAME &QLIB &CLEN &CMD)
             CHGVAR     VAR(&MSG) +
                          VALUE('Sent X, waiting 3s...')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
             DLYJOB     DLY(3)

             /*-----------------------------------------------*/
             /* Step 6: Verify MSGBUF count                   */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&OP)  VALUE('C')
             CHGVAR     VAR(&SEQ) VALUE('000000000')
             CALL       PGM(IRCCLIENT/IRCBUFM) +
                          PARM(&OP &SEQ &WIN &TS &KIND +
                               &NICK &NCOL &FRAGS &RETC)

             CHGVAR     VAR(&MSG) VALUE('MSGBUF count =')
             CHGVAR     VAR(&MSG) VALUE(&MSG *BCAT &SEQ)
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             CHGVAR     VAR(&MSG) +
                          VALUE('IRCTEST2 done. WRKSPLF +
                          to inspect IRCNETD output.')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

 END:        ENDPGM
