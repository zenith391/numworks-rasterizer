const std = @import("std");
const eadk = @import("eadk.zig");
const resources = @import("resources.zig");
const lib = @import("lib.zig");
const Fp32 = lib.Fp32;
const Vec4 = lib.Vec4;
const Mat4x4 = lib.Mat4x4;
const Triangle = lib.Triangle;

pub const APP_NAME = "Rasterizer";

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

const Camera = struct {
    position: Vec4 = Vec4.L(0, 0, 0, 0),
};

var state = GameState.MainMenu;
var fps: f32 = 40;
var camera: Camera = .{};

const model_vertices = [_]Vec4{
    // front face
    Vec4.L(0.5, 0.5, 0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, 0.5, 1),
    // back face
    Vec4.L(0.5, 0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    // left face
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    // right face
    Vec4.L(0.5, 0.5, 0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(0.5, 0.5, 0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    // top face
    Vec4.L(-0.5, -0.5, 0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, -0.5, 0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    // bottom face
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
};

fn draw() void {
    // @setRuntimeSafety(false);

    if (state == .Playing) {
        const angle = Fp32.fromInt(@intCast(t)).div(Fp32.L(25));
        const model_matrix = Mat4x4.rotation(angle, Vec4.L(0, 1, 0, 0))
            .mul(
            Mat4x4.rotation(angle.div(Fp32.L(2)), Vec4.L(1, 0, 0, 0)),
        )
            .mul(
            Mat4x4.translation(Vec4.L(0, 0, -10, 0)),
        );
        const view_matrix = Mat4x4.translation(camera.position.scale(Fp32.L(-1)));
        const perspective_matrix = Mat4x4.perspective(std.math.degreesToRadians(70.0), 320.0 / 240.0, 0.1, 100);
        var M = Mat4x4.identity();
        M = M.mul(model_matrix);
        M = M.mul(view_matrix);
        M = M.mul(perspective_matrix);

        // TODO: use painter's algorithm
        var prng = std.Random.Xoroshiro128.init(0);
        const random = prng.random();
        inline for (0..model_vertices.len / 3) |i| {
            const a = M.project(model_vertices[i * 3 + 0]);
            const b = M.project(model_vertices[i * 3 + 1]);
            const c = M.project(model_vertices[i * 3 + 2]);
            const tri = (Triangle{ .a = a, .b = b, .c = c }).projected();
            tri.draw(eadk.rgb(random.int(u24)));
            // tri.drawWireframe(eadk.rgb(0xFF0000));
        }
        // var buf: [100]u8 = undefined;
        // {
        //     const slice = std.fmt.bufPrintZ(&buf, "a: {d:.1}, {d:.1}, {d:.1}, {d:.1}", .{ tri.a.x.toFloat(), tri.a.y.toFloat(), tri.a.z.toFloat(), tri.a.w.toFloat() }) catch unreachable;
        //     eadk.display.drawString(slice, .{ .x = 0, .y = 0 }, false, eadk.rgb(0xFFFFFF), 0);
        // }
        // {
        //     const slice = std.fmt.bufPrintZ(&buf, "b: {d:.1}, {d:.1}, {d:.1}, {d:.1}", .{ tri.b.x.toFloat(), tri.b.y.toFloat(), tri.b.z.toFloat(), tri.b.w.toFloat() }) catch unreachable;
        //     eadk.display.drawString(slice, .{ .x = 0, .y = 10 }, false, eadk.rgb(0xFFFFFF), 0);
        // }
        // {
        //     const slice = std.fmt.bufPrintZ(&buf, "c: {d:.1}, {d:.1}, {d:.1}, {d:.1}", .{ tri.c.x.toFloat(), tri.c.y.toFloat(), tri.c.z.toFloat(), tri.c.w.toFloat() }) catch unreachable;
        //     eadk.display.drawString(slice, .{ .x = 0, .y = 20 }, false, eadk.rgb(0xFFFFFF), 0);
        // }
        // {
        //     const pos = camera.position;
        //     const slice = std.fmt.bufPrintZ(&buf, "camera: {d:.1}, {d:.1}, {d:.1}, {d:.1}", .{ pos.x.toFloat(), pos.y.toFloat(), pos.z.toFloat(), pos.w.toFloat() }) catch unreachable;
        //     eadk.display.drawString(slice, .{ .x = 0, .y = 30 }, false, eadk.rgb(0xFFFFFF), 0);
        // }
        // tri.drawWireframe(eadk.rgb(0xFF0000));
    }
}

var t: u32 = 0;
fn eadk_main() void {
    while (true) : (t += 1) {
        const start = eadk.eadk_timing_millis();
        const kbd = eadk.keyboard.scan();
        if (kbd.isDown(.Back)) {
            break;
        }

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

        var buf: [100]u8 = undefined;
        if (state == .MainMenu) {
            eadk.display.drawString("Rasterizer", .{ .x = eadk.SCREEN_WIDTH / 2 - "Rasterizer".len * 10 / 2, .y = 0 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));
            eadk.display.drawString("EXE to play", .{ .x = 0, .y = 220 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x00000));

            if (kbd.isDown(.Exe)) {
                state = .Playing;
                t = 0;
            }
        }

        const speed = 0.1;
        if (kbd.isDown(.Up)) {
            camera.position = camera.position.add(Vec4.L(0, 0, -speed, 0));
        }
        if (kbd.isDown(.Left)) {
            camera.position = camera.position.add(Vec4.L(-speed, 0, 0, 0));
        }
        if (kbd.isDown(.Down)) {
            camera.position = camera.position.add(Vec4.L(0, 0, speed, 0));
        }
        if (kbd.isDown(.Right)) {
            camera.position = camera.position.add(Vec4.L(speed, 0, 0, 0));
        }

        const end = eadk.eadk_timing_millis();
        const frameFps = 1.0 / (@as(f32, @floatFromInt(@as(u32, @intCast(end - start)))) / 1000);
        fps = fps * 0.9 + frameFps * 0.1; // faire interpolation linéaire vers la valeur fps
        {
            const slice = std.fmt.bufPrintZ(&buf, "fps: {d:.1}", .{fps}) catch unreachable;
            eadk.display.drawString(
                slice,
                .{ .x = eadk.SCREEN_WIDTH - @as(u16, @intCast(slice.len)) * 8, .y = 0 },
                false,
                eadk.rgb(0xFFFFFF),
                eadk.rgb(0x000000),
            );
        }
        if (fps > 40) eadk.display.waitForVblank();
        eadk.display.waitForVblank();
    }
}

export fn main() void {
    eadk_main();
}

comptime {
    _ = @import("c.zig");
}
