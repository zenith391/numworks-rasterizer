# NumWorks Rasterizer

Zig Version: `0.15.2`

A simple rasterizer for NumWorks calculators, made to test the feasability of running 3D graphics
on this hardware.

## Design Decisions
- A fixed-point number implementation has been added, as it has a much higher performance than
  floating-point numbers on the CPU (Cortex M7). Using a lousy benchmark quickly tested on the
  calculator, fixed point computations are about 10 to 15 times faster than floating point.
  An excellent ressource I like discussing floating point is http://x86asm.net/articles/fixed-point-arithmetic-and-tricks/
- All vector operations use fixed point numbers, including matrix multiplication
- Linear interpolation is used for triangles, even if that's incorrect (and leaves to the warping
  walls effect like in PS1 games) as it's much better for performance

## Running on your calculator

Make sure you have NodeJS installed first

1. Connect your calculator
2. You only need to execute
```sh
zig build run -Doptimize=ReleaseFast
```
(`-Doptimize=ReleaseFast` is recommended even in debug for the app to run at reasonable speed)
