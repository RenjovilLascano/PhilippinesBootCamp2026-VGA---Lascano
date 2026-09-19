<!---
This file is used to generate your project datasheet.
-->

## How it works

A rhythm game drawn live on VGA (640x480, 25.175 MHz). Notes in three lanes
(left, middle, right) fall towards a hit line in time with a beat that the
chip plays itself. Each note is worth 1, 2, 4 or 8 eighth notes. Hit it on
time and the two dancers perform that many dance steps; miss it and the stage
turns red until your next hit.

## How to test

Connect a TinyVGA Pmod to the outputs and a TT Audio Pmod to the bidirectional
pins. Press START (`ui[3]`), then press LEFT, MIDDLE or RIGHT (`ui[0..2]`)
when a note reaches the hit line. `ui[7]` mutes the sound.

## External hardware

TinyVGA Pmod, TT Audio Pmod, four push buttons.
