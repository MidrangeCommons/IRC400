             /*-----------------------------------------------*/
             /* STRIRC - Start IRC Client Command             */
             /*                                               */
             /* Compile:                                      */
             /*   CRTCMD CMD(IRCCLIENT/STRIRC)                */
             /*          PGM(IRCCLIENT/STRIRCC)               */
             /*          SRCFILE(IRCCLIENT/QCMDSRC)           */
             /*          SRCMBR(STRIRC)                       */
             /*-----------------------------------------------*/
             CMD        PROMPT('Start IRC Client')

             PARM       KWD(NICK)   TYPE(*CHAR) LEN(32) MIN(1) +
                          PROMPT('IRC nick')
             PARM       KWD(SERVER) TYPE(*CHAR) LEN(64) +
                          DFT('irc.libera.chat') +
                          PROMPT('IRC server host')
             PARM       KWD(PORT)   TYPE(*DEC)  LEN(5 0) +
                          DFT(6667) +
                          RANGE(1 65535) +
                          PROMPT('TCP port')
             PARM       KWD(CHAN)   TYPE(*CHAR) LEN(64) +
                          DFT('#test') +
                          PROMPT('Initial channel')
