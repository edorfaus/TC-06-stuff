TC-06 assembly preprocessor
===========================

This directory contains a preprocessor script that takes an input file with an
extended version of the assembly language, and turns it into a plain assembly
file that the assembler in [Senbir] can understand.

This preprocessor script is written in Bash 4, using only built-ins, so that
should be the only dependency to make this work.

This file primarily describes the language that the preprocessor understands,
or at least the parts that are not already in Senbir's assembly language.

*Note:* When this file talks about an "identifier", it means a string that is
used to identify something, and which consists of only US-ASCII letters,
digits and/or underscores, and that starts with a letter or underscore.

[Senbir]: https://cliffracerx.itch.io/senbir

Features
--------

### Summary

(See following sections for details.)

- Relaxed whitespace/comment handling (indenting, comment-in-comment, etc.)
- Number format unification
- Constant expression evaluation
- Minor fixes/improvements
- Overlay handling
- Labels for addresses
- References to labels and overlays (by identifier instead of by address)

### Relaxed whitespace and comment handling

The assembler in Senbir is rather strict about the whitespace it allows - as
in, not allowing much of it at all.

This preprocessor relaxes this by collapsing runs of any whitespace (including
tabs etc.) into a single space, and removing leading/trailing whitespace, so
that you can use indenting, alignment, etc. as you want, and it gets cleaned
up for you.

Similarly, since Senbir's assembler doesn't allow blank lines, those are
replaced with an empty comment, which is allowed.

The assembler is also not very forgiving regarding comments, in particular it
requires that comments start either at the start of a line or after a space,
and that they do not contain other comments.

This preprocessor relaxes that by inserting spaces where necessary - both to
start the comment at the first "//", and in the middle of any following "//"
(turning them into "/ /") to ensure these problems don't occur.

### Number format unification

The assembler in Senbir parses numbers in different ways depending on which
argument of which instruction that number is for - sometimes it expects raw
binary bit strings, sometimes decimal numbers, and somes either can be used,
and which it chooses to use depends on things like the number of digits.

This preprocessor unifies this by specifying a single set of number parsing
rules that it uses everywhere, with checks for whether the given value makes
sense for that particular parameter.

Those parsing rules are specified in such a way that code Senbir's assembler
already understands should still work fine after being passed through the
preprocessor (though it might not _look_ exactly the same).

The parsing rules are:

1. If the value starts with `0x` or `0X`, optionally prefixed by `+` or `-`,
   then remove underscores and parse it as hexadecimal.
2. If the value starts with `0b` or `0B`, optionally prefixed by `+` or `-`,
   then remove underscores and parse it as binary with a placement extension.
3. If the value only contains the digits `0` and `1`, and has exactly as many
   digits (including any leading 0s) as the parameter has bits, then parse it
   as binary (no placement extension needed, as all the digits are there).
4. Otherwise, parse it as signed decimal (with the `+` sign being optional).

Rule 3 requires that we know the bit size of the parameter the value being
parsed is for, and generating the proper output so that Senbir's assembler
understands it also requires knowing the type of that parameter.

Combine those requirements, and we also have enough information to validate
both that the value of each argument is within the possible range for that
parameter, and that the instruction actually has all the required arguments
and no extra ones. Therefore, those things are also checked, to avoid getting
errors in Senbir later.

It is worth noting that where we have to output an argument as bits, negative
values are represented using two's-complement notation, and we accept the full
range of both signed and unsigned numbers for the source value.

#### Binary placement extension

The placement extension for binary numbers is intended for cases where you
don't want to have to specify all the bits of a number, just to determine
where in that number the bits you specified will end up. So, it only comes
into play when you need fewer bits than there are room for in the parameter.

Let's take DATAC as an example, which takes 32 bits, and say that you have
6 bits of actual data, with the rest being zeroes.

The first, and most basic, option is to specify all 32 bits, but that requires
you to add 26 bits of zeroes to the 6 bits you're actually interested in,
which can obscure which bits are actually important. However, in return, you
can place those bits anywhere in the number.

Thus, these two are equivalent:

	DATAC 0b00000000010100001010000000000000
	DATAC 00000000010100001010000000000000

The second option is to specify just the bits you actually need, in which case
they will be placed in the low bits of the result, with zeroes filling the rest.

Thus, these two are equivalent:

	DATAC 0b101101
	DATAC 00000000000000000000000000101101

