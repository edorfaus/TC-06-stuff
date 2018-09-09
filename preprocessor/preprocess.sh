#!/bin/bash

# -------- START: GLOBALS --------

# None of these variables should be used as names for local variables, as some
# functions directly or indirectly rely on being able to access these globals.

# Regular expression for matching an identifier (label, overlay name, etc.).
# An identifier must start with a ASCII letter or underscore, and can only
# contain ASCII letters, underscores and digits.
# Note: Can't use ranges here, as they're locale-dependent, which is bad.
identifierRegex="abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOPQRSTUVWXYZ"
identifierRegex="[$identifierRegex][${identifierRegex}0123456789]*"

# Used to hold the list of overlays, with info about each.
declare -A overlayList
# Used to hold the addresses at which the current overlay changes.
declare -a overlaySwitch

# Used to hold the list of labels, with info about each.
labels=" "

# Used to hold the text of the program being preprocessed.
program=

# -------- END: GLOBALS --------

# -------- START: OVERLAY HANDLING --------

# Get the disk address of the overlay with the given identifier.
# The address will be stored in the $overlayAddress variable.
# Returns 0 if the overlay was found, 1 otherwise.
# getOverlayAddress <identifier>
getOverlayAddress() {
	overlayAddress=${overlayList["$1"]}
	[[ "$overlayAddress" == "" ]] && return 1
	return 0
}

# Add a new overlay, with the given identifier and disk address.
# Returns 0 if the overlay was added, or 1 on error (e.g. duplicate overlay).
# addOverlay <identifier> <address>
addOverlay() {
	if [[ "${overlayList["$1"]}" != "" ]];
	then
		printf >&2 "Error: Duplicate overlay: %s at %s and %s\n" \
			"$1" "${overlayList["$1"]}" "$2"
		return 1
	fi
	overlayList["$1"]=$2
	overlaySwitch[$2]="$1"
	return 0
}

# Ends an overlay at the given disk address.
# endOverlay <address>
endOverlay() {
	overlaySwitch[$1]=
}

# Change the current overlay if the given address is an overlay switch point.
# This will set the $currentOverlay variable to either the same value as
# before, or to the new value, depending on the given address.
# switchCurrentOverlay <address>
switchCurrentOverlay() {
	currentOverlay=${overlaySwitch[$1]-$currentOverlay}
}

# -------- END: OVERLAY HANDLING --------

# -------- START: LABEL HANDLING --------

