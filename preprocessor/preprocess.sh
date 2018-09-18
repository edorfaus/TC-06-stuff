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

# Holds a mapping of hex digit to equivalent bits, for converting to binary.
declare -A hexToBitsMap

# Holds a mapping of instruction to the parameter types for that instruction.
declare -A instructionParameters
instructionParameters[DATAC]="bits32"
instructionParameters[NILLIST]="int32"
instructionParameters[NIL]=""
instructionParameters[HLT]=": uint28"
instructionParameters[MOVI]="uint4 uint24"
instructionParameters[MOVO]="uint4 uint24"
instructionParameters[JMP]="uint2 uint24"
instructionParameters[SETDATA]="uint4 uint2 setdata : uint4"
instructionParameters[GETDATA]="uint4 uint2 setdata"
instructionParameters[SET]="uint4 uint2 bits8"
instructionParameters[IFJMP]="uint2 uint24 uint2"
instructionParameters[PMOV]="uint4 uint4 uint5 uint5 uint5 uint1"
instructionParameters[MATH]="uint4 uint4 uint4 : bits16"

# Used to hold the list of overlays, with info about each.
declare -A overlayList
# Used to hold the addresses at which the current overlay changes.
declare -a overlaySwitch

# Used to hold the list of labels, with info about each.
labels=" "

# Used to hold the text of the program being preprocessed.
program=

# Used to hold the line number of the source line for each program line.
source_line_numbers=()

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

# -------- START: AT-REFERENCES --------

# Replace any @-references in the current line with their calculated values.
# Both input and output is in $line which must be without comment already.
# This function also uses these variables: $line_no $address $currentOverlay
# Returns 0 on success, 1 on error (after printing error message).
replaceAtReferences() {
	local pre=$line tmp refType refIdentifier refLocalTo
	local overlayAddress labelAddress labelOverlay
	local atIdentifierRegex="^($identifierRegex)([: ].*)?\$"
	local atLocalToRegex="^:([*]?|$identifierRegex)( .*)?\$"
	# Handle @-references, replacing them with the actual values.
	while tmp=${pre#*@} ; [ "$tmp" != "$pre" ]; do
		pre=${pre%%@*}
		if [ "${pre:(-1)}" != " " ]; then
			printf >&2 "Error: %s at line %s:\n%s\n" \
				"@-reference must be preceded by space" "$line_no" "$line"
			return 1
		fi
		refType=${tmp%%:*}
		if [ "$refType" = "$tmp" ]; then
			printf >&2 "Error: %s at line %s:\n%s\n" \
				"Invalid @-reference, missing colon" "$line_no" "$line"
			return 1
		fi
		tmp=${tmp#*:}
		if ! [[ "$tmp" =~ $atIdentifierRegex ]]; then
			printf >&2 "Error: %s at line %s:\n%s\n" \
				"Invalid identifier in @-reference" "$line_no" "$line"
			return 1
		fi
		refIdentifier=${BASH_REMATCH[1]}
		tmp=${BASH_REMATCH[2]}

		case "$refType" in
			overlay)
				if [ "${tmp:0:1}" = ":" ]; then
					printf >&2 "Error: %s at line %s:\n%s\n" \
						"Extra part in overlay @-reference" "$line_no" "$line"
					return 1
				fi
				if ! getOverlayAddress "$refIdentifier"
				then
					printf >&2 "Error: %s at line %s:\n%s\n" \
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
					printf >&2 "Error: %s at line %s:\n%s\n" \
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
					printf >&2 "Error: %s at line %s:\n%s\n" \
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
					printf >&2 "Error: %s at line %s:\n%s\n" \
						"Unable to get overlay of label" "$line_no" "$line"
					return 1
				fi
				# If the label is not in an overlay, then it is not local
				# in any meaningful sense, since it's never overlay-loaded.
				if [ "$labelOverlay" = "" ]; then
					printf >&2 "Error: %s at line %s:\n%s\n" \
						"Local label must be in overlay" "$line_no" "$line"
					return 1
				fi
				if ! getOverlayAddress "$labelOverlay"
				then
					printf >&2 "Error: %s at line %s:\n%s\n" \
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
				printf >&2 "Error: %s at line %s:\n%s\n" \
					"Unknown @-reference type" "$line_no" "$line"
				return 1
				;;
		esac
	done
	line=$pre
	return 0
}

# -------- END: AT-REFERENCES --------

# -------- START: PROGRAM TEXT HANDLING --------

# Add a line to the $program variable. (Assumes it's empty or has a newline.)
# Uses the $line_no variable to know the original source line number.
addProgramLine() {
	program+="$1${2:+ $2}"$'\n'
	source_line_numbers+=($line_no)
}

# -------- END: PROGRAM TEXT HANDLING --------

# -------- START: NUMBER HANDLING --------

# Initialize the hexToBitsMap global variable.
initHexToBitsMap() {
	local bits hex
	for bits in {0,1}{0,1}{0,1}{0,1} ; do
		printf -v hex "%X" $(( 2#$bits ))
		hexToBitsMap[$hex]=$bits
	done
}
initHexToBitsMap
unset initHexToBitsMap

# Parse the given expression down into a single number to be formatted.
# This should not be called outside of parseAndFormatNumber.
_parseExpression() {
	# from caller: type typeLen value
	local formattedNumber anyType="_any$typeLen" pre= depth=0 expr="$value"
	local state=number
	while [ "$expr" != "" ]; do
		case "$state" in
			number)
				if [[ "$expr" =~ ^[[:space:]]*"("[[:space:]]*(.*)$ ]]; then
					pre+=" ("
					depth=$(($depth + 1))
					expr=${BASH_REMATCH[1]}
				elif [[ "$expr" =~ ^[[:space:]]*([+-]?[0-9][0-9a-fA-FxX_.]*)[[:space:]]*(.*)$ ]]; then
					local number=${BASH_REMATCH[1]}
					expr=${BASH_REMATCH[2]}
					parseAndFormatNumber "$anyType" "$number" || return 1
					pre+=" $formattedNumber"
					state=operator
				elif [[ "$expr" =~ ^[[:space:]]*"~"[[:space:]]*(.*)$ ]]; then
					# This is technically an operator, not a number, but since
					# it's a unary operator, it works better here.
					pre+=" ~"
					expr=${BASH_REMATCH[1]}
				else
					printf >&2 "Error: Invalid expression, %s: %s\n" \
						"expected a number but found" "${expr:0:20}"
					return 1
				fi
				;;
			operator)
				if [[ "$expr" =~ ^[[:space:]]*")"[[:space:]]*(.*)$ ]]; then
					pre+=" )"
					depth=$(($depth - 1))
					expr=${BASH_REMATCH[1]}
					if [ $depth -lt 1 -a "$expr" != "" ]; then
						printf >&2 "Error: Invalid expression, %s: %s\n" \
							"unbalanced end-parenthesis before" "${expr:0:20}"
						return 1
					fi
				elif [[ "$expr" =~ ^[[:space:]]*([&|^*/%+-]|<<|>>)[[:space:]]*(.*)$ ]]; then
					pre+=" ${BASH_REMATCH[1]}"
					expr=${BASH_REMATCH[2]}
					state=number
				else
					printf >&2 "Error: Invalid expression, %s: %s\n" \
						"expected an operator but found" "${expr:0:20}"
					return 1
				fi
				;;
			*)
				printf >&2 "Internal error: Unknown state: '%s'\n" "$state"
				return 1
		esac
	done
	if [ "$state" = "number" ]; then
		printf >&2 "Error: Invalid expression, missing number at end: %s\n" \
			"$value"
		return 1
	fi
	if [ $depth -gt 0 ]; then
		printf >&2 "Error: Invalid expression, unclosed parenthesis: %s\n" \
			"$value"
		return 1
	fi
	value=$(( $pre ))
}

