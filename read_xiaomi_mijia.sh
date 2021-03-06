#!/bin/bash

###
#
# read_xiaomi_mijia.sh by Antti Kultanen <pyksy at pyksy dot fi>
#
# License: WTFPL
#

TRIES=5
TIMEOUT=30
ADAPTER=hci0

function show_help() {
	echo "Usage: $0 -b BLUETOOTH_MAC [-h] [-i INTERFACE] [-p] [-r RETRIES] [-s] [-t] [-w TIMEOUT]"
	echo ""
	echo "  -b A  connect to sensor at Bluetooth MAC address A"
	echo "  -h    display humidity (in %)"
	echo "  -i I  use interface I (default $ADAPTER)"
	echo "  -p    display battery level (in %)"
	echo "  -r N  try connecting N times (default $TRIES)"
	echo "  -s    display temperature, humidity and battery voltage"
	echo "  -t    display temperature (in �C)"
	echo "  -w S  wait S seconds for timeout (default $TIMEOUT)"
	echo ""
	echo "Example: $0 -b A4:C1:38:03:13:37 -s"
}


### Parse cmdline
#
while getopts "b:hi:pr:stw:" OPT
do
	case ${OPT} in
	b)
		BTADDRESS="$OPTARG"
		;;
	h)
		SHOWHUM=1
		;;
	i)
		ADAPTER="$OPTARG"
		;;
	p)
		SHOWBAT=1
		;;
	r)
		TRIES="$OPTARG"
		;;
	s)
		SHOWBAT=1
		SHOWHUM=1
		SHOWTEMP=1
		;;
	t)
		SHOWTEMP=1
		;;
	w)
		TIMEOUT="$OPTARG"
		;;
	esac
done


### Verify options
#
if [ -z "$SHOWBAT" ] && [ -z "$SHOWHUM" ] && [ -z "$SHOWTEMP" ]
then
	echo "ERROR: Nothing to do" >&2
	echo >&2
	show_help >&2
	exit 1
fi

if [ -z "$BTADDRESS" ]
then
	echo "ERROR: No sensor Bluetooth MAC address specified. (-b)" >&2
	echo >&2
	show_help >&2
	exit 1
fi

if ! [[ ${BTADDRESS^^} =~ ^([A-F0-9]{2}:){5}[A-F0-9]{2}$ ]]
then
	echo "ERROR: Invalid Bluetooth MAC address '$BTADDRESS'. (-b)"
	exit 1
fi

if ! [[ $ADAPTER =~ ^hci[0-9]+$ ]]
then
	echo "ERROR: Invalid bluetooth device name '$ADAPTER'. (-i)"
	exit 1
fi

if ! [[ $TRIES =~ ^[0-9]+$ ]]
then
	echo "ERROR: '$TRIES' is not a valid number of times to try. (-r)"
	exit 1
fi

if ! [[ $TIMEOUT =~ ^[0-9]+$ ]]
then
	echo "ERROR: '$TIMEOUT' is not a valid number of seconds to wait. (-w)"
	exit 1
fi


### Verify dependencies (gatttool)
#
if ! command -v gatttool >/dev/null
then
	echo "gatttool not found in path. Make sure Bluez is installed."
	exit 1
fi


### Verify adapter is found and up
#
if hciconfig $ADAPTER 2>&1 | grep -q -e "No such device" -e "DOWN"
then
	echo "ERROR: Device $ADAPTER is down or does not exist."
	exit 1
fi


### Read temperature and humidity from device
#
if [ -n "$SHOWTEMP" ] || [ -n "$SHOWHUM" ]
then
	TRY=0
	while [ -z "$RAWDATA" ] && [ $TRY -lt $TRIES ]
	do
		RAWDATA="$(timeout $TIMEOUT gatttool --adapter="$ADAPTER" -b "$BTADDRESS" \
			--char-write-req --handle=0x0038 --value=0100 --listen \
			| grep "Notification handle" -m 1 | cut -d : -f 2-)"
		((TRY++))
	done

	if [ $TRY -eq $TRIES ]
	then
		echo "ERROR: Failed after $TRIES retries" >&2
		exit 1
	fi

	TEMP="$(awk '{ printf("ibase=16; %s%s\n",$2,$1); }' <<<"${RAWDATA^^}" | bc)"
	TEMP="${TEMP:0:2}.${TEMP:2:2}"
	HUM="$(awk '{ printf("ibase=16; %s\n",$3); }' <<<"${RAWDATA^^}" | bc)"
fi
unset RAWDATA


### Read battery percentage from device
#
if [ -n "$SHOWBAT" ]
then
	TRY=0
	while [ -z "$RAWDATA" ] && [ $TRY -lt $TRIES ]
	do
		RAWDATA="$(timeout $TIMEOUT gatttool --adapter="$ADAPTER" -b "$BTADDRESS" \
			--char-read --uuid 0x2a19 --listen | cut -d : -f 3)"
		((TRY++))
	done

	        if [ $TRY -eq $TRIES ]
        then
                echo "ERROR: Failed after $TRIES retries" >&2
                exit 1
        fi

	BAT="$(awk '{ printf("ibase=16; %s\n",$1); }' <<<"${RAWDATA^^}" | bc)"
fi


### Display data
#
if [ -n "$SHOWTEMP" ]
then
	echo -n "$TEMP "
fi
if [ -n "$SHOWHUM" ]
then
	echo -n "$HUM "
fi
if [ -n "$SHOWBAT" ]
then
	echo -n "$BAT "
fi
echo
