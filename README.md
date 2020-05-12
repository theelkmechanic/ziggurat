# Ziggurat -- A Commander X-16 Z-machine

Since the dawn of time, man has searched for the ideal platform to play the Infocom classic, *Leather Goddesses of Phobos*. Now, with the imminent introduction of the Commander X-16, that day has finally arrived. "But," you say, "there is no Z-machine available for the Commander X-16!" Well, look no further! (Actually, look further. This one is pretty terrible.)

Ziggurat is a Z-machine interpreter written from scratch in 65C02 assembly language, based on the [Z-machine Standards Document version 1.1](http://inform-fiction.org/zmachine/standards/z1point1/index.html). The main impetus behind this project is as follows:
* Learning/remembering 6502 assembly
* Learning how to program for the Commander X-16 (using banked memory, VERA, etc.)
* I've just always wanted to write a Z-machine

A lot of things work at this point for version 3 games. Lots of things still to do, though:
* Redo text mode layering/font using 2bpp tiles for the overlay layer to increase font size
* Split windowing code out into a separate library for easier reusability
* Implementing opcodes for higher level games (Note: This includes actually checking the version of the game to see if the opcode is supported)
* Blorb/Quetzal file support
* Graphics mode for V6 games
* Sound?

## Getting Started

### Prerequisites

You will need the following to build and play with Ziggurat:
* [cc65](https://cc65.github.io/) assembler
* GNU Make
* Some Z-code game files (I've been testing with the games from Activision's *Classic Text Adventure Masterpieces of Infocom*, but there are lots of game files out there.)
* At least release 37 of the Commander X-16 emulator
* Possibly a couple ROM patches I did at [my own fork of the ROM](https://github.com/theelkmechanic/x16-rom) to fix a couple CBDOS issues with reading files.

### Building/Testing Ziggurat

Building should be as simple as running `make`. I've been developing on Windows 10, and I can say that creating SD card images to test with is a pain unless you install Windows Subsystem for Linux 2 (which requires the Windows 10 2004 release). So it may be simpler to just develop/test on Linux instead.

To make a SD card test image, I use the following little script in WSL 2 Debian:
```
#!/bin/sh
dd if=/dev/zero of=card.img bs=1M count=1024
printf 'n\n\n\n\n\nt\nc\nw\n' | fdisk card.img
LOPNAM=`losetup -f`
sudo losetup -o 1048576 $LOPNAM card.img
sudo mkfs -t vfat $LOPNAM
sudo losetup -d $LOPNAM
sudo mount -o rw,loop,offset=$((2048*512)) card.img card
sudo cp ziggurat.cx16 card/ZIGGURAT
sudo cp dats/* card
sudo umount card
```
That copies the Ziggurat program and all the game files (which I keep in a subdirectory) onto a 1GB SD card image that I can use in the emulator by running `../x16emu.exe -scale 2 -sdcard D:\\x16\\ziggurat\\card.img -debug &`. (The `-scale 2` is because my monitor is 1440p and my eyes are old.)

## License

The license for this code is non-existent. It's all hereby released into the public domain. Use it as you like. (Although why would you want to?)

## Acknowledgements

* Daniel Hotop, for suggesting using 2bpp text modes to increase the font size
