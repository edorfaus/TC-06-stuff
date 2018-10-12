This directory contains some programs based around using sine/cosine values.

They are designed to work in the default mode of Senbir (using the built-in
bootloader), but will generally also work on larger modes.

Due to the limitations of that mode, the values are generally precomputed and
included in a lookup table of values rather than calculated on the fly.

While I haven't tried to implement them, I believe that most of the algorithms
would probably take more space to implement than the table does, and that they
would also be far slower to use.

## cosinewave.txt

This program draws a cosine wave to the screen.

## sinewave.txt

This program draws a sine wave to the screen, while using the same lookup table
as cosinewave.txt does.

## circle-1.txt

This program draws a circle to the screen.

This uses separate registers for X and Y.

## circle-2.txt

This program draws a circle to the screen.

This combines the X and Y offsets into one register, to save a cycle in the
drawing loop.

## circle-3.txt

This program draws a circle to the screen.

This adds one bit of resolution to the angular position. This makes the drawing
happen slower, without affecting the final result, but is a step on the way for
the equivalent being done in the Lissajous curve drawing programs.

## lissajous-1.txt

This program draws a [Lissajous curve] to the screen.

[Lissajous curve]: https://en.wikipedia.org/wiki/Lissajous_curve

## lissajous-2.txt

This program draws a [Lissajous curve] to the screen.

This is a different curve to the one lissajous-1.txt draws, while the program
is identical except for using different curve parameters (two DATAC values).

## lissajous-grid.txt

This program draws a [Lissajous curve] to the screen based on curve parameters
given at runtime by the user, and allows the user to keep drawing new ones.

The underlying idea is that of a grid of Lissajous curves, with each row/column
increasing the multiplier in that direction by one, as in [The Coding Train]'s
[Coding Challenge #116] where he makes a grid of them.

[The Coding Train]: https://thecodingtrain.com/
[Coding Challenge #116]: https://www.youtube.com/watch?v=--6eyLO78CY

The default mode does not have enough monitor resolution to show several such
curves at the same time (it's arguable whether it really has enough to show
even one), so instead the grid is here virtual, allowing you to move around in
it and showing one at a time. The grid is 8 by 8.

Moving around on the grid is done using IJKL - J/L for X and I/K for Y.

(Note that the top half of each grid direction may have pixels being skipped,
due to the limited angular resolution being used to draw the curve.)

In addition, this program allows you to set the (initial) angular offset
between X and Y, between 0 and 31 inclusive (each step being 11.25 degrees).

This is done using WASD, where W/S decreases/increases the offset by 1, and A/D
decreases/increases the offset by 8. (These numbers/keys makes more sense while
the program is running, as they're based on how the current value is shown.)

Drawing the curve for the currently selected arguments is done using Enter.
