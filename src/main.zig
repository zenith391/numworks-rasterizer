const std = @import("std");
const eadk = @import("eadk.zig");
const resources = @import("resources.zig");
const lib = @import("lib.zig");
const Fp32 = lib.Fp32;
const Vec2 = lib.Vec2;
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
    pitch: Fp32 = Fp32.L(0),
    yaw: Fp32 = Fp32.L(0),
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

const tex_coords = [_]Vec2{
    Vec2.L(1.0, 0.0),
    Vec2.L(1.0, 1.0),
    Vec2.L(0.0, 0.0),
    Vec2.L(0.0, 0.0),
    Vec2.L(1.0, 1.0),
    Vec2.L(0.0, 1.0),
};

fn draw() void {
    // @setRuntimeSafety(false);

    if (state == .Playing) {
        // TODO: use painter's algorithm
        var prng = std.Random.Xoroshiro128.init(100);
        const random = prng.random();
        const view_matrix =
            Mat4x4.rotation(camera.yaw, Vec4.L(1, 0, 0, 0))
            .mul(Mat4x4.rotation(camera.pitch, Vec4.L(0, 1, 0, 0)))
            .mul(Mat4x4.translation(camera.position.scale(Fp32.L(-1))));
        const perspective_matrix = Mat4x4.perspective(std.math.degreesToRadians(50.0), 320.0 / 240.0, 0.5, 20);
        // premultiplied matrix
        const PM = perspective_matrix.mul(view_matrix);

        for (0..3) |j| {
            for (0..3) |k| {
                const x_offset = Fp32.fromInt(@intCast(j)).sub(Fp32.L(5));
                const z_offset = Fp32.fromInt(@intCast(k)).sub(Fp32.L(15));
                const model_matrix =
                    Mat4x4.translation(Vec4.init(x_offset, Fp32.L(0), z_offset, Fp32.L(0)));
                const M = PM.mul(model_matrix);
                inline for (0..model_vertices.len / 3) |i| {
                    const a = M.project(model_vertices[i * 3 + 0]);
                    const b = M.project(model_vertices[i * 3 + 1]);
                    const c = M.project(model_vertices[i * 3 + 2]);
                    const ta = tex_coords[(i * 3) % 6 + 0];
                    const tb = tex_coords[(i * 3) % 6 + 1];
                    const tc = tex_coords[(i * 3) % 6 + 2];
                    const tri = (Triangle{
                        .a = a,
                        .b = b,
                        .c = c,
                        .ta = ta,
                        .tb = tb,
                        .tc = tc,
                    }).projected();
                    tri.draw(random.int(u16), true, resources.wall_2);
                    // tri.drawWireframe(eadk.rgb(0xFF0000));
                }
            }
        }

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

        const speed = Fp32.L(0.1);
        const angular_speed = Fp32.L(0.02);
        if (kbd.isDown(.Up)) {
            camera.position = camera.position.add(Vec4.init(Fp32.sin(camera.pitch), Fp32.sin(camera.yaw).mul(Fp32.L(-1)), Fp32.cos(camera.pitch).mul(Fp32.L(-1)), Fp32.L(0)).scale(speed));
        }
        if (kbd.isDown(.Left)) {
            camera.pitch = camera.pitch.sub(angular_speed);
        }
        if (kbd.isDown(.Down)) {
            camera.position = camera.position.sub(Vec4.init(Fp32.sin(camera.pitch), Fp32.sin(camera.yaw).mul(Fp32.L(-1)), Fp32.cos(camera.pitch).mul(Fp32.L(-1)), Fp32.L(0)).scale(speed));
        }
        if (kbd.isDown(.Right)) {
            camera.pitch = camera.pitch.add(angular_speed);
        }
        if (kbd.isDown(.Plus)) {
            camera.yaw = camera.yaw.add(angular_speed);
        }
        if (kbd.isDown(.Minus)) {
            camera.yaw = camera.yaw.sub(angular_speed);
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
        // eadk.display.waitForVblank();
    }
}

export fn main() void {
    eadk_main();
}

comptime {
    _ = @import("c.zig");
}
