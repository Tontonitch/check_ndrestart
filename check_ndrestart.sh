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
#       1.2     |    16.02.26   | A. Koulouktsis| Various changes, binaries detection, 
#               |               | Y. Charton    | removed package detection as distrib dependent
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

# --- 1. VARIABLES ---

# Find lsb_release (handles different paths across RHEL versions)
LSBRELEASE=$(command -v lsb_release)

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATUS=$STATE_OK

# Plugin variable description
PROGNAME=$(basename $0)
RELEASE="Revision 1.2"
AUTHOR="by Yannick Charton, N. Lafont, A. Koulouktsis"

# Other variables
EXCLUDE=""
NEEDREBOOT=""
RC_NEEDREBOOT=0
NEEDSRVRESTART=""

# --- 2. REQUIREMENT CHECKS ---

# Check for lsb_release binary
if [ -z "$LSBRELEASE" ] || [ ! -x "$LSBRELEASE" ]; then
    echo "UNKNOWN: lsb_release not found or is not executable by the nagios/icinga user."
    exit $STATE_UNKNOWN
fi

# Check for bc (required for version math)
if ! command -v bc >/dev/null 2>&1; then
    echo "UNKNOWN: 'bc' command not found. Please install the 'bc' package."
    exit $STATE_UNKNOWN
fi

# --- 3. FUNCTIONS ---

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

# --- 4. PARAMETER PARSING ---

# Parse parameters
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            print_usage
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

# --- 5. OS RELEASE DETECTION ---

# Distrib dependent commands
case `uname` in
        Linux ) LSBR_DISTRID=`lsb_release -i -s`
                # Get major.minor version
				LSBR_DISTRRN=`lsb_release -r -s | cut -d '.' -f 1-2`
            ;;
        *)      echo "UNKNOWN: `uname` not yet supported by this plugin. Coming soon !"
                exit $STATE_UNKNOWN
            ;;
esac

# --- 6. EXECUTION LOGIC ---

case $LSBR_DISTRID in
    RedHatEnterpriseServer | RedHatEnterprise | CentOS | Rocky | RockyLinux)
        # Check if version is 7.3 or higher for the '-r' (reboot) flag support
        if [ $(bc <<< "$LSBR_DISTRRN >= 7.3") -ne 0 ]; then
            # Check if a full reboot is required
            NEEDREBOOT=$(needs-restarting -r 2>&1)
            RC_NEEDREBOOT=$?

            # Check which specific services need a restart
            if [ -n "${EXCLUDE}" ]; then
                NEEDSRVRESTART=$(sudo needs-restarting -s 2>&1 | egrep -vE "${EXCLUDE}")
                        else
                NEEDSRVRESTART=$(sudo needs-restarting -s 2>&1)
            fi

        else
            # Older RHEL/CentOS 6/7.x logic (pre 7.3)
            if [ -n "${EXCLUDE}" ]; then
                NEEDSRVRESTART=$(sudo needs-restarting 2>&1 | egrep -vE "${EXCLUDE}")
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
      echo "UNKNOWN: Linux distribution '$LSBR_DISTRID' not yet supported by this plugin."
      exit $STATE_UNKNOWN
      ;;
esac

# --- 7. OUTPUT GENERATION ---

# Filter out Subscription Manager noise if it exists in the output
NEEDREBOOT=$(echo "$NEEDREBOOT" | grep -v "Subscription Management")
NEEDSRVRESTART=$(echo "$NEEDSRVRESTART" | grep -v "Subscription Management")

if [ "${RC_NEEDREBOOT}" != "0" ]; then
    MSG_WARN="${MSG_WARN} Core libraries or services have been updated, reboot is required."
    EXTRA_WARN="${EXTRA_WARN}\n--- Reboot Required ---\n$NEEDREBOOT"
    STATUS=$STATE_WARNING
fi

if [ -n "${NEEDSRVRESTART}" ] && [[ ! "${NEEDSRVRESTART}" =~ "No processes" ]]; then
    MSG_WARN="${MSG_WARN} Services need restart."
    EXTRA_WARN="${EXTRA_WARN}\n--- Services to restart ---\n${NEEDSRVRESTART}"
    STATUS=$STATE_WARNING
fi

if [ $STATUS -eq 1 ]; then
    # Clean up leading spaces and print
    MSG_WARN=$(echo $MSG_WARN | xargs)
    echo -e "WARNING: ${MSG_WARN} | ${EXTRA_WARN}"
else
    echo "OK: No processes need to be restarted, no reboot required";
fi

exit $STATUS
