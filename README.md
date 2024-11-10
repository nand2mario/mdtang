
# MDTang - MegaDrive/Genesis for Sipeed Tang FPGA boards

<img src='doc/mdtang-0.1.jpg' width="300" />

This is a port of the [Genesis-MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer) core to Sipeed FPGA boards including Tang Mega 60K, 138K and 138K Pro. It is the latest addition following [NESTang](https://github.com/nand2mario/nestang), [SNESTang](https://github.com/nand2mario/snestang) and [GBATang](https://github.com/nand2mario/gbatang).

This is a mostly verbatim port. So game compatibility should be good. However, many features are not activated yet, such as country settings (set to Americas/NTSC), audio filters and SRAM saves. These features will be enabled over time.

Follow [me](https://x.com/nand2mario) on X to get updates.

## Instructions

In addition to the FPGA board, you also need a [Tang DS2 Pmod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html), a [Tang SDRAM Pmod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html), a [DS2 controller](https://en.wikipedia.org/wiki/DualShock), and finally a MicroSD card. Then assemble the parts as shown in the picture above.

Then follow these steps to install the core (for detailed instructions, for now refer to [SNESTang installation](https://github.com/nand2mario/snestang/blob/main/doc/installation.md)),

1. Download and install [Gowin IDE 1.9.9](https://cdn.gowinsemi.com.cn/Gowin_V1.9.9_x64_win.zip).

2. Download a [MDTang release](https://github.com/nand2mario/mdtang/releases).

3. Use Gowin programmer to program `firmware.bin` to on-board flash, at starting address **0x500000**.

4. Again using the Gowin programmer, program `mdtang_m138k.fs` or `mdtang_m138kpro.fs` to on-board flash at starting address 0x000000.

Now the core should be ready. Just load roms (`.bin`) on the SD card and enjoy. It supports two DS2 controllers acting as 3 button Sega gamepads (square button for A, X for B, circle button for C).

## Documentation

* [Blast Processing on the Tang FPGA boards](https://nand2mario.github.io/posts/2024/mdtang/)

## Acknowledgements
* [Genesis-MiSTer core](https://github.com/MiSTer-devel/Genesis_MiSTer)
