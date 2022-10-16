const std = @import("std");
const eadk = @import("eadk.zig");
const za = @import("zalgebra");

pub const APP_NAME = "Raycaster 3D";

pub export const eadk_app_name: [APP_NAME.len:0]u8 linksection(".rodata.eadk_app_name") = APP_NAME.*;
pub export const eadk_api_level: u32 linksection(".rodata.eadk_api_level") = 0;

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;
const Mat4 = za.Mat4;

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    //var buf: [512]u8 = undefined;
    const str = @ptrCast([:0]const u8, msg);
    //_ = buf;

    var i: usize = 0;
    while (true) {
        eadk.display.drawString(str,
            .{ .x = 0, .y = 0 }, true, eadk.rgb(0), eadk.rgb(0xFFFFFF));
        eadk.display.waitForVblank();

        const kbd = eadk.keyboard.scan();
        if (kbd.isDown(.Backspace) or i > 100) {
            break;
        }
        i += 1;
    }

    @breakpoint();
    unreachable;
}

const Triangle = struct {
    v1: Vec4,
    v2: Vec4,
    v3: Vec4,
    // texture coordinates
    t1: Vec2,
    t2: Vec2,
    t3: Vec2,

    pub fn transform(self: Triangle, mat: Mat4) Triangle {
        return .{
            .v1 = mat.mulByVec4(self.v1),
            .v2 = mat.mulByVec4(self.v2),
            .v3 = mat.mulByVec4(self.v3),
            .t1 = self.t1,
            .t2 = self.t2,
            .t3 = self.t3,
        };
    }

    pub fn fromSlice(slice: []const f32) Triangle {
        std.debug.assert(slice.len == 3 * 5); // 5 floats per vertices, 3 vertices
        return Triangle {
            .v1 = Vec4.new(slice[0],  slice[1],  slice[2], 1),
            .v2 = Vec4.new(slice[5],  slice[6],  slice[7], 1),
            .v3 = Vec4.new(slice[10], slice[11], slice[12], 1),
            .t1 = Vec2.new(slice[3],  slice[4]),
            .t2 = Vec2.new(slice[8],  slice[9]),
            .t3 = Vec2.new(slice[13], slice[14]),
        };
    }
};

fn triangleList(array: anytype) [array.len/15]Triangle {
    var triangles: [array.len/15]Triangle = undefined;
    var i: usize = 0;
    while (i < array.len) : (i += 15) {
        triangles[i/15] = Triangle.fromSlice(array[i..i+15]);
    }
    return triangles;
}

const cube = [_]f32 {
    // position        texture coordinates
    -0.5, -0.5, -0.5,  0.0, 0.0,
     0.5, -0.5, -0.5,  1.0, 0.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
    -0.5,  0.5, -0.5,  0.0, 1.0,
    -0.5, -0.5, -0.5,  0.0, 0.0,

    -0.5, -0.5,  0.5,  0.0, 0.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
     0.5,  0.5,  0.5,  1.0, 1.0,
     0.5,  0.5,  0.5,  1.0, 1.0,
    -0.5,  0.5,  0.5,  0.0, 1.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,

    -0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5,  0.5, -0.5,  1.0, 1.0,
    -0.5, -0.5, -0.5,  0.0, 1.0,
    -0.5, -0.5, -0.5,  0.0, 1.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,
    -0.5,  0.5,  0.5,  1.0, 0.0,

     0.5,  0.5,  0.5,  1.0, 0.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5,  0.5,  0.0, 0.0,
     0.5,  0.5,  0.5,  1.0, 0.0,

    -0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5, -0.5,  1.0, 1.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,
    -0.5, -0.5, -0.5,  0.0, 1.0,

    -0.5,  0.5, -0.5,  0.0, 1.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5,  0.5,  0.5,  1.0, 0.0,
     0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5,  0.5,  0.5,  0.0, 0.0,
    -0.5,  0.5, -0.5,  0.0, 1.0
};
const cubeTriangles = triangleList(cube);