# Get the disk address of the given label, in the $labelAddress variable.
# If in-overlay is given, then it only finds labels local to that overlay,
# otherwise it finds the first label with that name regardless of overlay, and
# warns if there's more than one match.
# Returns 0 if a label was found, 1 otherwise.
# getLabelAddress <label> [in-overlay]
getLabelAddress() {
	if [[ "$labels" =~ " $1="([0123456789]+)":${2+$2 }"(.*) ]]; then
		labelAddress=${BASH_REMATCH[1]}
		if [ $# -lt 2 ] && [[ "${BASH_REMATCH[2]}" =~ " $1=" ]]; then
			printf >&2 "Warning: Multiple matches found for label %s\n" "$1"
		fi
		return 0
	fi
	return 1
}

# Get the overlay that the given label, with the given address, is in.
# If the label was found, the overlay identifier is put in the $labelOverlay
# variable, and 0 is returned. Otherwise, 1 is returned.
# getLabelOverlay <label> <address>
getLabelOverlay() {
	if [[ "$labels" =~ " $1=$2:"([^ ]*)" " ]]; then
		labelOverlay=${BASH_REMATCH[1]}
		return 0
	fi
	return 1
}

# Add the given label, with the given disk address, for the given overlay.
# Returns 0 if the label was added, or 1 on error (e.g. duplicate label).
# addLabel <label-identifier> <address> <overlay-identifier>
addLabel() {
	local labelAddress
	if getLabelAddress "$1" "$3"
	then
		printf >&2 "Error: Duplicate label: %s at %s and %s in overlay %s\n" \
			"$1" "$labelAddress" "$2" "$3"
		return 1
	fi
	labels+="$1=$2:$3 "
	return 0
}

# -------- END: LABEL HANDLING --------

# -------- START: PROGRAM TEXT HANDLING --------

# Add a line to the $program variable. (Assumes it's empty or has a newline.)
addProgramLine() {
	program+="$1${2:+ $2}"$'\n'
}

# -------- END: PROGRAM TEXT HANDLING --------

# -------- START: PASS 1 --------

endCurrentOverlay() {
	if [[ "$currentOverlay" == "" ]]; then
		return
	fi
	local endAddress=$(($address - 1))
	# The previous address is the last address of the current overlay, so set
	# that overlay's end address (in its header DATAC) to that address.
	program=${program//@overlayEnd/$endAddress}
	addProgramLine "// Overlay $currentOverlay ended at address $endAddress"
	# Mark the current address as not being in this overlay anymore.
	endOverlay $address
	# Clear the current overlay.
	currentOverlay=
}

# Pass 1: read lines from source, clean up spaces etc., find overlays/labels
runPass1() {
	local line_no=0
	local address=0
	local currentOverlay=
	local labelRegex="^($identifierRegex)[[:space:]]*:[[:space:]]*(.*)\$"
	local line comment tmp
	while IFS= read -r line
	do
		line_no=$(($line_no + 1))

		# Trim leading whitespace.
		if [[ "$line" =~ ^[[:space:]]+(.*)$ ]]; then
			line=${BASH_REMATCH[1]}
		fi
		# Trim trailing whitespace.
		if [[ "$line" =~ ^(.*[^[:space:]])[[:space:]]+$ ]]; then
			line=${BASH_REMATCH[1]}
		fi
		# Simplify groups of whitespace down to one regular space.
		tmp=
		while [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+(.*)$ ]]; do
			tmp+="${BASH_REMATCH[1]} "
			line=${BASH_REMATCH[2]}
		done
		line="$tmp$line"

		if [ "$line" = "" ]; then
			# Line is empty, turn it into an empty comment to avoid problems.
			addProgramLine "//"
			continue
		fi

		# Check for labels.
		while [[ "$line" =~ $labelRegex ]]; do
			tmp="${BASH_REMATCH[1]}"
			line="${BASH_REMATCH[2]}"
			addLabel "$tmp" "$address" "$currentOverlay" || return 1
			addProgramLine "// Label $tmp found at address $address"
		done
		if [ "$line" = "" ]; then
			# Line only contained a label, nothing else
			continue
		fi

		# If the line has a comment, split it out into a separate variable.
		comment=
		if [[ "$line" =~ //(.*)$ ]]; then
			# This also ensures the assembler can't barf on comment-in-comment.
			comment="${BASH_REMATCH[1]//\/\//\/ \/}"
			while tmp="${comment//\/\//\/ \/}" ; [ "$tmp" != "$comment" ]; do
				comment="$tmp"
			done
			comment="//$comment"
			line=${line%%//*}
			if [ "$line" = "" ]; then
				# Line is purely a comment
				addProgramLine "$comment"
				continue
			fi
			# Trim trailing space, in case there was one before the comment.
			line=${line% }
		fi

		case "${line%% *}" in
			DATAC|NIL|HLT|MOVI|MOVO|JMP|SETDATA|GETDATA|SET|IFJMP|PMOV|MATH)
				addProgramLine "$line" "$comment"
				address=$(($address + 1))
				;;
			NILLIST)
				if ! [[ "$line" =~ ^"NILLIST "([0-9]+)$ ]]; then
					printf >&2 "Error: %s at line %s:\n%s\n" \
						"Missing or invalid NILLIST count" "$line_no" "$line"
					return 1
				fi
				tmp="${BASH_REMATCH[1]}"
				addProgramLine "$line" "$comment"
				address=$(($address + $tmp))
				;;
			OVERLAY)
				tmp="^OVERLAY ($identifierRegex)\$"
				if ! [[ "$line" =~ $tmp ]]; then
					printf >&2 "Error: %s at line %s:\n%s\n" \
						"Invalid overlay declaration" "$line_no" "$line"
					return 1
				fi
				tmp=${BASH_REMATCH[1]}
				endCurrentOverlay
				currentOverlay=$tmp
				addOverlay "$currentOverlay" "$address" || return 1
				addProgramLine "// Overlay $tmp started at address $address"
				if [[ "$comment" != "" ]]; then
					addProgramLine "$comment"
				fi
				# Add the overlay-end-address line that the loader expects.
				addProgramLine "DATAC @overlayEnd // End address for overlay"
				address=$(($address + 1))
				;;
			END_OVERLAY)
				if [[ "$currentOverlay" == "" ]]; then
					printf >&2 "Error: %s at line %s\n" \
						"No overlay to end" "$line_no"
					return 1
				fi
				endCurrentOverlay
				;;
			*)
				printf >&2 "Error: %s at line %s:\n%s\n" \
					"Unknown instruction" "$line_no" "$line"
				return 1
		esac
	done
	endCurrentOverlay
}

