             /*-----------------------------------------------*/
             /* IRCTEST1 - Phase 1 acceptance test            */
             /*                                               */
             /* Verifies the persistence layer:               */
             /*   1. Append 10 records to MSGBUF (auto-seq)   */
             /*   2. Walk N (next-after) from seq=5; expect   */
             /*      5 records returned                       */
             /*   3. Round-trip a string through IRCOUTQ      */
             /*                                               */
             /* All output via SNDPGMMSG so it shows up in    */
             /* the job log when called interactively.        */
             /*                                               */
             /* Run:                                          */
             /*   ADDLIBLE LIB(IRCCLIENT)                     */
             /*   CALL PGM(IRCCLIENT/IRCTEST1)                */
             /*-----------------------------------------------*/
             PGM

             DCL        VAR(&MSG)   TYPE(*CHAR) LEN(80)
             DCL        VAR(&I)     TYPE(*DEC)  LEN(2 0) VALUE(0)
             DCL        VAR(&COUNT) TYPE(*DEC)  LEN(5 0) VALUE(0)
             DCL        VAR(&CNTC)  TYPE(*CHAR) LEN(5)

             /* IRCBUFM parameters */
             DCL        VAR(&OP)    TYPE(*CHAR) LEN(1)
             DCL        VAR(&SEQ)   TYPE(*CHAR) LEN(9)
             DCL        VAR(&WIN)   TYPE(*CHAR) LEN(4) +
                                     VALUE('0001')
             DCL        VAR(&TS)    TYPE(*CHAR) LEN(8) +
                                     VALUE('12:00:00')
             DCL        VAR(&KIND)  TYPE(*CHAR) LEN(1) VALUE('S')
             DCL        VAR(&NICK)  TYPE(*CHAR) LEN(32) +
                                     VALUE('TEST')
             DCL        VAR(&NCOL)  TYPE(*CHAR) LEN(1) VALUE('W')
             DCL        VAR(&FRAGS) TYPE(*CHAR) LEN(512)
             DCL        VAR(&RETC)  TYPE(*CHAR) LEN(4)

             /* Data queue test buffers + API call params           */
             /* (V4R5 has no SNDDTAQ/RCVDTAQ CL commands)            */
             DCL        VAR(&DQI)   TYPE(*CHAR) LEN(32) +
                                     VALUE('IRCTEST1-PING-12345678901234567')
             DCL        VAR(&DQO)   TYPE(*CHAR) LEN(32)
             DCL        VAR(&DLEN)  TYPE(*DEC)  LEN(5 0) VALUE(32)
             DCL        VAR(&WAIT)  TYPE(*DEC)  LEN(5 0) VALUE(1)
             DCL        VAR(&QNAME) TYPE(*CHAR) LEN(10) +
                                     VALUE('IRCOUTQ')
             DCL        VAR(&QLIB)  TYPE(*CHAR) LEN(10) +
                                     VALUE('IRCCLIENT')

             CHGVAR     VAR(&MSG) VALUE('IRCTEST1 start')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             /*-----------------------------------------------*/
             /* Step 0: trim any leftover MSGBUF records      */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&OP)  VALUE('T')
             CHGVAR     VAR(&SEQ) VALUE('999999999')
             CALL       PGM(IRCCLIENT/IRCBUFM) +
                          PARM(&OP &SEQ &WIN &TS &KIND +
                               &NICK &NCOL &FRAGS &RETC)

             /*-----------------------------------------------*/
             /* Step 1: append 10 records with auto-seq       */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&OP) VALUE('A')

 LOOP1:
             CHGVAR     VAR(&I)   VALUE(&I + 1)
             CHGVAR     VAR(&SEQ) VALUE('000000000')
             CALL       PGM(IRCCLIENT/IRCBUFM) +
                          PARM(&OP &SEQ &WIN &TS &KIND +
                               &NICK &NCOL &FRAGS &RETC)
             IF         COND(&RETC *NE '0000') THEN(DO)
               CHGVAR     VAR(&MSG) +
                            VALUE('FAIL append retc=' *BCAT &RETC)
               SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
               GOTO       CMDLBL(END)
             ENDDO
             IF         COND(&I *LT 10) THEN(GOTO CMDLBL(LOOP1))

             CHGVAR     VAR(&MSG) VALUE('OK appended 10 records')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             /*-----------------------------------------------*/
             /* Step 2: read since seq=5 via 'N' walk         */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&OP)    VALUE('N')
             CHGVAR     VAR(&SEQ)   VALUE('000000005')
             CHGVAR     VAR(&COUNT) VALUE(0)

 LOOP2:
             CALL       PGM(IRCCLIENT/IRCBUFM) +
                          PARM(&OP &SEQ &WIN &TS &KIND +
                               &NICK &NCOL &FRAGS &RETC)
             IF         COND(&RETC *NE '0000') THEN(GOTO +
                          CMDLBL(DONE2))
             CHGVAR     VAR(&COUNT) VALUE(&COUNT + 1)
             GOTO       CMDLBL(LOOP2)

 DONE2:
             CHGVAR     VAR(&CNTC) VALUE(&COUNT)
             CHGVAR     VAR(&MSG) VALUE('Read since 5 returned')
             CHGVAR     VAR(&MSG) VALUE(&MSG *BCAT &CNTC)
             CHGVAR     VAR(&MSG) VALUE(&MSG *BCAT '(expect 5)')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             /*-----------------------------------------------*/
             /* Step 3: data queue round-trip                  */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&DLEN) VALUE(32)
             CALL       PGM(QSNDDTAQ) +
                          PARM(&QNAME &QLIB &DLEN &DQI)
             CHGVAR     VAR(&DLEN) VALUE(32)
             CHGVAR     VAR(&WAIT) VALUE(1)
             CALL       PGM(QRCVDTAQ) +
                          PARM(&QNAME &QLIB &DLEN &DQO &WAIT)
             IF         COND(&DQO *EQ &DQI) THEN(DO)
               CHGVAR     VAR(&MSG) +
                            VALUE('OK IRCOUTQ round-trip')
               SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
             ENDDO
             ELSE       CMD(DO)
               CHGVAR     VAR(&MSG) +
                            VALUE('FAIL IRCOUTQ round-trip')
               SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)
             ENDDO

             CHGVAR     VAR(&MSG) VALUE('IRCTEST1 complete')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

 END:        ENDPGM