The third option is for when you want the bits to instead be placed in the
high bits of the result, with zeroes filling the rest. To do this, specify
just the bits you actually need, followed by three periods. 

Thus, these two are equivalent:

	DATAC 0b101101...
	DATAC 10110100000000000000000000000000

The fourth and last option is for when you have bits for both the low and high
end bits of the result, with zeroes filling the middle. To do this, specify
the high bits, followed by three periods, followed by the low bits.

Thus, these two are equivalent:

	DATAC 0b101...101
	DATAC 10100000000000000000000000000101

It is not possible to use more than one set of three periods, as then the
parser could not know how many zeroes you intended each place to have.

### Constant expression evaluation

Sometimes, it is more convenient (or even necessary) for a value to be set
not as a simple number, but as an expression that combines multiple numbers.

A preprocessor can (obviously) only do this for values that are known at the
time of processing, hence the need for all the involved numbers to be
constants, but this is still useful - especially when combined with
@-expressions, which for the purposes of these expressions can usually be
considered constants.

Note that using expressions do not relax the restrictions on @-expressions in
the argument for NILLIST, as they are still evaluated during the first pass.

It is worth noting that the numbers and operations inside an expression are
not restricted by the bit size of the parameter the expression is for while
the evaluation is happening (though the placement extension etc. still uses
the correct size). Instead, those restrictions are only applied to the result
of the expression evaluation, as if that result had been specified directly.

#### General syntax

To be able to find such expressions, in the face of code that might have
several of them per line, it is required for every expression to be enclosed
in parenthesis. This does not relax the requirement for separate arguments to
be separated by whitespace, even if both are expressions - but it does allow
expressions to themselves contain whitespace without having the individual
parts of the expression be considered separate arguments to the instruction.

Also, while parenthesis can be used in the expression (e.g. to override the
default operator precedence), they must be balanced.

The actual numbers used within an expression use the same parser as numbers
outside, as described in the "Number format unification" section.

The supported operators are the ones of basic integer arithmetic:

- `*` for multiplication
- `/` for integer division
- `%` for remainder (or modulo arithmetic)
- `+` for addition
- `-` for subtraction

plus some for doing bitwise logic:

- `~` for bitwise NOT (the only unary operator)
- `&` for bitwise AND
- `|` for bitwise OR (inclusive OR)
- `^` for bitwise XOR (exclusive OR)
- `<<` for shift left
- `>>` for shift right

That the `~` operator is unary means that it does not combine two numbers, but
instead takes the number that comes immediately after it, and does something
to it - in this case, inverts its bits.

#### Operator precedence

This preprocessor uses the underlying expression evaluator of Bash to actually
evaluate the expression (after the numbers have been parsed), so the operator
precedence is tied to that of Bash.

In this list, the operators listed together have the same precedence, while
the overall list is shown in order of decreasing precedence.

- `~` - bitwise negation
- `*`, `/`, `%` - multiplication, division, remainder
- `+`, `-` - addition, subtraction
- `<<`, `>>` - left and right bitwise shift
- `&` - bitwise AND
- `^` - bitwise XOR
- `|` - bitwise OR

As an example, this means that the expression `( 1 << 2 + 1 )` evaluates to 8,
not 5, while the expression `( 1 << 2 | 1 )` does the opposite.

### Minor fixes/improvements

Sometimes, Senbir's assembler allows something it probably shouldn't, or
behaves oddly in corner cases or when given unusual code.

This preprocessor blocks or changes some of those things, to protect the
developer and attempt to make the code do what it appears they intended.

In particular, it:

- blocks instructions with suffixes (Senbir accepts e.g. MOVIES to mean MOVI).
- blocks NILLIST with a negative count (Senbir would add one NIL).
- changes NILLIST 0 into a comment (Senbir would add one NIL).

### Overlays

This feature is meant to handle two related cases, that both occur when the
program you are writing is meant to be stored on the disk drive.

The first case is for the initial program that will be loaded by a classic
boot loader, which is expected to be at the start of the disk, preceded by a
word that tells the loader how long the program is (how many words to load).

The second case is for when your program uses overlays to have more code than
fits in memory at one time, with a classic overlay loader that expects to be
told the address of the overlay to load, and for that overlay to start with a
word that tells the loader what the last address of that overlay is (where to
stop loading words into memory for that overlay).

