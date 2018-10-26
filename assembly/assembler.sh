#!/bin/bash

# Note: This script uses fd 3 for the input file, and fd 4 for the output file.

# Holds a mapping of instruction to the parameter types for that instruction.
# Known types: uint bits zero fixed special
declare -A instructionParameters
instructionParameters[DATAC]="bits-32"
instructionParameters[NILLIST]="special-32"
instructionParameters[NIL]="zero-32"
instructionParameters[HLT]="fixed:0001-4 : uint-28"
instructionParameters[MOVI]="fixed:0010-4 uint-4 uint-24"
instructionParameters[MOVO]="fixed:0011-4 uint-4 uint-24"
instructionParameters[JMP]="fixed:0100-4 uint-2 uint-24 zero-2"
instructionParameters[SETDATA]="fixed:0101-4 uint-4 uint-2 special-22"
instructionParameters[GETDATA]="fixed:0110-4 uint-4 uint-2 special-22"
instructionParameters[SET]="fixed:0111-4 uint-4 uint-2 bits,uint-8 zero-14"
instructionParameters[IFJMP]="fixed:1000-4 uint-2 uint-24 uint-2"
instructionParameters[PMOV]="fixed:1001-4 uint-4 uint-4 uint-5 uint-5 uint-5 bits-1 zero-4"
instructionParameters[MATH]="fixed:1010-4 uint-4 uint-4 uint-4 : bits-16"

full_line=
line_no=0
line=

instruction=
arguments=
argument=

parameters=
instructionWord=

argumentBits=
handleTypeErrors=()


# Holds a mapping of hex digit to equivalent bits, for converting to binary.
declare -A hexToBitsMap
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



error() {
	printf >&2 "Error: %s at line %s:\n%s\n" "$*" "$line_no" "$full_line"
	return 1
}

internal() {
	printf >&2 "Internal error on line %s: %s\n%s\n" \
		"$line_no" "$*" "$full_line"
	exit 2
}

# ----

instructionCount=0

writerFormat=true

writerInit=writerInitFile
writerWrite=writerToFile
writerDone=writerDoneFile

writerPrefix=
writerSeparator=$'\n'
writerSuffix=

writerBufferData=

