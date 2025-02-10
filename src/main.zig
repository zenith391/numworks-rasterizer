const std = @import("std");
const eadk = @import("eadk.zig");
const resources = @import("resources.zig");
const za = @import("zalgebra");
const Fp32 = @import("lib.zig").Fp32;

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;

pub const APP_NAME = "Mario Kart";

pub export const eadk_app_name: [APP_NAME.len:0]u8 linksection(".rodata.eadk_app_name") = APP_NAME.*;
pub export const eadk_api_level: u32 linksection(".rodata.eadk_api_level") = 0;

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // afficher ce qui a été rendu pour meilleur déboguage
    eadk.display.swapBuffer();

    var buf: [512]u8 = undefined;
    const ra = @returnAddress() - @intFromPtr(&panic);
    const str = std.fmt.bufPrintZ(&buf, "@ 0x{x} (frame {d})", .{ ra, t }) catch unreachable;

    var i: usize = 0;
    while (true) {
        eadk.display.drawString(@as([:0]const u8, @ptrCast(msg)), .{ .x = 0, .y = 0 }, false, eadk.rgb(0), eadk.rgb(0xFFFFFF));
        eadk.display.drawString(str, .{ .x = 0, .y = 16 }, false, eadk.rgb(0), eadk.rgb(0xFFFFFF));
        eadk.display.waitForVblank();

        const kbd = eadk.keyboard.scan();
        if (kbd.isDown(.Backspace) or i > 200) {
            break;
        }
        i += 1;
    }
    @breakpoint();
    unreachable;
}

const GameState = enum { MainMenu, Playing };

var state = GameState.MainMenu;
var fps: f32 = 40;

const DELTA_SCALE = 1.0;
const SPRITE_TRANSPARENT_COLOR = eadk.rgb(0x980088);

const Object = struct {
    texture: u8,
    x: f32,
    y: f32,
    distance: f32 = undefined,

    pub fn sortDsc(_: void, a: Object, b: Object) bool {
        return a.distance > b.distance;
    }

    pub fn sortAsc(_: void, a: Object, b: Object) bool {
        return a.distance < b.distance;
    }
};

// State for a wall to not recompute it twice
const WallState = struct {
    drawStart: u16,
    drawEnd: u16,
    textureId: u8,
    darken: bool,
    texPos: f32,
    texX: u8,
    step: f32,
};
var objects = std.BoundedArray(Object, 16).init(0) catch unreachable;

fn draw() void {
    // @setRuntimeSafety(false);

    if (state == .MainMenu) {
        // afficher menu
        eadk.display.fillRectangle(
            .{
                .x = 0,
                .y = 0,
                .width = eadk.SCENE_WIDTH,
                .height = eadk.SCENE_HEIGHT,
            },
            eadk.rgb(0x000000),
        );
        return;
    }

    if (eadk.display.isUpperBuffer) {
        eadk.display.fillRectangle(.{
            .x = 0,
            .y = 0,
            .width = eadk.SCENE_WIDTH,
            .height = eadk.SCREEN_HEIGHT / 2,
        }, eadk.rgb(0x383838));
    }

    if (!eadk.display.isUpperBuffer) {
        eadk.display.fillRectangle(.{
            .x = 0,
            .y = eadk.SCENE_HEIGHT / 2,
            .width = eadk.SCENE_WIDTH,
            .height = eadk.SCENE_HEIGHT / 2,
        }, eadk.rgb(0x383838));
    }

    // TODO: dessin sprites + terrain
}

const big_ol_data: [512 * 1024]u8 = undefined;

var t: u32 = 0;
fn eadk_main() void {
    _ = big_ol_data;

    var prng = std.Random.DefaultPrng.init(eadk.eadk_random());
    const random = prng.random();
    _ = random;

    while (true) : (t += 1) {
        const start = eadk.eadk_timing_millis();

        const kbd = eadk.keyboard.scan();

        if (state == .Playing) {
            // Dessiner le haut
            eadk.display.isUpperBuffer = true;
            eadk.display.clearBuffer();
            draw();
            eadk.display.swapBuffer();

            // Puis, dessiner le bas
            eadk.display.isUpperBuffer = false;
            eadk.display.clearBuffer();
            draw();
            eadk.display.swapBuffer();
        } else {
            // eadk.eadk_display_push_rect_uniform(.{ .x = 0, .y = 0, .width = eadk.SCREEN_WIDTH, .height = eadk.SCREEN_HEIGHT }, eadk.rgb(0x000000));
        }

        var buf: [100]u8 = undefined;
        if (state == .MainMenu) {
            eadk.display.drawString("Mario Kart", .{ .x = eadk.SCREEN_WIDTH / 2 - "Mario Kart".len * 10 / 2, .y = 0 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));
            eadk.display.drawString("(c) Randy", .{ .x = 0, .y = 20 }, false, eadk.rgb(0x888888), eadk.rgb(0x000000));
            eadk.display.drawString("EXE to play", .{ .x = 0, .y = 220 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x00000));

            if (kbd.isDown(.Exe)) {
                state = .Playing;
                t = 0;
            }
        }
        if (kbd.isDown(.Back)) {
            break;
        }

        // Benckmark: FP32 multiplications
        // const start = eadk.eadk_timing_millis();
        // var x: Fp32 = Fp32.fromInt(5000);
        // for (0..10000) |_| {
        //     x = x.mul(Fp32.L(1.5)).div(Fp32.L(2));
        //     std.mem.doNotOptimizeAway(x);
        // }
        // for (0..100000) |_| {
        //     x = x.add(Fp32.L(0.1));
        //     std.mem.doNotOptimizeAway(x);
        // }
        // const end = eadk.eadk_timing_millis();
        // const diff = end - start;
        // const slice = std.fmt.bufPrintZ(&buf, "fp32 mult + add: {d} ms", .{diff}) catch unreachable;
        // eadk.display.drawString(slice, .{ .x = 0, .y = 100 }, false, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));

        // const start2 = eadk.eadk_timing_millis();
        // var y: f32 = 5000;
        // for (0..10000) |_| {
        //     y = y * 1.5 / 2.0;
        //     std.mem.doNotOptimizeAway(y);
        // }
        // for (0..100000) |_| {
        //     y += 1;
        //     std.mem.doNotOptimizeAway(y);
        // }
        // const end2 = eadk.eadk_timing_millis();
        // const diff2 = end2 - start2;
        // const slice2 = std.fmt.bufPrintZ(&buf, "f32 mult + add: {d} ms", .{diff2}) catch unreachable;
        // eadk.display.drawString(slice2, .{ .x = 0, .y = 120 }, false, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));

        const frameFps = 1.0 / (@as(f32, @floatFromInt(@as(u32, @intCast(end - start)))) / 1000);
        fps = fps * 0.9 + frameFps * 0.1; // faire interpolation linéaire vers la valeur fps
        if (frameFps > 40) eadk.display.waitForVblank();
    }
}

export fn main() void {
    eadk_main();
}

comptime {
    _ = @import("c.zig");
}
