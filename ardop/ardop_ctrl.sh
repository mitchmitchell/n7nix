#!/bin/bash
#
# ardop_ctrl.sh
#
# start, stop & show status for ardop processes

BIN="/usr/bin"
LBIN="/usr/local/bin"
LOCAL_BIN="/home/pi/bin"

SYSTEMD_DIR="/etc/systemd/system"
FORCE_UPDATE=

# names of supported radios
RADIOLIST="ic706 ic7000 ic7300 kx2"

declare -A radio_ic706=( [rigname]="IC-706" [rignum]=311 [samplerate]=48000 [baudrate]=4800 [pttctrl]="GPIO=12" [catctrl]="" [alsa_lodriver]="-6.0" [alsa_pcm]="-26.5" )
declare -A radio_ic7000=( [rigname]="IC-7000" [rignum]=360 [samplerate]=48000 [baudrate]=19200 [pttctrl]="GPIO=12" [catctrl]="" [alsa_lodriver]="-6.0" [alsa_pcm]="-16.5" )
declare -A radio_ic7300=( [rigname]="IC-7300" [rignum]=373 [samplerate]=48000 [baudrate]=19200 [pttctrl]="/dev/ttyUSB0" [catctrl]="-c /dev/ttyUSB0" [alsa_lodriver]="-6.0" [alsa_pcm]="-16.5" )
declare -A radio_kx2=( [rigname]="K3/KX3" [rignum]=229 [samplerate]=48000 [baudrate]=19200 [pttctrl]="GPIO=12" [catctrl]="" [alsa_lodriver]="0.0" [alsa_pcm]="0.0" )

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function name_check
# Verify that the supplied radio name is in the supported list
function name_check() {
    retcode=1
    namecheck=$1
    for radio in $RADIOLIST ; do
        if [ $radio = "$namecheck" ] ; then
            return 0
        fi
    done
    return $retcode
}

# ===== function asoundfile
# Use a heredoc to build the .asoundrc file

function asoundfile() {
sudo tee $HOME/.asoundrc > /dev/null << EOT
pcm.ARDOP {
        type rate
        slave {
        pcm "hw:1,0"
        rate ${radio[samplerate]}
        }
}
EOT
}

# ===== function unitfile_rigctld
# Use a heredoc to build the rigctld.service file

function unitfile_rigctld() {
sudo tee /etc/systemd/system/rigctld.service > /dev/null << EOT
[Unit]
Description=rigctld
#Before=pat

[Service]
ExecStart=/usr/local/bin/rigctld -m ${radio[rignum]} -r /dev/ttyUSB0 -s ${radio[baudrate]}
WorkingDirectory=/home/pi/
StandardOutput=inherit
StandardError=inherit
Restart=no
User=pi

[Install]
WantedBy=multi-user.target
#WantedBy=pat
EOT
}

# ===== function unitfile_ardop
# Use a heredoc to build the ardop.service file
#
# From piardopc documentation
# -p device or --ptt device         Device to use for PTT control using RTS or GPIO Pin (Raspbery Pi only)
# -c device or --cat device         Device to use for CAT Control
# -k string or --keystring string   String (In HEX) to send to the radio to key PTT
# -u string or --unkeystring string String (In HEX) to send to the radio to unkeykey PTT

function unitfile_ardop() {
sudo tee /etc/systemd/system/ardop.service > /dev/null << EOT
[Unit]
Description=ardopc - ARDOP softmodem for pi
After=network.target sound.target

[Service]
User=pi
WorkingDirectory=/home/pi/
ExecStart=/home/pi/bin/piardopc 8515 pcm.ARDOP pcm.ARDOP ${radio[catctrl]} -p ${radio[pttctrl]}
#ExecStart=/bin/sh -c "/home/pi/bin/piardopc 8515 plughw:1,0 plughw:1,0 -p ${radio[pttctrl]} "
Restart=no

[Install]
WantedBy=multi-user.target
EOT
}

# ===== function unitfile_pat
# Use a heredoc to build the pat.service file

function unitfile_pat() {
sudo tee /etc/systemd/system/pat.service > /dev/null << EOT
[Unit]
Description=pat
#Before=network.target
Requires=rigctld
#Wants=rigctld

[Service]
User=pi
ExecStart=/usr/bin/pat http
WorkingDirectory=/home/pi/
StandardOutput=inherit
StandardError=inherit
Restart=no

[Install]
WantedBy=multi-user.target
EOT
}

# ===== function unitfile_exists
# A more general way to determine existence of a systemd service file
function unitfile_exists() {
  [ $(systemctl list-unit-files "${1}*" | wc -l) -gt 3 ]
}

# ===== function status_service

