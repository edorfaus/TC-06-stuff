Snake
=====

This is an implementation of the classic Snake game, for the default mode of
Senbir.

## snake.txt

This variant is built with my preprocessor, and depends on having my overlay
loader in ROM (as bootloader).

The game is awkwardly slow (taking about 5-6 seconds per step), and is not
quite bug-free, but generally works, and is playable given some patience.

## snake-dr.txt

This variant is also built with my preprocessor, but it does not use overlays,
instead being based on my disk-runner - so it can use the built-in bootloader.

The game is still rather slow, though better than the first variant (taking
almost 2 seconds per step, or double that when hitting food or pressing keys).

I don't know of any bugs in this variant, other than it being rather slow.

## Controls

The game is controlled using the keyboard.

During regular gameplay, a regular WASD control scheme is used, although only
lowercase is supported.

When you have crashed (into a wall or yourself), as indicated by the top-left
pixel being black, then `r` resets it and starts a new game.