const perspective = Mat4.perspective(
    70.0,
    @as(f32, eadk.SCREEN_WIDTH) / @as(f32, eadk.SCREEN_HEIGHT),
    0.1,
    100,
);


fn drawTriangles(triangles: []const Triangle, viewMatrix: Mat4, modelMatrix: Mat4, color: eadk.EadkColor) void {
    for (triangles) |triangle| {
        // Project the triangle using the view matrix and the perspective matrix
        var proj_tri = triangle.transform(modelMatrix).transform(viewMatrix).transform(perspective);
        const width_f = @as(f32, eadk.SCREEN_WIDTH);
        const height_f = @as(f32, eadk.SCREEN_HEIGHT);

        // Divide each vector by its 'w' component to go to clip space
        if (proj_tri.v1.z() < 0 or proj_tri.v2.z() < 0 or proj_tri.v3.z() < 0) {
            continue;
        }
        proj_tri.v1 = proj_tri.v1.scale(1 / proj_tri.v1.w());
        proj_tri.v2 = proj_tri.v2.scale(1 / proj_tri.v2.w());
        proj_tri.v3 = proj_tri.v3.scale(1 / proj_tri.v3.w());

        // Finally, go from clip space to screen space
        const x1 = (proj_tri.v1.x() / 2 + 0.5) * width_f;
        const y1 = (1 - (proj_tri.v1.y() / 2 + 0.5)) * height_f;
        
        const x2 = (proj_tri.v2.x() / 2 + 0.5) * width_f;
        const y2 = (1 - (proj_tri.v2.y() / 2 + 0.5)) * height_f;

        const x3 = (proj_tri.v3.x() / 2 + 0.5) * width_f;
        const y3 = (1 - (proj_tri.v3.y() / 2 + 0.5)) * height_f;
        eadk.display.drawTriangle(
            x1, y1, x2, y2, x3, y3,
            color,
        );
    }
}

const Camera = struct {
    position: Vec3 = Vec3.new(0, 1, 0),
    pitch: f32 = 0.0,
    yaw: f32 = za.toRadians(@as(f32, -90.0)),

    pub fn input(self: *Camera) void {
        const forward = self.getForward().scale(0.1);
        const right = self.getForward().cross(Vec3.up()).norm().scale(0.1);

        const kbd = eadk.keyboard.scan();
        if (kbd.isDown(.Up)) {
            self.position = self.position.add(forward);
        }
        if (kbd.isDown(.Down)) {
            self.position = self.position.sub(forward);
        }
        if (kbd.isDown(.Left)) {
            self.position = self.position.sub(right);
        }
        if (kbd.isDown(.Right)) {
            self.position = self.position.add(right);
        }

        if (kbd.isDown(.Plus)) {
            self.position = self.position.add(Vec3.new(0, 0.1, 0));
        }
        if (kbd.isDown(.Minus)) {
            self.position = self.position.sub(Vec3.new(0, 0.1, 0));
        }
    }

    pub fn getForward(self: Camera) Vec3 {
        return Vec3.new(
            std.math.cos(self.yaw) * std.math.cos(self.pitch),
            std.math.sin(self.pitch),
            std.math.sin(self.yaw) * std.math.cos(self.pitch),
        );
    }

    pub fn getViewMatrix(self: Camera) Mat4 {
        const direction = self.getForward();
        return Mat4.lookAt(self.position, self.position.add(direction), Vec3.new(0, 1, 0));
    }
};
var camera = Camera {};

