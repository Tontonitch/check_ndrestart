#!/bin/bash
#set -x
# ========================================================================================
# System/services restart need check plugin for Nagios/Icinga
#
# Written by    : Yannick Charton
# Release       : 1.0
# Creation date : 8 May 2017
# Description   : Nagios plugin (script) to if the system needs to be restarted or if some 
#               processes/services need to be restarted following some package updates.
#
# Usage         : ./check_ndrestart.sh
#
# Installation  : some sudo settings need to be configured. Add a file /etc/sudoers.d/check_ndrestart
#                 containing:
#                  Defaults:icinga   !requiretty
#                  icinga ALL=(root) NOPASSWD: /usr/bin/needs-restarting
#
# ========================================================================================
#
# HISTORY :
#     Release   |     Date      |    Authors    |       Description
# --------------+---------------+---------------+------------------------------------------
#       1.0     |    08.05.17   | Y. Charton    | Initial release
# --------------+---------------+---------------+------------------------------------------
#
# =========================================================================================

# Paths to commands used in this script.  These may have to be modified to match your system setup.
LSBRELEASE=/usr/bin/lsb_release

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATUS=$STATE_OK

# Plugin variable description
PROGNAME=$(basename $0)
RELEASE="Revision 1.0"
AUTHOR="by Yannick Charton"

if [ ! -x $LSBRELEASE ]; then
        echo "UNKNOWN: lsb_release not found or is not executable by the nagios/icinga user."
        exit $STATE_UNKNOWN
fi

# Functions plugin usage
print_release() {
    echo "$RELEASE $AUTHOR"
}

print_usage() {
    echo ""
    echo "$PROGNAME $RELEASE - Nagios plugin (script) to if the system needs to be restarted"
	echo "or if some processes/services need to be restarted following some package updates."
    echo ""
    echo "Usage: check_ndrestart.sh"
    echo ""
    echo "Usage: $PROGNAME"
    echo "Usage: $PROGNAME --help"
    echo ""
}

print_help() {
        print_usage
        echo ""
        echo "This plugin will check if the system needs to be restarted or if some"
	    echo "processes/services need to be restarted following some package updates."
        echo ""
        exit 0
}

# 
case `uname` in
        Linux ) LSBR_DISTRID=`lsb_release -i -s`
                LSBR_DISTRRN=`lsb_release -r -s`
            ;;
        *)      echo "UNKNOWN: `uname` not yet supported by this plugin. Coming soon !"
                exit $STATE_UNKNOWN
            ;;
esac

NEEDREBOOT=""
RC_NEEDREBOOT=0
NEEDSRVRESTART=""
RC_NEEDSRVRESTART=0

case $LSBR_DISTRID in
    RedHatEnterpriseServer | CentOS) 
	  if [ $(bc <<< "$LSBR_DISTRRN >= 7.3") -ne 0 ]; then 
	    NEEDREBOOT=$(needs-restarting -r 2>&1)
		RC_NEEDREBOOT=$?
		NEEDSRVRESTART=$(sudo needs-restarting -s 2>&1)
		[ "$(echo $NEEDSRVRESTART)" != "" ] && RC_NEEDSRVRESTART=1
      else
	    NEEDSRVRESTART=$(sudo needs-restarting 2>&1)
		RC_NEEDSRVRESTART=$?
      fi
	  ;;
    *)
      echo "UNKNOWN: `uname` not yet supported by this plugin. Coming soon !"
      exit $STATE_UNKNOWN
      ;;
esac		

if [ "${RC_NEEDREBOOT}" != "0" ]; then
        MSG_WARN="${MSG_WARN} Core libraries or services have been updated, reboot is required."
		EXTRA_WARN="${EXTRA_WARN}
$NEEDREBOOT"
		STATUS=$STATE_WARNING
fi

if [ "${RC_NEEDSRVRESTART}" != "0" ]; then
        MSG_WARN="${MSG_WARN} Some services need to be restarted."
		EXTRA_WARN="${EXTRA_WARN}
Services that need to be restarted:
${NEEDSRVRESTART}"
		STATUS=$STATE_WARNING
fi

if [ $STATUS -eq 1 ]; then
    echo "WARNING: ${MSG_WARN}|${EXTRA_WARN}"
else
    echo "OK: No processes need to be restarted, no reboot required";
fi
exit $STATUS
