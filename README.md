# NumWorks Rasterizer

External app for NumWorks made in Zig and based on https://github.com/numworks/epsilon-sample-app-cpp

## Running on your calculator

Make sure you have NodeJS installed first

1. Connect your calculator
2. As for most Zig projects, you only need to execute
```sh
zig build run -Drelease-fast
```
(`-Drelease-fast` is recommended even in debug for the app to run at reasonable speed)