function status_service() {
    service="$1"
    IS_ENABLED="ENABLED"
    IS_RUNNING="RUNNING"
    # echo "Checking service: $service"
    systemctl is-enabled "$service" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        IS_ENABLED="NOT ENABLED"
    fi
    systemctl is-active "$service" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        IS_RUNNING="NOT RUNNING"
    fi
}

# ===== function status_all_processes
function status_all_processes() {
    for process in "rigctld" "piardopc" "pat" ; do

        pid_pat="$(pidof $process)"
        ret=$?
        # Display process: name, pid, arguments
        if [ "$ret" -eq 0 ] ; then
            args=$(ps aux | grep -i $pid_pat | grep -v "grep" | head -n 1 | tr -s '[[:space:]]' | sed -n "s/.*$process//p")
            echo "proc $process: $ret, pid: $pid_pat, args: $args"
        else
            echo "proc $process: $ret, NOT running"
        fi
    done
}

# ===== function status_all_services

function status_all_services() {
    for service in "rigctld" "ardop" "pat" ; do
        status_service
    done
}

# ===== function start_service

function start_service() {
    service="$1"
    echo "Starting service: $service"
    systemctl is-enabled "$service" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        echo "ENABLING $service"
        $SYSTEMCTL enable "$service"
        if [ "$?" -ne 0 ] ; then
            echo "Problem ENABLING $service"
        fi
    fi
    $SYSTEMCTL --no-pager start "$service"
    if [ "$?" -ne 0 ] ; then
        echo "Problem starting $service"
    fi
}

# ===== function stop_service

function stop_service() {
    service="$1"
    systemctl is-enabled "$service" > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo "DISABLING $service"
        $SYSTEMCTL disable "$service"
        if [ "$?" -ne 0 ] ; then
            echo "Problem DISABLING $service"
        fi
    else
        echo "Service: $service already disabled."
    fi
    $SYSTEMCTL stop "$service"
    if [ "$?" -ne 0 ] ; then
        echo "Problem STOPPING $service"
    fi
    echo "Service: $service now stopped."
}

# ===== function check_service

function check_service() {

    service="$1"
    if $SYSTEMCTL is-active --quiet "$service" ; then
        stop_service $service
    else
        echo "Service: $service is already stopped"
    fi
}

# ===== function kill_ardop
function kill_ardop() {
    kill_flag=$1
    echo
    echo "DEBUG: kill_ardop: kill_flag $kill_flag"
    echo

    for process in "rigctld" "piardopc" "pat" ; do

        pid_pat="$(pidof $process)"
        ret=$?
        # Display process: name, pid, arguments
        if [ "$ret" -eq 0 ] ; then
            args=$(ps aux | grep -i $pid_pat | grep -v "grep" | head -n 1 | tr -s '[[:space:]]' | sed -n "s/.*$process//p")
            echo "proc $process: $ret, pid: $pid_pat, args: $args"
        fi

        # Stop systemd services
        service="$process"
        if [ "$process" = "piardopc" ] ; then
            service="ardop"
        fi

        if $SYSTEMCTL is-active --quiet "$service" ; then
            stop_service $service
        else
            # kill ardop process
            if [ "$ret" -eq 0 ] && [ "$kill_flag" = "true" ] ; then
                echo "$process running with pid: $pid_pat, killing"
                kill $pid_pat
            fi
        fi
    done
}

# ===== function audio_device_check

function audio_device_check() {

    audio_device=$1
    if [ -z $audio_device ] ; then
        echo "Need to pass audio device name to audio_device_check()"
        return
    fi

    echo -n "  == audio device $audio_device check: "
    if [ -e "/proc/asound/$audio_device/pcm0c/sub0/status" ] ; then
        grep -i "state:\|closed" "/proc/asound/$audio_device/pcm0c/sub0/status"
    else
        echo "device status file does NOT exist"
    fi
}

# ===== function process_check

function process_check() {
    kill_flag=
    auddev="udrc"
    if [ "$1" -eq 1 ] ; then
        kill_flag=true
        echo "kill flag set"
    fi

    audio_device_check $auddev
    asoundrc_file_check

#    echo
#    echo "  === process check"
#    kill_ardop $kill_flag
}

# ===== function unitfile_update
# systemd unit file copy

function unitfile_update() {

    echo " == unit file update"

    for unit_file in "rigctld" "ardop" "pat" ; do
        case $unit_file in
            rigctld)
                unitfile_rigctld
            ;;
            ardop)
                unitfile_ardop
            ;;
            pat)
                unitfile_pat
            ;;
            *)
                echo "Do not recognize this unit file name: $unit_file"
                exit 1
            ;;
        esac
    done
    $SYSTEMCTL daemon-reload
}

# ===== function systemd unit file check
# systemd unit file exists check