# -------- END: PASS 1 --------

# -------- START: PASS 2 --------

# Pass 2: Insert the actual addresses of overlays, labels, etc.
runPass2() {
	# TODO: Deal with the line numbers no longer matching up after pass 1.
	local line_no=0
	local address=0
	local currentOverlay=
	local line comment tmp pre refType refIdentifier refLocalTo ret
	local overlayAddress labelAddress labelOverlay
	local atIdentifierRegex="^($identifierRegex)([: ].*)?$"
	local atLocalToRegex="^:([*]?|$identifierRegex)( .*)?$"
	# Reset the program text so we can add things back into it.
	program=
	while IFS= read -r -d $'\n' line
	do
		line_no=$(($line_no + 1))

		# If this line is a pure comment, then it's fine as-is.
		if [ "${line:0:2}" = "//" ]; then
			addProgramLine "$line"
			continue
		fi

		switchCurrentOverlay $address

		# If the line has a comment, split it out into a separate variable.
		comment=${line#*//}
		if [ "$comment" = "$line" ]; then
			comment=
		else
			comment="//$comment"
		fi
		# This is safe because pass 1 ensures there's a single space there,
		# unless at the start of the line, which we already handled above.
		pre=${line%% //*}

		# Handle @-references, replacing them with the actual values.
		while tmp=${pre#*@} ; [ "$tmp" != "$pre" ]; do
			pre=${pre%%@*}
			if [ "${pre:(-1)}" != " " ]; then
				printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
					"@-reference must be preceded by space" "$line_no" "$line"
				return 1
			fi
			refType=${tmp%%:*}
			if [ "$refType" = "$tmp" ]; then
				printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
					"Invalid @-reference, missing colon" "$line_no" "$line"
				return 1
			fi
			tmp=${tmp#*:}
			if ! [[ "$tmp" =~ $atIdentifierRegex ]]; then
				printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
					"Invalid identifier in @-reference" "$line_no" "$line"
				return 1
			fi
			refIdentifier=${BASH_REMATCH[1]}
			tmp=${BASH_REMATCH[2]}

			case "$refType" in
				overlay)
					if [ "${tmp:0:1}" = ":" ]; then
						printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
							"Extra part in overlay @-reference" "$line_no" "$line"
						return 1
					fi
					if ! getOverlayAddress "$refIdentifier"
					then
						printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
							"Unknown overlay in @-reference" "$line_no" "$line"
						return 1
					fi
					pre+="$overlayAddress$tmp"
					;;
				disk)
					refLocalTo="*"
					;;&
				local|relative)
					refLocalTo=$currentOverlay
					;;&
				disk|local|relative)
					if [[ "$tmp" =~ $atLocalToRegex ]]; then
						refLocalTo=${BASH_REMATCH[1]}
						tmp=${BASH_REMATCH[2]}
					elif [ "${tmp:0:1}" = ":" ]; then
						printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
							"Invalid local-to identifier in @-reference" \
							"$line_no" "$line"
						return 1
					fi
					if [ "$refLocalTo" = "*" ]; then
						getLabelAddress "$refIdentifier"
						ret=$?
					else
						getLabelAddress "$refIdentifier" "$refLocalTo"
						ret=$?
					fi
					if [ $ret -ne 0 ]; then
						printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
							"Unknown label in @-reference" "$line_no" "$line"
						return 1
					fi
					;;&
				disk)
					pre+="$labelAddress$tmp"
					;;
				local)
					if ! getLabelOverlay "$refIdentifier" "$labelAddress"
					then
						printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
							"Unable to get overlay of label" "$line_no" "$line"
						return 1
					fi
					# If the label is not in an overlay, then it is not local
					# in any meaningful sense, since it's never overlay-loaded.
					if [ "$labelOverlay" = "" ]; then
						printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
							"Local label must be in overlay" "$line_no" "$line"
						return 1
					fi
					if ! getOverlayAddress "$labelOverlay"
					then
						printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
							"Unknown overlay for label" "$line_no" "$line"
						return 1
					fi
					labelAddress=$(($labelAddress - $overlayAddress - 1))
					pre+="$labelAddress$tmp"
					;;
				relative)
					labelAddress=$(($labelAddress - $address))
					# Take the absolute value, by dropping any minus sign.
					labelAddress=${labelAddress#-}
					pre+="$labelAddress$tmp"
					;;
				*)
					printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
						"Unknown @-reference type" "$line_no" "$line"
					return 1
					;;
			esac
		done
		line=$pre

		case "${line%% *}" in
			DATAC|NIL|HLT|MOVI|MOVO|JMP|SETDATA|GETDATA|SET|IFJMP|PMOV|MATH)
				addProgramLine "$line" "$comment"
				address=$(($address + 1))
				;;
			NILLIST)
				tmp="${BASH_REMATCH[1]}"
				addProgramLine "$line" "$comment"
				address=$(($address + $tmp))
				;;
			*)
				printf >&2 "Error: %s at line %s (pass 2):\n%s\n" \
					"Unknown instruction" "$line_no" "$line"
				return 1
		esac
	done
}

