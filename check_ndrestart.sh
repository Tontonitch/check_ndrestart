#!/bin/bash
#set -x
# ========================================================================================
# Needs-restarting for Nagios
#
# Written by    : Yannick Charton
# Description   : Nagios plugin (script) to if the system needs to be restarted or if some
#                 processes/services need to be restarted following some package updates.
#
# Usage         : ./check_ndrestart.sh [-e service_to_exclude] [-e service_to_exclude]"
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
#       1.1.4   |    16.02.26   | Y. Charton    | Added RockyLinux as supported distribution
# --------------+---------------+---------------+------------------------------------------
#       1.1.3   |    13.02.26   | Y. Charton    | Added the "new" possible LSBR_DISTRIB 
#               |               |               | variable value for RHEL
# --------------+---------------+---------------+------------------------------------------
#       1.1.2   |    22.10.18   | N. Lafont     | Add XCP-ng / XenServer support,
#               |               |               | fix error message, multiple dot version
# --------------+---------------+---------------+------------------------------------------
#       1.1.1   |    20.08.18   | Y. Charton    | Add Fedora support, requirement check,
#               |               |               | fix error code
# --------------+---------------+---------------+------------------------------------------
#       1.1     |    10.01.18   | Y. Charton    | Exclude list
# --------------+---------------+---------------+------------------------------------------
#       1.0     |    08.05.17   | Y. Charton    | Initial release
# --------------+---------------+---------------+------------------------------------------
# 
# Notes: needs-restarting can produce false-positive reports for applications behaving "abnormally"
#        see https://access.redhat.com/solutions/3317951 for an Oracle Clusterware process case
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
RELEASE="Revision 1.1.4"
AUTHOR="by Yannick Charton"

# Other variables
EXCLUDE=""
NEEDREBOOT=""
RC_NEEDREBOOT=0
NEEDSRVRESTART=""

if [ ! $(rpm -q yum-utils) ]; then
        echo "UNKNOWN: the required package yum-utils is not installed on this system".
        exit $STATE_UNKNOWN
fi

if [ ! $(rpm -q redhat-lsb-core) ]; then
        echo "UNKNOWN: the required package redhat-lsb-core is not installed on this system".
        exit $STATE_UNKNOWN
fi

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
    echo "Usage: check_ndrestart.sh [-e service_to_exclude] [-e service_to_exclude]"
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

# Parse parameters
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            print_help
            exit $STATE_OK
            ;;
        -v | --version)
            print_release
            exit $STATE_OK
            ;;
        -e | --exclude)
            shift
            if [ -n "${EXCLUDE}" ]; then EXCLUDE="${EXCLUDE}|"; fi
                        EXCLUDE="${EXCLUDE}$1"
            ;;
        *)  echo "Unknown argument: $1"
            print_usage
            exit $STATE_UNKNOWN
            ;;
    esac
shift
done


# Distrib dependent commands
case `uname` in
        Linux ) LSBR_DISTRID=`lsb_release -i -s`
                LSBR_DISTRRN=`lsb_release -r -s | cut -d '.' -f 1-2`
            ;;
        *)      echo "UNKNOWN: `uname` not yet supported by this plugin. Coming soon !"
                exit $STATE_UNKNOWN
            ;;
esac


case $LSBR_DISTRID in
    RedHatEnterpriseServer | RedHatEnterprise | CentOS | RockyLinux)
        if [ $(bc <<< "$LSBR_DISTRRN >= 7.3") -ne 0 ]; then
            NEEDREBOOT=$(needs-restarting -r 2>&1)
            RC_NEEDREBOOT=$?

            if [ -n "${EXCLUDE}" ]; then
                NEEDSRVRESTART=$(sudo needs-restarting -s 2>&1 | egrep -v "${EXCLUDE}")
                        else
                NEEDSRVRESTART=$(sudo needs-restarting -s 2>&1)
            fi

        else
            if [ -n "${EXCLUDE}" ]; then
                NEEDSRVRESTART=$(sudo needs-restarting 2>&1 | egrep -v "${EXCLUDE}")
                        else
                NEEDSRVRESTART=$(sudo needs-restarting 2>&1)
            fi
        fi
        ;;
    XCP-ng | XenServer)
        if [ -n "${EXCLUDE}" ]; then
            NEEDSRVRESTART=$(sudo needs-restarting 2>&1 | egrep -v "${EXCLUDE}")
        else
            NEEDSRVRESTART=$(sudo needs-restarting 2>&1)
        fi
        ;;
    Fedora)
        if [ $(bc <<< "$LSBR_DISTRRN >= 28") -ne 0 ]; then
            NEEDREBOOT=$(needs-restarting -r 2>&1)
            RC_NEEDREBOOT=$?

            if [ -n "${EXCLUDE}" ]; then
                NEEDSRVRESTART=$(sudo needs-restarting -s 2>&1 | egrep -v "${EXCLUDE}")
                        else
                NEEDSRVRESTART=$(sudo needs-restarting -s 2>&1)
            fi

        else
            if [ -n "${EXCLUDE}" ]; then
                NEEDSRVRESTART=$(sudo needs-restarting 2>&1 | egrep -v "${EXCLUDE}")
                        else
                NEEDSRVRESTART=$(sudo needs-restarting 2>&1)
            fi
        fi
        ;;
    *)
      echo "UNKNOWN: $LSBR_DISTRID not yet supported by this plugin. Coming soon !"
      exit $STATE_UNKNOWN
      ;;
esac

if [ "${RC_NEEDREBOOT}" != "0" ]; then
    MSG_WARN="${MSG_WARN} Core libraries or services have been updated, reboot is required."
    EXTRA_WARN="${EXTRA_WARN}
$NEEDREBOOT"
    STATUS=$STATE_WARNING
fi

if [ -n  "${NEEDSRVRESTART}" ]; then
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