# Parse, check and then format a number according to its parameter type.
# On success, returns 0 with result in the $formattedNumber variable.
# On error, returns 1.
# parseAndFormatNumber <type> <number>
parseAndFormatNumber() {
	local type typeLen value="$2" sign
	if ! [[ "$1" =~ ^(bits|u?int|_any)([0-9]+)$ ]]; then
		printf >&2 "Error: Invalid number type: %s\n" "$1"
		return 1
	fi
	type=${BASH_REMATCH[1]}
	typeLen=${BASH_REMATCH[2]}
	if [ "${value:0:1}" = "(" ]; then
		_parseExpression || return 1
	fi
	if [[ "$value" =~ ^([+-]?)0[xX](.*)$ ]]; then
		# Explicitly hexadecimal.
		sign=${BASH_REMATCH[1]}
		if ! [[ "${BASH_REMATCH[2]//_}" =~ ^([0123456789abcdefABCDEF]+)$ ]]; then
			printf >&2 "Error: Invalid hexadecimal value: %s\n" "$value"
			return 1
		fi
		value=$(( 16#${BASH_REMATCH[1]} ))
	elif [[ "$value" =~ ^([+-]?)0[bB](.*)$ ]]; then
		# Explicitly binary.
		sign=${BASH_REMATCH[1]}
		if ! [[ "${BASH_REMATCH[2]//_}" =~ ^([01]+)("..."([01]*))?$ ]]; then
			printf >&2 "Error: Invalid binary value: %s\n" "$value"
			return 1
		fi
		if [ $(( ${#BASH_REMATCH[1]} + ${#BASH_REMATCH[3]} )) -gt $typeLen ]; then
			printf >&2 "Error: Binary value too long for %s: %s\n" "$1" "$value"
			return 1
		fi
		value=${BASH_REMATCH[1]}
		if [ "${BASH_REMATCH[2]}" != "" ]; then
			printf -v value "%s%*s" "$value" \
				$(( $typeLen - ${#value} )) "${BASH_REMATCH[3]}"
			value=${value// /0}
		fi
		# If the value is negative zero, drop the negativity.
		[ "$sign" = "-" ] && [[ "$value" =~ ^0+$ ]] && sign=
		if [ "$type" = "bits" -a "$sign" != "-" ]; then
			# We have the format we want, so skip re-encoding it.
			printf -v value "%*s" "$typeLen" "$value"
			formattedNumber=${value// /0}
			return 0
		fi
		value=$(( 2#$value ))
	elif [ ${#value} -eq $typeLen ] && [[ "$value" =~ ^[01]+$ ]]; then
		# Binary with exact length.
		if [ "$type" = "bits" ]; then
			# We already have the format we want, so skip re-encoding it.
			formattedNumber=$value
			return 0
		fi
		value=$(( 2#$value ))
	else
		# No other recognized format, so try decimal.
		if ! [[ "$value" =~ ^([+-]?)([0123456789]+)$ ]]; then
			printf >&2 "Error: Invalid number: %s\n" "$value"
			return 1
		fi
		sign=${BASH_REMATCH[1]}
		value=$(( 10#${BASH_REMATCH[2]} ))
	fi
	# If the value is negative zero, drop the negativity.
	[ "$sign" = "-" -a $value -eq 0 ] && sign=
	case "$type" in
		uint)
			if [ "$sign" = "-" ]; then
				printf >&2 "Error: Negative value not allowed for %s\n" "$1"
				return 1
			fi
			if [ $value -ge $(( 2**$typeLen )) ]; then
				printf >&2 "Error: Value too large for %s: %s\n" "$1" "$value"
				return 1
			fi
			formattedNumber=$value
			return 0
			;;
		int)
			local op=-ge
			[ "$sign" = "-" ] && op=-gt
			if [ $value $op $(( 2**($typeLen - 1) )) ]; then
				printf >&2 "Error: Value out of range for %s: %s%s\n" \
					"$1" "$sign" "$value"
				return 1
			fi
			if [ "$sign" = "-" ]; then
				formattedNumber=$(( 0 - $value ))
			else
				formattedNumber=$value
			fi
			return 0
			;;
		bits)
			local op=-ge maxVal=$(( 2**$typeLen ))
			if [ "$sign" = "-" ]; then
				op=-gt
				maxVal=$(( $maxVal / 2 ))
			fi
			if [ $value $op $maxVal ]; then
				printf >&2 "Error: Value out of range for %s: %s%s\n" \
					"$1" "$sign" "$value"
				return 1
			fi
			if [ "$sign" = "-" ]; then
				value=$(( $maxVal * 2 - $value ))
			fi
			# There's no built-in way to convert to a binary string,
			# so we have to do it ourselves.
			printf -v value "%X" "$value"
			op=
			while [ "$value" != "" ]; do
				op+=${hexToBitsMap[${value:0:1}]}
				value=${value:1}
			done
			# We should now have the result bits, with up to 3 extra 0-bits.
			while [ ${#op} -gt $typeLen -a "${op:0:1}" = "0" ]; do
				op=${op:1}
			done
			if [ ${#op} -gt $typeLen ]; then
				printf >&2 "Error: Result has too many bits for %s: %s\n" \
					"$1" "$op"
				return 1
			fi
			# We could have fewer 0-bits than we need, so add the rest.
			printf -v op "%*s" "$typeLen" "$op"
			formattedNumber=${op// /0}
			return 0
			;;
		_any)
			# This type is used for intermediate values, so don't check range.
			if [ "$sign" = "-" ]; then
				formattedNumber=$(( 0 - $value ))
			else
				formattedNumber=$value
			fi
			return 0
			;;
		*)
			printf >&2 "Internal error: Unknown type: '%s' from '%s'\n" \
				"$type" "$1"
			exit 1
			;;
	esac
}

# -------- END: NUMBER HANDLING --------

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
	local line comment tmp formattedNumber
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
				if ! replaceAtReferences
				then
					printf >&2 "Note: For NILLIST, %s\n" \
						"only preceding identifiers can be used."
					return 1
				fi
				if ! [[ "$line" =~ ^"NILLIST "(.+)$ ]]; then
					printf >&2 "Error: %s for NILLIST at line %s:\n%s\n" \
						"Missing argument" "$line_no" "$line"
					return 1
				fi
				if ! parseAndFormatNumber int32 "${BASH_REMATCH[1]}"
				then
					printf >&2 "Error: %s for NILLIST at line %s:\n%s\n" \
						"Invalid count" "$line_no" "$line"
					return 1
				fi
				tmp=$formattedNumber
				if [ $tmp -lt 0 ]; then
					printf >&2 "Error: %s for NILLIST at line %s:\n%s\n" \
						"Count cannot be negative" "$line_no" "$line"
					return 1
				fi
				if [ $tmp -eq 0 ]; then
					# Senbir's NILLIST always adds at least one NIL.
					addProgramLine "// NILLIST $tmp" "${comment:1}"
				else
					addProgramLine "NILLIST $tmp" "$comment"
				fi
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
	local line_index=0 line_no
	local address=0
	local currentOverlay=
	local line comment tmp pre refType ret optional formattedNumber
	local old_line_numbers=("${source_line_numbers[@]}")
	# Reset the program text so we can add things back into it.
	program=
	source_line_numbers=()
	while IFS= read -r -d $'\n' line
	do
		line_no=${old_line_numbers[$line_index]}
		line_index=$(($line_index + 1))

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
		line=${line%% //*}

		# Handle @-references, replacing them with the actual values.
		replaceAtReferences || return 1

		case "${line%% *}" in
			DATAC|NIL|HLT|MOVI|MOVO|JMP|SETDATA|GETDATA|SET|IFJMP|PMOV|MATH)
				IFS=" " read -r pre ret <<<"$line"
				optional=0
				for refType in ${instructionParameters[$pre]} ; do
					if [ "$refType" = ":" ]; then
						optional=1
						continue
					fi
					if [ "$ret" = "" ]; then
						if [ $optional -eq 0 ]; then
							printf >&2 "Error: %s at line %s:\n%s\n" \
								"Missing argument" "$line_no" "$line"
							return 1
						fi
						continue
					fi
					IFS=" " read -r tmp ret <<<"$ret"
					if [ "${tmp:0:1}" = "(" ]; then
						# It's an expression, so grab all of it even if there
						# are spaces in it.
						local noOpen=${tmp//\(} noEnd=${tmp//\)}
						while [ ${#noOpen} -lt ${#noEnd} -a "$ret" != "" ]; do
							local tmp2
							IFS=" " read -r tmp2 ret <<<"$ret"
							tmp+=" $tmp2"
							noOpen=${tmp//\(}
							noEnd=${tmp//\)}
						done
					fi
					if [ "$refType" = "setdata" ]; then
						# This parameter handles differently based on the flag.
						case "${pre##* }" in
							0) refType="bits22" ;;
							3) refType="uint4" ;;
							1|2)
								# Parse it as signed int, like Senbir does.
								if ! parseAndFormatNumber "int22" "$tmp"
								then
									printf >&2 "Error: %s at line %s:\n%s\n" \
										"Invalid argument" "$line_no" "$line"
									return 1
								fi
								# Check that the abs. value fits in 21 bits.
								if [ $formattedNumber -lt 0 ]; then
									formattedNumber=$(( 0 - $formattedNumber ))
								fi
								if ! parseAndFormatNumber "uint21" "$formattedNumber"
								then
									printf >&2 "Error: %s at line %s:\n%s\n" \
										"Invalid argument" "$line_no" "$line"
									return 1
								fi
								# This argument is OK, output it as int22.
								refType="int22"
								;;
							*)
								printf >&2 "Error: %s at line %s:\n%s\n" \
									"Unknown flag value" "$line_no" "$line"
								return 1
								;;
						esac
					fi
					if ! parseAndFormatNumber "$refType" "$tmp"
					then
						printf >&2 "Error: %s at line %s:\n%s\n" \
							"Invalid argument" "$line_no" "$line"
						return 1
					fi
					pre+=" $formattedNumber"
				done
				if [ "$ret" != "" ]; then
					printf >&2 "Error: %s at line %s:\n%s\n" \
						"Too many arguments" "$line_no" "$line"
					return 1
				fi
				addProgramLine "$pre" "$comment"
				address=$(($address + 1))
				;;
			NILLIST)
				# Match the count to update the address. The count has already
				# been parsed, checked and formatted during pass 1.
				if ! [[ "$line" =~ ^"NILLIST "([0-9]+)$ ]]; then
					printf >&2 "Internal error: %s at line %s:\n%s\n" \
						"Bad NILLIST" "$line_no" "$line"
					return 1
				fi
				tmp="${BASH_REMATCH[1]}"
				addProgramLine "$line" "$comment"
				address=$(($address + $tmp))
				;;
			*)
				printf >&2 "Error: %s at line %s:\n%s\n" \
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