function unitfile_check() {

    retcode=0
    for file in "rigctld" "ardop" "pat" ; do
        if [ ! -e "$SYSTEMD_DIR/${file}.service" ] ; then
            retcode=1
            echo "Systemd unit file: $SYSTEMD_DIR/${file}.service NOT found."
        else
            systemctl status $file >/dev/null 2>&1
            status=$?
            echo "Service: $file, status: $status"
        fi
    done
    if [ "$retcode" -eq 0 ] && [ -z "$FORCE_UPDATE" ] ; then
        echo "All systemd service files found"
    else
        echo "Creating systemd service files."
        unitfile_update
        retcode=1
    fi
    return $retcode
}

# ===== function ardop_process_status

function ardop_process_status() {
    echo " == Ardop systemctl unit file check"
    unitfile_check
    retcode=$?
#   echo "DEBUG: retcode from unitfile_check: $retcode"
    if [ "$retcode" -eq 1 ] ; then
        echo " systemctl daemon-reload"
        $SYSTEMCTL daemon-reload
    fi

    echo " == Ardop process check"
    status_all_services
    status_all_processes
    auddev="udrc"
    audio_device_check $auddev
}

# ===== function is_pulseaudio
# Determine if pulse audio is running

function is_pulseaudio() {
    pid=$(pidof pulseaudio)
    retcode="$?"
    return $retcode
}

# ===== function check for an integer