It turns out that code for the second case can also handle the first case,
since when the start address is 0, the end address is the same as the length.
This is also why a classic overlay loader can also be used as a boot loader.

This preprocessor implements the second case (and thus also the first) by
adding two new instruction words to the assembly language.

Note that this preprocessor also uses overlays as contexts for references to
labels. See the section on references for details.

#### OVERLAY identifier

This instruction is used to start a new overlay, and give it an identifier by
which to refer to it later. That identifier must be unique within the file,
duplicates are not allowed.

In the output, this instruction will be replaced with an overlay header - a
DATAC that contains the last address of this overlay.

If the overlay is not explicitly ended with END_OVERLAY, it runs either until
the next overlay starts, or the end of the file.

##### Example

	OVERLAY main
	// Code here
	OVERLAY overlay1
	// More code here
	END_OVERLAY
	DATAC 00000000000000000000000000000001
	OVERLAY overlay2
	// Even more code

#### END_OVERLAY

This instruction can be used to mark the end of an overlay, if it needs to end
before the start of the next overlay or the end of the file.

This is purely a preprocessor instruction, and does not take up any space in
the final program; it doesn't change the address of any following instruction.

A typical use case for this is to include some data on the disk that you don't
want to be loaded into memory by the overlay loader - e.g. a list that your
program loads into a register one at a time to use for something ephemeral.

##### Example

	OVERLAY main
	// Code to load from disk goes here
	END_OVERLAY
	DATAC 00000000000000000000000000000001
	DATAC 00000000000000000000000000000010

### Labels

In TC-06 assembly programs, one often needs to refer to specific addresses,
both in memory and on disk - e.g. when using MOVI, JMP or GETDATA. Keeping
track of these addresses manually in the face of changing code (and thus
addresses) is both error prone and annoying, especially in large programs.

Labels provide a way to give such addresses an identifer, so that they can be
referenced by that identifier instead of having to specify the numeric address
yourself. (See the section on references for details on how to do that.)

Labels are created by prefixing a line with the label identifier, followed by
a colon. Whitespace is allowed both between and around these tokens.

The label then points to the address of the first instruction that follows it,
whether that is on the same line or a later one.

It is allowed to have multiple labels for the same address, and even to create
more than one on the same line, regardless of it having any other instruction.

Labels are namespaced to the nearest enclosing overlay, if any, or if not, to
the global scope. This means that it is possible to have more than one label
with the same identifier, as long as they are in different overlays - but it
is not allowed to have duplicates within an overlay (or outside any overlays).

##### Example

	OVERLAY main
	one:
	// comment
	two :
	three: four: MOVI 2 0
	five :MOVO 2 0
	six:
	OVERLAY overlay2
	five: JMP 1 0
	seven:
	END_OVERLAY
	eight:five:HLT

Here, the labels:

