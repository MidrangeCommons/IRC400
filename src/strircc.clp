             /*-----------------------------------------------*/
             /* STRIRCC - Start IRC Client Controller         */
             /*                                               */
             /* Phase 4: validate parms, SBMJOB IRCNETD,      */
             /* sleep for registration, push auto-JOIN onto   */
             /* IRCOUTQ, hand control to IRCCHATC.            */
             /*                                               */
             /* When IRCCHATC returns, push 'X' to IRCOUTQ as */
             /* a safety net so IRCNETD shuts down even if    */
             /* the user exited via F3 instead of /quit.      */
             /*                                               */
             /* Phase 5 will replace the fixed DLYJOB(15)     */
             /* with a poll on IRCCONF.connected.             */
             /*                                               */
             /* Compile:                                      */
             /*   CRTCLPGM PGM(IRCCLIENT/STRIRCC)             */
             /*            SRCFILE(IRCCLIENT/QCLSRC)          */
             /*-----------------------------------------------*/
             PGM        PARM(&NICK &SERVER &PORT &CHAN)

             DCL        VAR(&NICK)    TYPE(*CHAR) LEN(32)
             DCL        VAR(&SERVER)  TYPE(*CHAR) LEN(64)
             DCL        VAR(&PORT)    TYPE(*DEC)  LEN(5 0)
             DCL        VAR(&CHAN)    TYPE(*CHAR) LEN(64)

             /* Working storage */
             DCL        VAR(&PORTC)   TYPE(*CHAR) LEN(8)
             DCL        VAR(&MSG)     TYPE(*CHAR) LEN(80)
             DCL        VAR(&CMD)     TYPE(*CHAR) LEN(80)
             DCL        VAR(&CMDLEN)  TYPE(*DEC)  LEN(5 0)
             DCL        VAR(&CHLEN)   TYPE(*DEC)  LEN(3 0)
             DCL        VAR(&PWIN)    TYPE(*CHAR) LEN(4)  +
                                       VALUE('0000')

             /* QSNDDTAQ API call params (V4R5 has no SNDDTAQ CL)  */
             DCL        VAR(&QNAME)   TYPE(*CHAR) LEN(10) +
                                       VALUE('IRCOUTQ')
             DCL        VAR(&QLIB)    TYPE(*CHAR) LEN(10) +
                                       VALUE('IRCCLIENT')

             CHGVAR     VAR(&PORTC) VALUE(&PORT)

             /* Drain stale entries from IRCOUTQ so a leftover     */
             /* 'X' (safety byte from a prior STRIRC's exit) does  */
             /* not poison this session's freshly-launched engine. */
             CALL       PGM(QCLRDTAQ) PARM(&QNAME &QLIB)
             MONMSG     MSGID(CPF0000)

             CHGVAR     VAR(&MSG) VALUE('STRIRC: submitting +
                          IRCNETD...')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             /*-----------------------------------------------*/
             /* Submit IRCNETD batch                          */
             /*-----------------------------------------------*/
             SBMJOB     CMD(CALL PGM(IRCCLIENT/IRCNETD) +
                          PARM(&SERVER &PORTC &NICK +
                               'IRC400 client')) +
                          JOB(IRCNETD)
             MONMSG     MSGID(CPF0000) EXEC(DO)
               CHGVAR     VAR(&MSG) +
                            VALUE('FAIL SBMJOB IRCNETD')
               SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
               GOTO       CMDLBL(END)
             ENDDO

             /*-----------------------------------------------*/
             /* Wait for IRCNETD to register (fixed sleep     */
             /* for Phase 4; Phase 5 will poll IRCCONF).      */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&MSG) VALUE('Waiting 15s +
                          for engine to register...')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
             DLYJOB     DLY(15)

             /*-----------------------------------------------*/
             /* Auto-join initial channel (if any)            */
             /*-----------------------------------------------*/
             /* Trim CHAN length */
             CHGVAR     VAR(&CHLEN) VALUE(64)
 TRCH:       IF         COND(&CHLEN *EQ 0) THEN(GOTO CMDLBL(TRCH1))
             IF         COND(%SST(&CHAN &CHLEN 1) *NE ' ') +
                          THEN(GOTO CMDLBL(TRCH1))
             CHGVAR     VAR(&CHLEN) VALUE(&CHLEN - 1)
             GOTO       CMDLBL(TRCH)
 TRCH1:

             IF         COND(&CHLEN *GT 0) THEN(DO)
               CHGVAR     VAR(&CMD) VALUE('CJOIN ' *CAT +
                            %SST(&CHAN 1 &CHLEN))
               CHGVAR     VAR(&CMDLEN) VALUE(&CHLEN + 6)
               CALL       PGM(QSNDDTAQ) +
                            PARM(&QNAME &QLIB &CMDLEN &CMD)
             ENDDO

             /*-----------------------------------------------*/
             /* Hand off to chat panel                        */
             /*-----------------------------------------------*/
             CALL       PGM(IRCCLIENT/IRCCHATC) +
                          PARM(&PWIN &CHAN &NICK)
             MONMSG     MSGID(CPF0000)

             /*-----------------------------------------------*/
             /* Safety: ensure IRCNETD ends                   */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&CMD) VALUE('X')
             CHGVAR     VAR(&CMDLEN) VALUE(1)
             CALL       PGM(QSNDDTAQ) +
                          PARM(&QNAME &QLIB &CMDLEN &CMD)
             MONMSG     MSGID(CPF0000)

             CHGVAR     VAR(&MSG) VALUE('STRIRC ended.')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

 END:        ENDPGM
