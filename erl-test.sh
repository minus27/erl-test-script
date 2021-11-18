#!/usr/bin/env bash
exitOnError() { # $1=ErrorMessage $2=PrintUsageFlag
	local TMP="$(echo "$0" | sed -E 's#^.*/##')"
	local REQ_ARGS="$(grep -e "#REQUIRED[=]" $0)"
	local OPT_ARGS="$(grep -e "#OPTIONAL[=]" $0)"
	[ "$1" != "" ] && >&2 echo "ERROR: $1"
	[[ "$1" != "" && "$2" != "" ]] && >&2 echo ""
	[ "$2" != "" ] && {
		>&2 echo -e "USAGE: ${TMP}$([[ "${REQ_ARGS}" != "" ]] && echo " [REQUIRED_ARGUMENTS]")$([[ "${OPT_ARGS}" != "" ]] && echo " [OPTIONAL_ARGUMENTS]")"
		[[ "${REQ_ARGS}" != "" ]] && {
			>&2 echo -e "\nREQUIRED ARGUMENTS:"
			>&2 echo -e "$(echo "${REQ_ARGS}" | sed -E -e 's/\|/ | /' -e 's/^[^-]*/  /g' -e 's/\)//' -e 's/#[^=]*=/: /')"
		}
		[[ "${OPT_ARGS}" != "" ]] && {
			>&2 echo -e "\nOPTIONAL ARGUMENTS:"
			>&2 echo -e "$(echo "${OPT_ARGS}" | sed -E -e 's/\|/ | /' -e 's/^[^-]*/  /g' -e 's/\)//' -e 's/#[^=]*=/: /')"
		}
	}
	exit 1
}
toolCheck() {
	type -P curl >/dev/null 2>&1 || exitOnError "\"curl\" required and not found"
	type -P vegeta >/dev/null 2>&1 || exitOnError "\"vegeta\" required and not found"
}
log() { # $1=msg
	echo "$1" >> "${LOG_FILE}"
	[[ "${DEBUG}" != "" ]] && >&2 echo "$1"
}
checkIntegerValue() { #$1=NAME, $2=VALUE, $3=MIN, $4=MAX 
	[[ "$2" != "0" && ! "$2" =~ ^[1-9]+[0-9]*$ ]] && exitOnError "$1 value must be an integer"
	[[ "$3" != "" ]] && {
		[[ $2 -lt $3 ]] && exitOnError "$1 value cannot be less than $3"
	}
	[[ "$4" != "" ]] && {
		[[ $2 -gt $4 ]] && exitOnError "$1 value cannot be greater than $4"
	}
}
dumpVars() { # $1=TITLE 
	local TITLE="$1"
	shift
	log "${TITLE}: $#"
	for NAME in "$@"
	do
		log "  ${NAME}: \"${!NAME}\""
	done
}
getArgs() {
	POSITIONAL=()
	# Defaults:
	VA_RATE=1
	VA_DURATION="1s"
	VA_TARGET_METHOD="GET"
	VA_TARGET_URL=""
	VA_REPORT_INTERVAL="1s"
	DELAY_WINDOW=""
	DELAY_START=0
	LOG="1"
	#
	while [[ $# -gt 0 ]]
	do
		key="$(echo "[$1]" | tr '[:upper:]' '[:lower:]' | sed -e 's/^\[//' -e 's/\]$//')"
		case "$key" in
			-r|--attack_rate) #OPTIONAL=Vegeta Attack Rate RPS
				checkIntegerValue "Vegeta Attack Rate" "$2"
				VA_RATE="$2"
				shift; shift
				;;
			-d|--attack_duration) #OPTIONAL=Vegeta Attack Duration seconds
				#checkIntegerValue "Vegeta Attack Duration" "$2"
				VA_DURATION="$2"
				shift; shift
				;;
			-m|--attack_target_method) #OPTIONAL=Vegeta Attack Target Method
				VA_TARGET_METHOD="$2"
				shift; shift
				;;
			-t|--attack_target_url) #OPTIONAL=Vegeta Attack Target URL
				VA_TARGET_URL="$2"
				shift; shift
				;;
			-i|--attack_report_interval) #OPTIONAL=Vegeta Attack Report Interval
				VA_REPORT_INTERVAL="$2"
				shift; shift
				;;
			-u|--user-agent) #OPTIONAL=Vegeta Attack User-Agent
				VA_UA_SET=1
				VA_UA="$2"
				shift; shift
				;;
			-f|--output_file_name) #OPTIONAL=Output File Name - Default=SCRIPT_NAME.out
				[[ "$2" == "" ]] && exitOnError "Output File Name cannot be an empty string"
				OF_NAME="$2"
				shift; shift
				;;
			-l|--log) #OPTIONAL=Log information to file
				checkIntegerValue "Log information to file" "$2" "0" "1"
				LOG="$2"
				shift; shift
				;;
			-w|--delay-window) #OPTIONAL=Delay Window (1/10/60)
				[[ "$2" =~ ^(1|[16]0)$ ]] || exitOnError "Unexpected Delay Window, i.e. not 1/10/60"
				DELAY_WINDOW="$2"
				shift; shift
				;;
			-s|--delay-start) #OPTIONAL=Delay Start (0 <= DELAY_START < DELAY_WINDOW)
				checkIntegerValue "Delay Start" "$2" "0"
				[[ $2 -ge $DELAY_WINDOW ]] && exitOnError "Delay Start value must be less than Delay Window ($DELAY_WINDOW)"
				DELAY_START="$2"
				shift; shift
				;;
			-x|--exit) #OPTIONAL=Process arguments and exit
				EXIT="1"
				shift
				;;
			--debug) #HIDDEN_OPTION
				{DEBUG}="1"
				shift
				;;
			*)
				[[ "$1" =~ ^- ]] && exitOnError "Unexpected argument - \"$1\"" "1"
				POSITIONAL+=("$1")
				shift
				;;
		esac
	done
	# Checks:
	[[ "${#POSITIONAL[@]}" -ne 0 ]] &&  exitOnError "No positional arguments expected, ${#POSITIONAL[@]} found" "1"

	REQ_ARGS=(VA_TARGET_URL)
	OPT_ARGS=(VA_RATE VA_DURATION VA_TARGET_METHOD VA_TARGET_URL VA_REPORT_INTERVAL OF_NAME LOG)
	for NAME in "${REQ_ARGS[@]}"
	do
		[[ "${!NAME}" == "" ]] && exitOnError "Value for ${NAME} required"
	done

	[[ "${VA_UA}" == "" ]] && {
		getVegetaUserAgent
	}

	[[ "${LOG}" != "" || "${EXIT}" != "" ]] && {
		dumpVars "Required Arguments" "${REQ_ARGS[@]}"
		dumpVars "Optional Arguments" "${OPT_ARGS[@]}"
		[[ "${EXIT}" != "" ]] && exit 1
	}
}
delayStart() { # $1=WIN_LEN, $2=WIN_SEC, $3=PREFIX
	local WIN_LEN="$1"; local WIN_SEC="$2"; local MSG_LBL="Time to start: "; local LAST_MSG; local NEW_MSG
	MSG_LBL="$3$MSG_LBL"
	[[ ! "$WIN_LEN" =~ ^[0-9]+$ ]] && exitOnError "WINDOW_LENGTH must be a positive integer"
	[[ ! "$WIN_SEC" =~ ^[0-9]+$ ]] && exitOnError "WINDOW_START must be a positive integer"
	[[ "$WIN_SEC" -ge $WIN_LEN ]] && exitOnError "WINDOW_START must be less than WINDOW_LENGTH"
	local NOW_MS="$(ruby -e 'printf("%.6f",Time.now.to_f)')"
	local NOW="$(echo $NOW_MS  | sed 's/\..*//')"
	local START="$((NOW/WIN_LEN*WIN_LEN + WIN_SEC))"
	[[ "$(echo "$START > $NOW_MS" | bc -l)" -eq 0 ]] && START="$(echo "$START + $WIN_LEN" | bc)"
	while [[ "$(echo "$START < $NOW_MS" | bc -l)" -eq 0 ]]; do
		local WAIT="$(( START - $(echo $NOW_MS  | sed 's/\..*//') ))"
		NEW_MSG="$(printf '%s%02d:%02d:%02d' "$MSG_LBL" "$((WAIT / 3600))" "$(((WAIT / 60) % 3600))" "$((WAIT % 60))")"
		[[ "$NEW_MSG" != "$LAST_MSG" ]] && {
			printf "$(echo "$LAST_MSG" | sed 's/./ /g')\r"
			echo -n "$NEW_MSG"
			LAST_MSG="$NEW_MSG"
		}
		sleep 0.05
		NOW_MS="$(ruby -e 'printf("%.6f",Time.now.to_f)')"
	done
	[[ "$LAST_MSG" != "" ]] && printf "\r$(echo "$LAST_MSG" | sed 's/./ /g')\r"
}
getVegetaUserAgent() {
	let TMP
	TMP="$(echo "GET https://ua.demotool.site" | vegeta attack  -rate=1 -duration=1s | vegeta encode)"
	VA_UA="$(echo "${TMP}" | grep -oE "\"X-User-Agent\":\[\".*?\"\]" | sed -E 's/^.*:\["(.*)"\]$/\1/')"
}
runVegetaAttack() {
	VEGETA_ATTACK_ARGS=(-rate=${VA_RATE} -duration=${VA_DURATION})
	[[ "${VA_UA_SET}" != "" ]] && VEGETA_ATTACK_ARGS+=(-header="user-agent: $VA_UA")
	echo "${VA_TARGET_METHOD} ${VA_TARGET_URL}" | vegeta attack "${VEGETA_ATTACK_ARGS[@]}" | vegeta encode | tee "${OUT_FILE}" | vegeta report -every="${VA_REPORT_INTERVAL}" | ./colorReport.sh
}

#
#
#
toolCheck
LOG_FILE="$(echo "$0" | sed -E 's/\.[^.]+$//').log"
rm -f $LOG_FILE
getArgs "$@"
[[ "${OF_NAME}" != "" ]] && OUT_FILE="${OF_NAME}.out" || OUT_FILE="$(echo "$0" | sed -E 's/\.[^.]+$//').out"
rm -f $OUT_FILE

IP="$(curl -s https://ip.demotool.site)"
[[ "$DELAY_WINDOW" != "" ]] && delayStart "$DELAY_WINDOW" "$DELAY_START" #"${TEST_INFO} - "
runVegetaAttack
