             /*-----------------------------------------------*/
             /* BUILD - Compile all IRC Client objects        */
             /*                                               */
             /* Six-phase build. Step 3 still empty until     */
             /* Phase 4 (chat panel display file) lands.      */
             /*                                               */
             /*   Step 1: Data area  (IRCCONF)                */
             /*   Step 2: Physical files (MSGBUF, IRCSRVR,    */
             /*           IRCWINR) + data queues              */
             /*   Step 3: Display files                       */
             /*   Step 4: ILE C programs                      */
             /*   Step 5: CL programs                         */
             /*   Step 6: Command                             */
             /*                                               */
             /* MONMSG on every step so a single failure      */
             /* does not abort the rest of the build.         */
             /*-----------------------------------------------*/
             PGM

             DCL        VAR(&MSG) TYPE(*CHAR) LEN(50)

             /*-----------------------------------------------*/
             /* Step 1: Data area + data queues               */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&MSG) VALUE('Step 1: Data area')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             DLTDTAARA  DTAARA(IRCCLIENT/IRCCONF)
             MONMSG     MSGID(CPF0000)
             CRTDTAARA  DTAARA(IRCCLIENT/IRCCONF) +
                          TYPE(*CHAR) LEN(512) VALUE(' ')
             MONMSG     MSGID(CPF0000)

             DLTDTAQ    DTAQ(IRCCLIENT/IRCOUTQ)
             MONMSG     MSGID(CPF0000)
             CRTDTAQ    DTAQ(IRCCLIENT/IRCOUTQ) MAXLEN(512) +
                          TEXT('UI to net-engine command queue')
             MONMSG     MSGID(CPF0000)

             DLTDTAQ    DTAQ(IRCCLIENT/IRCEVTQ)
             MONMSG     MSGID(CPF0000)
             /* MAXLEN(80) so the same queue can carry both 1-byte    */
             /* engine wakes (sent by IRCNETD) and 80-byte AID-key    */
             /* entries posted by the 5250 workstation when the       */
             /* invited read on IRCCHATD/CHATIN is satisfied.         */
             CRTDTAQ    DTAQ(IRCCLIENT/IRCEVTQ) MAXLEN(80) +
                          TEXT('Net-engine + DSPF wake-up queue')
             MONMSG     MSGID(CPF0000)

             /*-----------------------------------------------*/
             /* Step 2: Physical files                        */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&MSG) VALUE('Step 2: Physical files')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             DLTF       FILE(IRCCLIENT/MSGBUF)
             MONMSG     MSGID(CPF0000)
             CRTPF      FILE(IRCCLIENT/MSGBUF) +
                          SRCFILE(IRCCLIENT/QDDSSRC) +
                          SRCMBR(MSGBUF) SIZE(*NOMAX)
             MONMSG     MSGID(CPF0000)

             DLTF       FILE(IRCCLIENT/IRCSRVR)
             MONMSG     MSGID(CPF0000)
             CRTPF      FILE(IRCCLIENT/IRCSRVR) +
                          SRCFILE(IRCCLIENT/QDDSSRC) +
                          SRCMBR(IRCSRVR) SIZE(*NOMAX)
             MONMSG     MSGID(CPF0000)

             DLTF       FILE(IRCCLIENT/IRCWINR)
             MONMSG     MSGID(CPF0000)
             CRTPF      FILE(IRCCLIENT/IRCWINR) +
                          SRCFILE(IRCCLIENT/QDDSSRC) +
                          SRCMBR(IRCWINR) SIZE(*NOMAX)
             MONMSG     MSGID(CPF0000)

             /*-----------------------------------------------*/
             /* Step 3: Display files                         */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&MSG) VALUE('Step 3: Display files')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             DLTF       FILE(IRCCLIENT/IRCCHATD)
             MONMSG     MSGID(CPF0000)
             CRTDSPF    FILE(IRCCLIENT/IRCCHATD) +
                          SRCFILE(IRCCLIENT/QDDSSRC) +
                          SRCMBR(IRCCHATD)
             MONMSG     MSGID(CPF0000)

             /*-----------------------------------------------*/
             /* Step 4: ILE C programs                        */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&MSG) +
                          VALUE('Step 4: ILE C programs')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             DLTPGM     PGM(IRCCLIENT/IRCBUFM)
             MONMSG     MSGID(CPF0000)
             CRTBNDC    PGM(IRCCLIENT/IRCBUFM) +
                          SRCFILE(IRCCLIENT/QCSRC) +
                          SRCMBR(IRCBUFM)
             MONMSG     MSGID(CPF0000)

             DLTPGM     PGM(IRCCLIENT/IRCSRVM)
             MONMSG     MSGID(CPF0000)
             CRTBNDC    PGM(IRCCLIENT/IRCSRVM) +
                          SRCFILE(IRCCLIENT/QCSRC) +
                          SRCMBR(IRCSRVM)
             MONMSG     MSGID(CPF0000)

             /* IRCNETD now binds the IRCFMT module so it can call  */
             /* ircfmt_clean(). Build modules first, then CRTPGM.   */
             DLTMOD     MODULE(IRCCLIENT/IRCFMT)
             MONMSG     MSGID(CPF0000)
             CRTCMOD    MODULE(IRCCLIENT/IRCFMT) +
                          SRCFILE(IRCCLIENT/QCSRC) +
                          SRCMBR(IRCFMT)
             MONMSG     MSGID(CPF0000)

             DLTMOD     MODULE(IRCCLIENT/IRCNETD)
             MONMSG     MSGID(CPF0000)
             CRTCMOD    MODULE(IRCCLIENT/IRCNETD) +
                          SRCFILE(IRCCLIENT/QCSRC) +
                          SRCMBR(IRCNETD) +
                          SYSIFCOPT(*IFSIO)
             MONMSG     MSGID(CPF0000)

             DLTPGM     PGM(IRCCLIENT/IRCNETD)
             MONMSG     MSGID(CPF0000)
             CRTPGM     PGM(IRCCLIENT/IRCNETD) +
                          MODULE(IRCCLIENT/IRCNETD +
                                 IRCCLIENT/IRCFMT) +
                          ENTMOD(IRCCLIENT/IRCNETD)
             MONMSG     MSGID(CPF0000)

             DLTPGM     PGM(IRCCLIENT/IRCCHATL)
             MONMSG     MSGID(CPF0000)
             CRTBNDC    PGM(IRCCLIENT/IRCCHATL) +
                          SRCFILE(IRCCLIENT/QCSRC) +
                          SRCMBR(IRCCHATL)
             MONMSG     MSGID(CPF0000)

             /*-----------------------------------------------*/
             /* Step 5: CL programs                           */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&MSG) VALUE('Step 5: CL programs')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             DLTPGM     PGM(IRCCLIENT/STRIRCC)
             MONMSG     MSGID(CPF0000)
             CRTCLPGM   PGM(IRCCLIENT/STRIRCC) +
                          SRCFILE(IRCCLIENT/QCLSRC) +
                          SRCMBR(STRIRCC)
             MONMSG     MSGID(CPF0000)

             DLTPGM     PGM(IRCCLIENT/IRCTEST1)
             MONMSG     MSGID(CPF0000)
             CRTCLPGM   PGM(IRCCLIENT/IRCTEST1) +
                          SRCFILE(IRCCLIENT/QCLSRC) +
                          SRCMBR(IRCTEST1)
             MONMSG     MSGID(CPF0000)

             DLTPGM     PGM(IRCCLIENT/IRCTEST2)
             MONMSG     MSGID(CPF0000)
             CRTCLPGM   PGM(IRCCLIENT/IRCTEST2) +
                          SRCFILE(IRCCLIENT/QCLSRC) +
                          SRCMBR(IRCTEST2)
             MONMSG     MSGID(CPF0000)

             DLTPGM     PGM(IRCCLIENT/IRCCHATC)
             MONMSG     MSGID(CPF0000)
             CRTCLPGM   PGM(IRCCLIENT/IRCCHATC) +
                          SRCFILE(IRCCLIENT/QCLSRC) +
                          SRCMBR(IRCCHATC)
             MONMSG     MSGID(CPF0000)

             /*-----------------------------------------------*/
             /* Step 6: Command                               */
             /*-----------------------------------------------*/
             CHGVAR     VAR(&MSG) VALUE('Step 6: Command')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             DLTCMD     CMD(IRCCLIENT/STRIRC)
             MONMSG     MSGID(CPF0000)
             CRTCMD     CMD(IRCCLIENT/STRIRC) +
                          PGM(IRCCLIENT/STRIRCC) +
                          SRCFILE(IRCCLIENT/QCMDSRC) +
                          SRCMBR(STRIRC)
             MONMSG     MSGID(CPF0000)

             CHGVAR     VAR(&MSG) +
                          VALUE('Build complete. Type STRIRC.')
             SNDPGMMSG  MSG(&MSG) TOPGMQ(*EXT)

             ENDPGM
