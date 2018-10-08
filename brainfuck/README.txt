This is an interpreter for the esoteric programming language "brainfuck".

For more information on the language, see: https://esolangs.org/wiki/Brainfuck

It tries to follow the implementor recommendations, but see the notes below.

This program assumes that it is booted with the overlay loader in RAM.

It works in Senbir's default mode, though only with limited space for the BF
program; that mode has 30 words available to be split between program and tape.

However, the interpreter itself is not limited to that, so in a mode with a
larger disk drive all the extra space is available for the BF program's use.

See the bottom of the interpreter for where/how to add the BF program and data.

Notes on this implementation of brainfuck:

All the basic commands: <>+-,.[] are implemented, and all other characters
are considered to be comments.

If the BF program finishes (runs off the end), the interpreter halts the PC.

If a branch instruction ("[" or "]") would jump but fails to find a matching
counterpart, then the top-left pixel is set to dark green and the PC is halted.

Each memory cell is 8 bits, and wraps on overflow and underflow. The data
pointer is initially placed at the leftmost end of the tape, and memory cells
to the left of that are not supported.

However, this interpreter does not prevent you from moving the pointer to the
left of the start of the tape, and that's where the BF program itself is stored
- which means you can technically write and run self-modifying BF programs with
this interpreter (though you have to be careful with some of its requirements).

In fact, beyond the BF program (further to the left) is the interpreter itself,
which is also accessible in the same way, and thus technically modifiable, but
since it tends to rely on 32-bit values instead of 8-bit ones, it is probably
not possible to significantly modify it without destroying it.

The size of the tape (to the right) is determined by the available space on the
disk after the interpreter and BF program. Each word of disk space corresponds
to one memory cell.

Unlike standard brainfuck, the memory cells are not automatically zeroed when
the interpreter starts; it relies on the area already being zeroes (as per
NILLIST). This enables use of a tape that contains initial data for the program
to work on, but also means that a program being re-run without first re-writing
the disk cannot rely on the tape being all zeroes to start with.

Trying to write to a memory cell that does not exist will likely cause the PC
to stop (that is how Senbir reacts to trying to write beyond the the disk).

Output is sent to the (virtual) monitor, not as characters (since the monitor
doesn't do those natively and is rather too low-resolution anyway), but as a
visual representation of the bits in the sent byte. For each byte that is
output, one column is drawn (starting at the left, wrapping at the right), with
the low bit at the top and the high bit at the bottom; white is 1 and black 0.

Input is taken from the (virtual) keyboard in a non-line-buffered blocking
fashion, meaning that the BF program stops and waits for input if none is
available, but receives keys immediately without the user pressing enter.

This means that the user can always provide more input, so the concept of EOF
does not apply, so the controversy of how to return EOF is avoided completely
since EOF does not exist (and thus is simply never returned).

When the program is trying to read input, the top-right pixel is set to bright
green, and once input is received, it is cleared to black. This might overwrite
the low bit of an output byte, so you may need to watch carefully to catch it.

The enter key (which Senbir gives value 13) is mapped to value 10 (BF newline).

Other characters use the native character set of the (virtual) host.