- one, two, three and four all point to the MOVI instruction
- six points to the start address of overlay2 (the DATAC it was turned into)
- seven and eight both point to the HLT (since END_OVERLAY doesn't take space)
- five points to the MOVO, the JMP or the HLT instruction depending on context

See the section on references for an explanation of how to determine or set
which of the labels named five is being referred to in a given context.

### References to labels and overlays

For the label and overlay identifiers to really be useful, we need a way to
refer to them by that identifier.

This preprocessor provides that by way of @-references.

An @-reference consists of an at-sign "@" followed by the type of reference,
followed by a colon, followed by the identifier you are referring to. When the
identifier is a label identifier, this can further be followed by another
colon, and a context specifier.

At the moment, there are four types of @-references: overlay, disk, local and
relative. All of these except the overlay type refer to label identifiers.

With one exception, @-references can refer to identifiers that were created
anywhere in the file. That exception is in the argument for NILLIST.

In the argument for NILLIST, only identifiers that were created earlier in the
file can be used, as that argument is processed during the first pass, before
later identifiers are known. This is done because the value of that argument
affects the location of every identifier that is created after that NILLIST.
Accepting those identifiers would thus easily lead to cases where their actual
addresses cannot be resolved, because they would depend on their own location.

#### The "overlay" reference type

This type of reference is used to get the disk address of an overlay - in
other words, where on the disk that overlay starts.

As such, the identifier is here an overlay identifier, and no context
specifier is accepted since the overlay identifiers are always global.

The typical use case for this is to send that address to the overlay loader.

##### Example

	OVERLAY main
	JMP 0 2
	DATAC @overlay:myFunction // The address of the myFunction overlay
	MOVI 2 1 // Load the address into R2
	JMP 3 9  // Call the overlay loader
	OVERLAY myFunction
	JMP 0 2
	DATAC @overlay:main // The address of the main overlay

Assuming the overlay loader is reached by `JMP 3 9`, this code will end up
repeatedly loading and executing the two overlays, going back and forth
between them, since the only difference in the code is the overlay address.

#### The "disk" reference type

This type of reference is used to get the disk address of a label - in other
words, where on the disk the thing that the label points to is.

As such, the identifier is here a label identifier, and a context specifier
can be given. If it is not given, the default context specifier is here "*".

A basic use case for this is to load some data directly from the disk, without
first loading it into memory as part of the overlay.

##### Example

	OVERLAY main
	JMP 0 2          // Skip to code
	DATAC @disk:data // The disk address of the data
	MOVI 2 1         // Load the address into R2
	GETDATA 1 3 2    // Load the data from disk
	// Do something with that data
	END_OVERLAY
	data: DATAC 00000001000000010000000100000001

#### The "local" reference type

This type of reference is used to get the memory address of a label - in other
words, where in memory the thing that the label points to is, or equivalently,
where it is relative to the overlay that it is in.

As such, the identifier is here a label identifier, and a context specifier
can be given. If it is not given, the default context specifier is here the
overlay identifier of the overlay that the @-reference is in.

A basic use case for this is as the target of a JMP, or to move data between
memory and registers.

##### Example

	OVERLAY main
	loop: // Do some stuff here
	MOVI 2 @local:myValue // Load myValue into R2
	IFJMP 1 @local:loop 0 // Jump to loop if R2 == R3
	HLT
	myValue: DATAC 00000000000000000000000000000101

#### The "relative" reference type

This type of reference is used to get the relative address of a label, as
compared to the address of the @-reference - or in other words, how far away
from the @-reference that label is.

As such, the identifier is here a label identifier, and a context specifier
can be given. If it is not given, the default context specifier is here the
overlay identifier of the overlay that the @-reference is in.

One possible use case for this is as the target of a relative JMP. However, it
is generally safer to use a non-relative JMP with an @local reference, since
that won't break if the label is moved to the other side of the JMP without
updating the JMP direction accordingly.

##### Example

	OVERLAY main
	// Do stuff
	IFJMP 0 @relative:skip 0 // Jump forward to skip if R2 == R3
	// Do more stuff
	skip:

#### The context specifier

The context specifier identifies which context to try to find the given label
identifier in, as a way to avoid getting the wrong address if there are other
contexts that have the same identifier.

When it is not given, there's a default value that depends on the reference
type, so see the section for that reference type. Usually that default is what
you want, but in some cases you may need to specify otherwise.

Since each overlay is a separate context, the overlay identifiers are valid
context identifiers as well, and specify that the label should be found in
that overlay.

In addition, there are two predefined context specifiers:

- "" (the empty string), which means to look outside of all the overlays.
- "*" (a star), which means to look in all contexts.

If looking in all contexts, then the first matching label identifier is
returned, and if there is more than one match, then a warning is printed.

Note that this is a warning, not an error, so it will not stop the processing.

##### Example

Note that this is not meant as an example of _good_ code, just an example of
ways the context specifier can be used.

	OVERLAY main
	MOVI 1 @local:addr   // R1 = address of global "data"
	GETDATA 1 3 1        // R1 = value of global "data"
	MOVO 1 @local:data   // save R1 into local "data" (no trailing ":")
	MOVI 2 @local:next:* // R2 = address of overlay "second" (no warning here)
	JMP 3 9              // Load overlay "second"
	addr: DATAC @disk:data: // Address of global "data" (due to trailing ":")
	next: DATAC @overlay:second // Address of overlay "second"
	data: NIL                   // Memory location to save the data in
	// Note that the second overlay is not long enough to overwrite this data
	OVERLAY second
	MOVI 1 @local:data:main // R1 = value of local "data" (not overwritten)
	MATH 1 1 0              // R1 += R1 : double it
	MOVO 1 @local:data:*    // set value of local "data" (generates a warning)
	HLT
	END_OVERLAY
	data: DATAC 00000000000000000000000000000010