function is_num() {
    local chk=${1#[+-]};
    [ "$chk" ] && [ -z "${chk//[0-9]}" ]
}

function which_radio() {

    if [ -e "/etc/systemd/system/rigctld.service" ] ; then
        radionum=$(grep "rigctld -m" /etc/systemd/system/rigctld.service | cut -d' ' -f3)
        if is_num $radionum ; then
            dbgecho "radio number ok: $radionum"
            for array in $RADIOLIST ; do
               arrayname="radio_${array}"
               declare -n radarray=$arrayname
               #debug
               # echo "name ${radarray[rigname]}, number: ${radarray[rignum]}"
               if [ "${radarray[rignum]}" -eq "$radionum" ] ; then
                   radio_name="${radarray[rigname]}"
                   break;
               fi
            done
        else
            echo "Check rigctld unit file, not configured properly"
        fi
    else
        echo "rigctld not configured"
    fi
}

# ===== function asoundrc_file_check
function asoundrc_file_check() {

    if [[ $EUID != 0 ]] ; then
        cfgfile="$HOME/.asoundrc"
        if [ ! -e "$cfgfile" ] || [ "$FORCE_UPDATE" = "true" ] ; then
            echo "File: $cfgfile does not exist, creating"
            # create asound file
            asoundfile
        else
            grep -i "pcm.ARDOP" $cfgfile > /dev/null 2>&1
            if [ $? -ne 0 ] ; then
                echo "asoundrc_file_check: No ARDOP entry in $cfgfile"
            else
                echo "asoundrc_file_check: Found ARDOP entry in $cfgfile"
                CARDNO=$(aplay -l | grep -i udrc)

                if [ ! -z "$CARDNO" ] ; then
#                    echo "asoundrc_file_check: udrc card number line: $CARDNO"
                    CARDNO=$(echo $CARDNO | cut -d ' ' -f2 | cut -d':' -f1)
#                    echo "asoundrc_file_check: udrc is sound card #$CARDNO"
                    asound_cardno=$(grep -i pcm $cfgfile | tail -n 1 | cut -d':' -f2 | cut -d',' -f1)
                    if [ $CARDNO -ne $asound_cardno ] ; then
                        echo
                        echo " asoundrc_file_check: asound cfg device does NOT match aplay device"
                        echo
                    else
                        echo "asoundrc_file_check: asound cfg device match: sound card number: $CARDNO"
                    fi
                else
                    echo "asoundrc_file_check: No udrc sound card found."
                fi
            fi
        fi
    else
        echo
        echo " Running as root so .asoundrc file not checked"
    fi
}


# ==== ardop_file_status
# Verify ardop programs are installed

function ardop_file_status() {

    is_pulseaudio
    if [ "$?" -eq 0 ] ; then
        echo "== Pulse Audio is running with pid: $pid"
    else
        echo "Pulse Audio is NOT running"
    fi

    # Check for .asoundrc & asound.conf ALSA configuration files
    # Verify virtual sound device ARDOP
    asoundrc_file_check

    # Verify config file to define virtual devices for split channel operation
    cfgfile="/etc/asound.conf"
    if [ ! -e "$cfgfile" ] ; then
        echo "File: $cfgfile does not exist"
    else
        echo "Found file: $cfgfile for split channel operation"
    fi

    PROGLIST="piARDOP_GUI piardop2 piardopc"

    echo " == Ardop Verify required programs"

    for prog_name in `echo ${PROGLIST}` ; do
        type -P $prog_name &> /dev/null
        retcode="$?"
        if [ "$retcode" -ne 0 ] ; then
            echo "$scriptname: Need to Install $prog_name"
            NEEDPKG_FLAG=true
        else
            # Get last word of filename, break on under bar, only look at first 3 characters
            lastword=$(grep -oE '[^_]+$' <<< $prog_name | cut -c1-3)
            if [ "$lastword" != "GUI" ] ; then
                echo "Found program: $prog_name, $($prog_name -h | head -n 1)"
            else
                echo "Found program: $prog_name"
            fi
        fi
    done

    prog_name="arim"
    type -P $prog_name &> /dev/null
    if [ $? -ne 0 ] ; then
        echo "$scriptname: Need to Install $prog_name"
        NEEDPKG_FLAG=true
    else
        echo "Found program: $prog_name, version: $($prog_name -v | head -n 1)"
    fi
    prog_name="pat"
    type -P $prog_name &> /dev/null
    if [ $? -ne 0 ] ; then
        echo "$scriptname: Need to Install $prog_name"
        NEEDPKG_FLAG=true
    else
        echo "Found program: $prog_name, version: $($prog_name version)"
    fi
}

usage () {
	(
	echo "Usage: $scriptname [-f][-d][-h][status][stop][start]"
        echo "                  No args will show status of rigctld, piardopc, pat"
        echo "                  args with dashes must come before other arguments"
        echo "  start           start required ardop processes"
        echo "  stop            stop all ardop processes"
        echo "  status          display status of all ardop processes"
        echo "  -a <radio name> specify radio name (ic706 ic7000 ic7300 kx2)"
        echo "  -f | --force    Update all systemd unit files & .asoundrc file"
        echo "  -d              Set DEBUG flag"
        echo "  -h              Display this message."
        echo
	) 1>&2
	exit 1
}

# ===== main

# Check if running as root
if [[ $EUID != 0 ]] ; then
   SYSTEMCTL="sudo systemctl "
else
   SYSTEMCTL="systemctl"
fi

# draws manager collides with pat http

check_service "draws-manager"

# For now assume NOT running in split_channel mode and
#  shut down direwolf
check_service "direwolf"

if [[ $# -eq 0 ]] ; then
    APP_ARG="status"
fi

# default radio name
radioname="radio_ic706"
declare -n radio=$radioname

while [[ $# -gt 0 ]] ; do
APP_ARG="$1"

case $APP_ARG in
    -a)
        radioname=$2
        shift  # past argument

        name_check $radioname
        if [ $? -eq 1 ] ; then
            echo "Radio: $radioname NOT supported"
            exit
        fi
        radioname="radio_${radioname}"
        echo "Setting rig name to: $radioname"
        if [ ! -z "$DEBUG" ] ; then
            declare -n radio=$radioname
            echo
            echo "DEBUG: radio name: $radioname, radio: $radio"
            printf "rig ctrl baud rate: %s\n" ${radio[baudrate]}
            echo
            catctrl=${radio[catctrl]}
            if [ -z "$catctrl" ] ; then catctrl="rigctl" ; fi
            echo "== Dump radio parameters for radio: $radioname"
            for key in "${!radio[@]}"; do echo -n "$key -> ${radio[$key]}, "; done
            echo
            printf "rig number: %s, baud rate: %s, alsa sample rate: %s, ptt: %s, cat: %s, alsa pcm: %s\n" ${radio[rignum]} ${radio[baudrate]} ${radio[samplerate]} ${radio[pttctrl]} "$catctrl" "${radio[alsa_pcm]}"
        fi
        exit
    ;;
    stop)
        echo "Kill all ardopc, rigctld & pat processes"
        # temporary until everything is started with systemd
        kill_ardop true
    ;;
    start)
        for service in "rigctld" "ardop" "pat" ; do
            start_service $service
        done
    ;;
    status)
        # radio_name var is set by which_radio
        which_radio
        echo " == Status for configured rig: $radio_name"
        ardop_file_status
        ardop_process_status
        echo "Finished ardop status"
        exit 0
    ;;
    -f|--force)
        FORCE_UPDATE=true
        echo "Force update mode on"
   ;;
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

# make variable radio an alias for radioname
declare -n radio=$radioname

# radio_name var is set by which_radio
which_radio
echo
echo " == Status for configured rig: $radio_name"

process_check 0
unitfile_check
retcode=$?

#echo "DEBUG: retcode from unitfile_check: $retcode"

if [ "$retcode" -eq 1 ] ; then
    echo " systemctl daemon-reload"
    $SYSTEMCTL daemon-reload
fi

echo " == Ardop process check"
status_all_processes

echo "Finished ardop $APP_ARG"