fn eadk_main() void {
    var prng = std.rand.DefaultPrng.init(eadk.eadk_random());
    const random = prng.random();
    _ = random;
    eadk.display.fillRectangle(eadk.screen_rectangle, eadk.rgb(0x000000));


    var t: u32 = 0;
    while (true) : (t +%= 1) {
        // effacer l'écran
        eadk.display.fillRectangle(eadk.screen_rectangle, eadk.rgb(0x000000));
        camera.input();
        const viewMatrix = camera.getViewMatrix();

        const triR = @intToFloat(f32, t % 360);
        const modelMatrix = Mat4.recompose(
            Vec3.new(0, 0, -3),
            Vec3.new(78, triR, 0),
            Vec3.new(1, 1, 1),
        );
        drawTriangles(&cubeTriangles, viewMatrix, modelMatrix, eadk.rgb(0xFFFFFF));

        var triZ: f32 = std.math.sin(@intToFloat(f32, t % 628) / 100) * 2 - 3;
        const modelMatrix2 = Mat4.recompose(
            Vec3.new(0, 0, triZ),
            Vec3.new(45, triR*2, 0),
            Vec3.new(1, 1, 1),
        );
        drawTriangles(&cubeTriangles, viewMatrix, modelMatrix2, eadk.rgb(0xFF0000));

        const kbd = eadk.keyboard.scan();
        eadk.display.waitForVblank();
        if (kbd.isDown(.Backspace)) {
            break;
        }
    }
}

export fn main() void {
    eadk.init();
    eadk_main();
}

export fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) void {
    std.mem.copy(u8, dest[0..n], src[0..n]);
}

export fn __aeabi_memcpy(dest: [*]u8, src: [*]const u8, n: usize) callconv(.AAPCS) void {
    std.mem.copy(u8, dest[0..n], src[0..n]);
}
export fn __aeabi_memcpy8(dest: [*]u8, src: [*]const u8, n: usize) callconv(.AAPCS) void {
    std.mem.copy(u8, dest[0..n], src[0..n]);
}

fn generateConstantTable(from: f32, to: f32, comptime precision: usize, func: fn(f32) f32) [precision]f32 {
    var table: [precision]f32 = undefined;
    @setEvalBranchQuota(precision * 10);

    var idx: usize = 0;
    var x: f32 = from;
    const increment = (to - from) / @intToFloat(f32, table.len);
    while (x < to) : (x += increment) {
        table[idx] = func(x);
        idx += 1;
    }

    return table;
}

const COS_PRECISION = 1000;
const cos_table = generateConstantTable(0, 2 * std.math.pi, COS_PRECISION, zigCos);
fn zigCos(x: f32) f32 {
    return std.math.cos(x);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a * (1 - t) + b * t;
}

export fn cosf(theta: f32) f32 {
    const x = @mod(theta, 2 * std.math.pi);
    const range = 2.0 * std.math.pi - 0.0;
    const idx = @floatToInt(usize, x / range * COS_PRECISION);
    if (idx != COS_PRECISION - 1) {
        const t = x / range * COS_PRECISION - @floor(x / range * COS_PRECISION);
        return lerp(cos_table[idx], cos_table[idx+1], t);
    }
    return cos_table[idx];
}

export fn sinf(theta: f32) f32 {
    return cosf(theta - std.math.pi / 2.0);
}

const tan_table = generateConstantTable(0, std.math.pi, COS_PRECISION, zigTan);
fn zigTan(x: f32) f32 {
    return std.math.tan(x);
}
export fn tanf(theta: f32) f32 {
    const x = @mod(theta, std.math.pi);
    const range = 1.0 * std.math.pi - 0.0;
    const idx = @floatToInt(usize, x / range * COS_PRECISION);
    if (idx != COS_PRECISION - 1) {
        const t = x / range * COS_PRECISION - @floor(x / range * COS_PRECISION);
        return lerp(tan_table[idx], tan_table[idx+1], t);
    }
    return tan_table[idx];
}

export fn fmodf(x: f32, y: f32) f32 {
    return x - @floor(x / y) * y;
}


// export fn memmove(dest: [*]u8, src: [*]const u8, n: usize) void {
//     _ = dest; _ = src; _ = n;
//     unreachable;
// }

// export fn memset(str: [*]u8, c: i8, n: usize) void {
//     std.mem.set(u8, dest[0..n], c);
//     unreachable;
// }
export fn __aeabi_memset4(str: [*]u8, c: u8, n: usize) callconv(.AAPCS) void {
    _ = str; _ = c; _ = n;
    //std.mem.set(u8, str[0..n], c);
}
