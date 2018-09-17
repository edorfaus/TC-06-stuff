Snake
=====

This is an implementation of the classic Snake game, for the default mode of
Senbir.

It is built with my preprocessor, and depends on having the overlay loader in
ROM (as bootloader).

The game is awkwardly slow, and not quite bug-free, but generally works, and
is playable given some patience.

## Controls

The game is controlled using the keyboard.

During regular gameplay, a regular WASD control scheme is used, although only
lowercase is supported.

When you have crashed (into a wall or yourself), as indicated by the top-left
pixel being black, then `r` resets it and starts a new game.
