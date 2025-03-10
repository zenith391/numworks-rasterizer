const std = @import("std");
const bmp = @import("bmp.zig");
const eadk = @import("eadk.zig");
const lib = @import("lib.zig");
const Texture = lib.Texture;
const EadkColor = eadk.EadkColor;

const wall_2_array = makeImageArray(@embedFile("assets/wall_2.bmp"));
pub const wall_2 = makeTexture(wall_2_array);
const grass_side_array = makeImageArray(@embedFile("assets/grass_side.bmp"));
pub const grass_side = makeTexture(grass_side_array);
const grass_top_array = makeImageArray(@embedFile("assets/grass_top.bmp"));
pub const grass_top = makeTexture(grass_top_array);
const dirt_array = makeImageArray(@embedFile("assets/dirt.bmp"));
pub const dirt = makeTexture(dirt_array);
const stone_array = makeImageArray(@embedFile("assets/stone.bmp"));
pub const stone = makeTexture(stone_array);
const sand_array = makeImageArray(@embedFile("assets/sand.bmp"));
pub const sand = makeTexture(sand_array);
const gravel_array = makeImageArray(@embedFile("assets/gravel.bmp"));
pub const gravel = makeTexture(gravel_array);

fn MakeImageArrayReturn(comptime bmpFile: []const u8) type {
    @setEvalBranchQuota(100000);
    const image = bmp.comptimeRead(bmpFile) catch unreachable;
    const size = image.width * image.height;
    return struct { width: u16, height: u16, colors: [size]EadkColor };
}

fn makeImageArray(comptime bmpFile: []const u8) MakeImageArrayReturn(bmpFile) {
    @setEvalBranchQuota(100000);
    const image = bmp.comptimeRead(bmpFile) catch unreachable;
    var pixels: [image.height * image.width]EadkColor = undefined;
    var y: usize = 0;
    while (y < image.height) : (y += 1) {
        var x: usize = 0;
        while (x < image.width) : (x += 1) {
            const rgb: u24 =
                @as(u24, image.data[y * image.width * 3 + x * 3 + 0]) << 0 // blue
            | @as(u24, image.data[y * image.width * 3 + x * 3 + 1]) << 8 // green
            | @as(u24, image.data[y * image.width * 3 + x * 3 + 2]) << 16 // red
            ;
            pixels[y * image.width + x] = eadk.rgb(rgb);
        }
    }

    return .{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .colors = pixels,
    };
}

fn makeTexture(comptime image_array: anytype) Texture {
    return .{
        .width = image_array.width,
        .height = image_array.height,
        .colors = &image_array.colors,
    };
}
