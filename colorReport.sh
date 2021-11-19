#!/usr/bin/env bash
while IFS='$\n' read -r LINE; do
	[[ "${LINE}" =~ ^Duration ]] && {
		TIME="$(echo "${LINE}" | sed -E 's/^Duration *\[[^]]*\] *([^,]+),.*$/\1/')"
		[[ "${TIME}" =~ [µm]s$ ]] && TIME=0
		TIME="$(echo "${TIME}" | sed -E "s/\..*$//")"
		continue
	}
	[[ "${LINE}" =~ ^Status[[:space:]]Codes ]] && {
		CODES="$(echo "${LINE}" | grep -oE "\d+:\d+")"
		FG_COLOR=0
		echo -n "$(tput bold)${TIME}:$(tput sgr0)"
		while IFS= read -r CODE; do
			STATUS="$(echo "${CODE}" | sed 's/:.*$//')"
			case "$STATUS" in
				0)
					BG_COLOR=3
					;;
				200)
					BG_COLOR=2
					;;
				429)
					BG_COLOR=1
					;;
				*)
					;;
			esac
			echo -n " $(tput setab $BG_COLOR)$(tput setaf $FG_COLOR)${CODE}$(tput sgr0)"
		done <<< "${CODES}"
		echo
	}
done