writerFormatDecimal() {
	instructionWord=$(( 2#$instructionWord ))
}

writerFormatHexadecimal() {
	printf -v instructionWord '0x%08X' $(( 2#$instructionWord ))
}

writerToFile() {
	if [ $instructionCount -eq 0 ]; then
		printf >&4 "%s" "$1"
	else
		writerToFile() {
			printf >&4 "%s%s" "$writerSeparator" "$1"
		}
		writerToFile "$@"
	fi
}

writerToBuffer() {
	if [ $instructionCount -eq 0 ]; then
		writerBufferData+="$1"
	else
		writerToBuffer() {
			writerBufferData+="$writerSeparator$1"
		}
		writerToBuffer "$@"
	fi
}

writerOpenFile() {
	if [ "$outFile" = "-" ]; then
		# Write to stdout
		exec 4>&1 || return 1
	else
		# Write to file
		exec 4> "$outFile" || return 1
	fi
}

writerInitFile() {
	writerOpenFile || return 1

	if [ "$writerPrefix" != "" ]; then
		printf >&4 "%s" "$writerPrefix"
	fi
}

writerDoneFile() {
	printf >&4 "%s" "$writerSuffix"

	# Close the output descriptor
	exec 4>&-
}

writerDoneBuffer() {
	writerOpenFile || return 1

	printf >&4 "%s%s%s" "$writerPrefix" "$writerBufferData" "$writerSuffix"

	# Close the output descriptor
	exec 4>&-
}

writerDoneSizeHeader() {
	arguments=$instructionCount handleType_uint 32 || internal "size header"
	instructionWord=$argumentBits
	$writerFormat || internal "format size header"

	if [ $instructionCount -eq 0 ]; then
		writerBufferData+="$instructionWord"
	else
		writerBufferData="$instructionWord$writerSeparator$writerBufferData"
	fi

	writerDoneBuffer
}

# ----

outputInstructionWord() {
	[ ${#1} -eq 32 ] || internal "invalid instruction word length (${#1}: $1)"

	local instructionWord="$1"

	$writerFormat || internal "failed to format instruction word"

	$writerWrite "$instructionWord" || internal "failed to write instruction"

	instructionCount=$((instructionCount + 1))
}

getNextProgramLine() {
	while IFS= read -r -d $'\n' -u 3 full_line
	do
		line_no=$((line_no + 1))

		# Remove any comments
		line=${full_line%%//*}

		# Trim whitespace
		read -r line <<<"$line" || internal "trim failed"

		# If it's not empty, then return it
		if [ "$line" != "" ]; then
			return 0
		fi
	done

	# No more lines are available
	return 1
}

#----

handleTypeError() {
	handleTypeErrors+=("For $type: $1")
}

handleType_uint() {
	local value rest
	read -r value rest <<<"$arguments" || internal "peek arg in type_uint"

	if ! [[ "$value" =~ ^[+]?[0-9]+$ ]]; then
		handleTypeError "Argument is not an unsigned integer: \"$value\""
		return 1
	fi

	# There's no built-in way to convert a number to a binary string,
	# so we have to do it ourselves.
	printf -v value "%X" "${value#+}"
	local bits=
	while [ "$value" != "" ]; do
		bits+=${hexToBitsMap[${value:0:1}]}
		value=${value:1}
	done
	# We should now have the result bits, with up to 3 extra 0-bits.
	while [ ${#bits} -gt $1 -a "${bits:0:1}" = "0" ]; do
		bits=${bits:1}
	done
	if [ ${#bits} -gt $1 ]; then
		handleTypeError "Result has too many bits (${#bits} > $1)"
		return 1
	fi
	# We could have fewer 0-bits than we need, so add the rest.
	printf -v bits "%*s" "$1" "$bits"

	argumentBits=${bits// /0}
	arguments=$rest
}

handleType_bits() {
	local arg rest
	read -r arg rest <<<"$arguments" || internal "peek arg in type_bits"

	if [ ${#arg} -ne $1 ] || ! [[ "$arg" =~ ^[01]+$ ]]; then
		handleTypeError "Argument is not binary or has wrong length: \"$arg\""
		return 1
	fi

	argumentBits=$arg
	arguments=$rest
}

handleType_zero() {
	printf -v argumentBits '%0*d' "$1" "0"
}

handleType_fixed() {
	argumentBits="$2"
}

handleType_special() {
	local handler="handleSpecial_$instruction"
	local type="$instruction $type"
	$handler "$@"
}

# ----

handleSpecialError() {
	handleTypeError "$@"
}

handleSpecial_NILLIST() {
	if ! [[ "$arguments" =~ ^([+-]?[0-9]+)$ ]]; then
		handleSpecialError "Missing or invalid arguments"
		return 1
	fi

	argument=$(( 10#$arguments ))

	if [ $argument -lt 1 ]; then
		handleSpecialError "Invalid argument: count less than 1"
		return 1
	fi

	handleType_zero 32

	while [ $argument -gt 1 ]; do
		outputInstructionWord "$argumentBits"
		argument=$((argument - 1))
	done
}

handleSpecial_SETDATA() {
	# This parameter handles differently based on the flag.
	case "${instructionWord:8}" in
		00)
			handleType_bits 22 || return 1
			;;
		11)
			handleType_uint 4 || return 1
			# Check for (and handle) extended setdata
			local tmp=$argumentBits
			if handleType_uint 4
			then
				printf -v argumentBits '%s1%s%0*d' \
					"$tmp" "$argumentBits" 13 0 || internal "setdata extended"
			else
				printf -v tmp '%0*d' 18 0 || internal "setdata gen zeroes"
				argumentBits+="$tmp"
			fi
			;;
		01|10)
			local arg rest
			read -r arg rest <<<"$arguments" || internal "setdata get arg"

			if ! [[ "$arg" =~ ^[+-]?[0-9]+$ ]]; then
				handleSpecialError "Argument is not an integer: \"$arg\""
				return 1
			fi

			local direction="1"
			if [ "${arg:0:1}" = "-" ]; then
				direction="0"
				arg=${arg:1}
			fi

			arguments="$arg" handleType_uint 21 || return 1

			argumentBits="$direction$argumentBits"
			arguments=$rest
			;;
		*)
			handleSpecialError "Unknown flag value: \"${instructionWord:8}\""
			return 1
			;;
	esac
}

handleSpecial_GETDATA() {
	# This parameter handles differently based on the flag.
	case "${instructionWord:8}" in
		00) handleType_bits 22 ; return $? ;;
		11)
			handleType_uint 4 || return 1
			local tmp
			printf -v tmp '%0*d' 18 0 || internal "gen zeroes in setdata"
			argumentBits+="$tmp"
			;;
		01|10)
			local arg rest
			read -r arg rest <<<"$arguments" || internal "setdata get arg"

			if ! [[ "$arg" =~ ^[+-]?[0-9]+$ ]]; then
				handleSpecialError "Argument is not an integer: \"$arg\""
				return 1
			fi

			local direction="1"
			if [ "${arg:0:1}" = "-" ]; then
				direction="0"
				arg=${arg:1}
			fi

			arguments="$arg" handleType_uint 21 || return 1

			argumentBits="$direction$argumentBits"
			arguments=$rest
			;;
		*)
			handleSpecialError "Unknown flag value: \"${instructionWord:8}\""
			return 1
			;;
	esac
}

# ----

buildInstructionWordFromParameters() {
	local optional=0 parameter size types type args handler
	while [ "$parameters" != "" ]; do
		read -r parameter parameters <<<"$parameters" || internal "next param"

		if [ "$parameter" = ":" ]; then
			optional=1
			continue
		fi

		IFS=- read -r types size <<<"$parameter" || internal "extract size"
		[[ "$size" =~ ^[0-9]+$ ]] || internal "invalid parameter size"
		[ $size -gt 0 ] || internal "parameter size < 1"

		handleTypeErrors=()
		argumentBits=
		while [ "$types" != "" ]; do
			IFS=, read -r type types <<<"$types" || internal "next type"
			[ "$type" != "" ] || internal "invalid type"

			IFS=: read -r type args <<<"$type" || internal "extract type args"

			handler="handleType_$type"
			$handler "$size" $args && break

			argumentBits=
		done

		if [ "$argumentBits" = "" ]; then
			if [ $optional -ne 0 -a "$arguments" = "" ]; then
				handleType_zero "$size"
			else
				if [ ${#handleTypeErrors[@]} -gt 0 ]; then
					printf >&2 "%s\n" "${handleTypeErrors[@]}"
					printf >&2 "\n"
				fi
				error "Invalid arguments for $instruction"
				return 1
			fi
		fi

		[ ${#argumentBits} -eq $size ] || internal "argument bits mismatch"

		instructionWord+="$argumentBits"
	done

	if [ "$arguments" != "" ]; then
		error "Too many arguments for $instruction"
		return 1
	fi
}

# ----

inFile=
outFile=
noOutput=0
showHelp=0
useBuffer=0
hasFormat=0
hasSizeHeader=0
hasSeparator=0
hasPrefix=0
hasSuffix=0

fail() {
	printf >&2 "Error: %s\n" "$1"
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		-o*|--output|--output=*)
			[ "$outFile" != "" ] && fail "Duplicate -o option"
			[ $noOutput -ne 0 ] && fail "Cannot combine -n and -o"
			if [ "$1" = "-o" -o "$1" = "--output" ]; then
				outFile="$2"
				shift
			elif [ "${1:0:2}" = "-o" ]; then
				outFile=${1:2}
			else # --output=
				outFile=${1:9}
			fi
			[ "$outFile" = "" ] && fail "Invalid output filename"
			;;
		-n|--no-output)
			[ "$outFile" != "" ] && fail "Cannot combine -o and -n"
			[ $noOutput -ne 0 ] && fail "Duplicate -n option"
			noOutput=1
			;;
		-h|--help)
			showHelp=1
			;;
		-f*|--format|--format=*)
			[ $hasFormat -ne 0 ] && fail "Duplicate -f option"
			hasFormat=1
			if [ "$1" = "-f" -o "$1" = "--format" ]; then
				writerFormat="$2"
				shift
			elif [ "${1:0:2}" = "-f" ]; then
				writerFormat=${1:2}
			else # --format=
				writerFormat=${1:9}
			fi
			case "$writerFormat" in
				bin) writerFormat=true ;;
				hex) writerFormat=writerFormatHexadecimal ;;
				dec) writerFormat=writerFormatDecimal ;;
				*) fail "Unknown format: $writerFormat" ;;
			esac
			;;
		-b|--buffer)
			[ $useBuffer -gt 1 ] && fail "Duplicate -b option"
			if [ $useBuffer -eq 0 ]; then
				writerWrite=writerToBuffer
				writerInit=true
				writerDone=writerDoneBuffer
			fi
			useBuffer=2
			;;
		--size-header)
			[ $hasSizeHeader -ne 0 ] && fail "Duplicate --size-header option"
			hasSizeHeader=1
			useBuffer=$((useBuffer + 1))
			writerWrite=writerToBuffer
			writerInit=true
			writerDone=writerDoneSizeHeader
			;;
		--separator)
			[ $hasSeparator -ne 0 ] && fail "Duplicate --separator option"
			hasSeparator=1
			writerSeparator="$2"
			shift
			;;
		--separator=*)
			[ $hasSeparator -ne 0 ] && fail "Duplicate --separator option"
			hasSeparator=1
			writerSeparator=${1:12}
			;;
		--prefix)
			[ $hasPrefix -ne 0 ] && fail "Duplicate --prefix option"
			hasPrefix=1
			writerPrefix="$2"
			shift
			;;
		--prefix=*)
			[ $hasPrefix -ne 0 ] && fail "Duplicate --prefix option"
			hasPrefix=1
			writerPrefix=${1:9}
			;;
		--suffix)
			[ $hasSuffix -ne 0 ] && fail "Duplicate --suffix option"
			hasSuffix=1
			writerSuffix="$2"
			shift
			;;
		--suffix=*)
			[ $hasSuffix -ne 0 ] && fail "Duplicate --suffix option"
			hasSuffix=1
			writerSuffix=${1:9}
			;;
		--json)
			shift
			set -- dummy -f dec --separator "," --prefix "[" --suffix "]" "$@"
			;;
		--js)
			shift
			set -- dummy -f hex --separator $',\n\t' --prefix $'[\n\t' \
				--suffix $'\n]' "$@"
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
		Assembles the in-file to make a binary program for the TC-06 processor.
		That binary program can be saved in various formats (usually as some
		form of text, by default as a 32-bit binary number per instruction).
		To preprocess stdin, use "-" as the in-file.
		Options:
		  -o, --output <out-file>
		      Write the output to the given file rather than stdout.
		      If out-file is "-", writes the output to stdout anyway.
		  -n, --no-output
		      Do not write the output to either stdout or a file.
		  -h, --help
		      Show this help.
		  -f, --format <format>
		      Use the given format to write the results to the output.
		      Known formats:
		          bin: Use binary numbers. This is the default.
		          hex: Use hexadecimal numbers.
		          dec: Use decimal numbers.
		  -b, --buffer
		      Buffer the output, to avoid overwriting the output file on error.
		  --size-header
		      Write a header giving the number of instructions in the output.
		      This implies --buffer
		  --separator <separator>
		      Write the given separator between the results in the output.
		      Defaults to a newline.
		  --prefix <prefix>
		      Write the given prefix to the output before the results.
		  --suffix <suffix>
		      Write the given suffix to the output after the results.
		  --json
		      Write the output in JSON format.
		      This is a shortcut for setting --format, --separator, --prefix
		      and --suffix to values that cause the output to be valid JSON.
		  --js
		      Write the output as a nicely formatted JavaScript array.
		      This is a shortcut for setting --format, --separator, --prefix
		      and --suffix to values that cause this format to be generated.
	END
	printf "%s\n" "$helpText"
	exit 0
fi

if [ "$inFile" = "-" ]; then
	# Read from stdin
	exec 3<&0 || fail "Could not open stdin as fd 3"
else
	# Read from file
	exec 3< "$inFile" || fail "Could not open input file"
fi

if [ $noOutput -ne 0 ]; then
	# No writing, so we don't need any of these
	writerWrite=true
	writerFormat=true
	writerInit=true
	writerDone=true
fi

$writerInit || exit 1

while getNextProgramLine
do
	read -r instruction arguments <<<"$line" || internal "instruction grab"

	parameters=${instructionParameters[$instruction]}
	if [ "$parameters" = "" ]; then
		error "Unknown instruction"
		exit 1
	fi

	instructionWord=
	buildInstructionWordFromParameters || exit 1

	# Note: this is not the only place this function is called
	outputInstructionWord "$instructionWord"
done

$writerDone

# Close the input file descriptor
exec 3<&-