# -------- END: PASS 2 --------

# -------- START: MAIN PROGRAM --------

inFile=
outFile=
noOutput=0
onlyPass1=0
showHelp=0
debugLevel=0

fail() {
	printf >&2 "Error: %s\n" "$1"
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		-o|--output)
			[ "$outFile" != "" ] && fail "Duplicate -o option"
			[ $noOutput -ne 0 ] && fail "Cannot combine -n and -o"
			[ "$2" = "" ] && fail "Invalid output filename"
			outFile=$2;
			shift
			;;
		-n|--no-output)
			[ "$outFile" != "" ] && fail "Cannot combine -o and -n"
			noOutput=1
			;;
		--pass1)
			onlyPass1=1
			;;
		-h|--help)
			showHelp=1
			;;
		-d|--debug)
			debugLevel=$(($debugLevel + 1))
			;;
		--)
			shift
			while [ $# -gt 0 ]; do
				[ "$1" = "" ] && fail "Invalid input filename"
				[ "$inFile" != "" ] && fail "Multiple input files given"
				inFile="$1"
				shift
			done
			break
			;;
		-)
			[ "$inFile" != "" ] && fail "Multiple input files given"
			inFile="$1"
			;;
		-*)
			fail "Unknown option: $1"
			;;
		*)
			[ "$1" = "" ] && fail "Invalid input filename"
			[ "$inFile" != "" ] && fail "Multiple input files given"
			inFile="$1"
			;;
	esac
	shift
done

[ "$outFile" = "" ] && outFile=-

if [ "$inFile" = "" ] || [ $showHelp -ne 0 ]; then
	printf "Usage: $0 [options] <in-file>\n"
	[ $showHelp -eq 0 ] && exit 1
	IFS= read -r -d '' helpText <<-'END'
		Preprocesses the in-file to make a file for the Senbir assembler.
		This program assumes that the result is intended as a disk image.
		To preprocess stdin, use "-" as the in-file.
		Options:
		  -o, --output <out-file>
		      Write the output to the given file rather than stdout.
		      If out-file is "-", writes the output to stdout anyway.
		  -n, --no-output
		      Do not write the output to either stdout or a file.
		  -h, --help
		      Show this help.
		  --pass1
		      Only run the first pass, not the second.
		      This is mainly only useful for debugging.
		  -d, --debug
		      Show debugging information on stdout. At the moment, this shows
		      the detected overlays and labels, with their addresses.
	END
	printf "%s\n" "$helpText"
	exit 0
fi

if [ "$inFile" = "-" ]; then
	# Read from stdin
	runPass1 || exit 1
else
	runPass1 < "$inFile" || exit 1
fi

if [ $onlyPass1 -eq 0 ] && [ "$program" != "" ]; then
	runPass2 <<<"${program%$'\n'}" || exit 1
fi

if [ $noOutput -eq 0 ]; then
	if [ "$outFile" = "-" ]; then
		# Write to stdout
		printf "%s" "$program"
	else
		printf "%s" "$program" > "$outFile"
	fi
fi

if [ $debugLevel -gt 0 ]; then
	printf "Overlays:\n"
	for ident in "${!overlayList[@]}" ; do
		printf "%6s %s\n" "${overlayList[$ident]}" "$ident"
	done
	printf "\nLabels:\n"
	tmp=${labels# }
	tmp=${tmp% }
	printf "  %s" "${tmp// /$'\n'  }"
fi

# -------- END: MAIN PROGRAM --------
