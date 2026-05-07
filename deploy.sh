#!/bin/bash
#-----------------------------------------------------------
# deploy.sh - Deploy and build IRC Client on AS/400
#
# One-command deployment: transfers all sources, creates
# the library, compiles everything, and installs.
#
# Usage:
#   ./deploy.sh <host> <user> <password>
#
# Example:
#   ./deploy.sh 192.168.1.101 QSECOFR QSECOFR0
#
# Prerequisites:
#   - FTP server active on the AS/400 (STRTCPSVR *FTP)
#   - User profile with *ALLOBJ authority
#   - ILE C compiler installed (5769-WDS Option 51)
#   - Option 13 (System Openness Includes) installed
#-----------------------------------------------------------

HOST="${1:?Usage: $0 <host> <user> <password>}"
USER="${2:?Usage: $0 <host> <user> <password>}"
PASS="${3:?Usage: $0 <host> <user> <password>}"

SRCDIR="$(cd "$(dirname "$0")" && pwd)"
ERRORS=0

echo "============================================"
echo " IRC Client for AS/400 V4R5+ - Deploy"
echo "============================================"
echo "  Host : ${HOST}"
echo "  User : ${USER}"
echo ""

#-----------------------------------------------------------
# Step 1: Create library and source physical files
#
# Uses FTP RCMD to run CL commands remotely.
# Errors are expected if objects already exist.
#-----------------------------------------------------------
echo "[1/4] Creating library and source files..."

ftp -inv "${HOST}" <<FTPEOF 2>&1 | grep -E "^[0-9]" | sed 's/^/       /'
user ${USER} ${PASS}
quote rcmd CRTLIB LIB(IRCCLIENT) TEXT('IRC Client V4R4')
quote rcmd CRTSRCPF FILE(IRCCLIENT/QCSRC) RCDLEN(112)
quote rcmd CRTSRCPF FILE(IRCCLIENT/QCLSRC) RCDLEN(112)
quote rcmd CRTSRCPF FILE(IRCCLIENT/QDDSSRC) RCDLEN(112)
quote rcmd CRTSRCPF FILE(IRCCLIENT/QCMDSRC) RCDLEN(112)
quit
FTPEOF

echo "       (Errors for existing objects are normal)"

#-----------------------------------------------------------
# Step 2: Transfer all source files
#
# The put list grows as later phases add sources.
#-----------------------------------------------------------
echo ""
echo "[2/4] Transferring source files..."

OUTPUT=$(ftp -inv "${HOST}" <<FTPEOF 2>&1
user ${USER} ${PASS}
quote site namefmt 0
cd IRCCLIENT
put ${SRCDIR}/src/build.clp QCLSRC.BUILD
put ${SRCDIR}/src/strircc.clp QCLSRC.STRIRCC
put ${SRCDIR}/src/irctest1.clp QCLSRC.IRCTEST1
put ${SRCDIR}/src/irctest2.clp QCLSRC.IRCTEST2
put ${SRCDIR}/src/strirc.cmd QCMDSRC.STRIRC
put ${SRCDIR}/src/msgbuf.pf QDDSSRC.MSGBUF
put ${SRCDIR}/src/ircsrvr.pf QDDSSRC.IRCSRVR
put ${SRCDIR}/src/ircwinr.pf QDDSSRC.IRCWINR
put ${SRCDIR}/src/ircbufm.c QCSRC.IRCBUFM
put ${SRCDIR}/src/ircsrvm.c QCSRC.IRCSRVM
put ${SRCDIR}/src/ircnetd.c QCSRC.IRCNETD
put ${SRCDIR}/src/ircfmt.c QCSRC.IRCFMT
put ${SRCDIR}/src/ircchatl.c QCSRC.IRCCHATL
put ${SRCDIR}/src/ircchatd.dspf QDDSSRC.IRCCHATD
put ${SRCDIR}/src/ircchatc.clp QCLSRC.IRCCHATC
quit
FTPEOF
)

# Count successful transfers
EXPECTED=15
OK=$(echo "$OUTPUT" | grep -c "File transfer completed successfully" || true)
TRUNC=$(echo "$OUTPUT" | grep -c "truncated" || true)

echo "       ${OK}/${EXPECTED} files transferred"
if [ "$TRUNC" -gt 0 ]; then
    echo "  !!   ${TRUNC} file(s) had truncation warnings"
    echo "$OUTPUT" | grep "truncated"
    ERRORS=1
fi

#-----------------------------------------------------------
# Step 3: Compile the BUILD program
#-----------------------------------------------------------
echo ""
echo "[3/4] Compiling build program..."

OUTPUT=$(ftp -inv "${HOST}" <<FTPEOF 2>&1
user ${USER} ${PASS}
quote rcmd CRTCLPGM PGM(IRCCLIENT/BUILD) SRCFILE(IRCCLIENT/QCLSRC) SRCMBR(BUILD)
quit
FTPEOF
)

if echo "$OUTPUT" | grep -q "250"; then
    echo "       BUILD program compiled"
else
    echo "  !!   BUILD compile failed"
    echo "$OUTPUT" | grep -E "^[0-9]"
    ERRORS=1
fi

#-----------------------------------------------------------
# Step 4: Run the build (compiles all objects)
#
# This runs synchronously via RCMD. The AS/400 FTP timeout
# is 300 seconds (5 min); plenty for the Phase 0 build.
#-----------------------------------------------------------
echo ""
echo "[4/4] Building all objects..."

OUTPUT=$(ftp -inv "${HOST}" <<FTPEOF 2>&1
user ${USER} ${PASS}
quote rcmd ADDLIBLE LIB(IRCCLIENT)
quote rcmd CALL PGM(IRCCLIENT/BUILD)
quit
FTPEOF
)

if echo "$OUTPUT" | grep -q "250.*CALL"; then
    echo "       Build completed successfully"
else
    echo "       Build may have completed (check AS/400 job log)"
    echo "       FTP response:"
    echo "$OUTPUT" | grep -E "^[0-9]" | tail -5
fi

#-----------------------------------------------------------
# Summary
#-----------------------------------------------------------
echo ""
echo "============================================"
if [ "$ERRORS" -eq 0 ]; then
    echo " Deploy complete!"
else
    echo " Deploy finished with warnings"
fi
echo "============================================"
echo ""
echo " Sign on to the AS/400 and run:"
echo ""
echo "   ADDLIBLE LIB(IRCCLIENT)"
echo "   STRIRC"
echo ""
