#!/bin/bash
#
# iptable-check.sh
#
# Verify that iptables has been configured for AX.25 operation
# If iptables has not been configured then add some rules to the tables

DEBUG=
SU=
scriptname="`basename $0`"

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function get_user

function get_user() {
   # Check if there is only a single user on this system
   if (( `ls /home | wc -l` == 1 )) ; then
      USER=$(ls /home)
   else
      echo -n "Enter user name ($(echo $USERLIST | tr '\n' ' ')), followed by [enter]"
      read -ep ": " USER
   fi
}

# ==== function check_user
# verify user name is legit

function check_user() {
   userok=false
   dbgecho "$scriptname: Verify user name: $USER"
   for username in $USERLIST ; do
      if [ "$USER" = "$username" ] ; then
         userok=true;
      fi
   done

   if [ "$userok" = "false" ] ; then
      echo "User name ($USER) does not exist,  must be one of: $USERLIST"
      exit 1
   fi

   dbgecho "using USER: $USER"
}

# ===== function usage

function usage() {
    echo "Usage: $scriptname [-d][-h]" >&2
    echo "   -d        set debug flag"
    echo "   -h        display this message"
    echo
}

#
# ===== main
#

while [[ $# -gt 0 ]] ; do
APP_ARG="$1"

case $APP_ARG in

   -d|--debug)
      DEBUG=1
      echo "Debug mode on"
   ;;
   -h|--help|-?)
      usage
      exit 0
   ;;
   *)
       echo "Unrecognized command line argument: $APP_ARG"
       usage
       exit 0
   ;;

esac

shift # past argument
done

# Get list of users with home directories
USERLIST="$(ls /home)"
USERLIST="$(echo $USERLIST | tr '\n' ' ')"

# Be sure we're running as root
if [[ $EUID != 0 ]] ; then
    echo "set sudo"
    SU="sudo"
    USER=$(whoami)
else
    get_user
    check_user
fi
BIN_DIR="/home/$USER/bin"

echo "== List current iptables rules"
# List iptables rules
#
# -L list: List all rules in all chains
# -v verbose output
# -n numeric: IP addresses & port numbers are printed in numeric format
# -x exact: display exact value of the packet & byte counters instead
#    of rounded number
$SU iptables -L -nvx


rule_count=0
if [ -e "/etc/iptables/rules.ipv4.ax25" ] ; then
    rule_count=$(grep -c "\-A OUTPUT" /etc/iptables/rules.ipv4.ax25)
fi
echo
echo "Number of ax25 iptables rules found: $rule_count"

# Check for required iptables files
#
CREATE_IPTABLES=false
IPTABLES_FILES="/etc/iptables/rules.ipv4.ax25 /lib/dhcpcd/dhcpcd-hooks/70-ipv4.ax25"
for ipt_file in `echo ${IPTABLES_FILES}` ; do

   if [ -f $ipt_file ] ; then
      echo "iptables file: $ipt_file exists"
   else
      echo "Creating iptables file: $ipt_file"
      CREATE_IPTABLES=true
   fi
done

if [ -e "/etc/iptables/rules.ipv4.ax25" ] && [ $rule_count -lt 6 ] ; then
    dbgecho "Will create iptables rules due to rule count: $rule_count"
    CREATE_IPTABLES=true
fi

if [ "$CREATE_IPTABLES" = "true" ] ; then

    sudo /bin/bash $BIN_DIR/iptable-flush.sh

    # Setup some iptable rules
    # 224.0.0.22
    #  - used for the IGMPv3 protocol.
    # 239.255.255.250:1900
    #  - Chromecast
    #  - traffic is discovery multicast traffic that occurs every 2 minutes from the system
    #  - UPnP (Universal Plug and Play)/SSDP (Simple Service Discovery Protocol) by various vendors to advertise the capabilities of (or discover) devices
    echo
    echo "== setup iptables"
    sudo /bin/bash $BIN_DIR/iptable-up.sh
    sudo sh -c "iptables-save > /etc/iptables/rules.ipv4.ax25"

    grep -q "iptables-restore" /lib/dhcpcd/dhcpcd-hooks/70-ipv4.ax25 > /dev/null 2>&1
    retcode="$?"
    if [ "$retcode" -ne 0 ] ; then
        echo "Setup restore command"
        sudo tee /lib/dhcpcd/dhcpcd-hooks/70-ipv4.ax25 > /dev/null <<EOF
iptables-restore < /etc/iptables/rules.ipv4.ax25
EOF
    fi
    rule_count=$(grep -c "\-A OUTPUT" /etc/iptables/rules.ipv4.ax25)
    echo "Number of ax25 rules now: $rule_count"
fi

if [ ! -z "$DEBUG" ] ; then
    IPTABLES_FILES="/etc/iptables/rules.ipv4.ax25 /lib/dhcpcd/dhcpcd-hooks/70-ipv4.ax25"
    for ipt_file in `echo ${IPTABLES_FILES}` ; do
        echo
        echo "== Dump file: $ipt_file"
        cat $ipt_file
    done
fi
