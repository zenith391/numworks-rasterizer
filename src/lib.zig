const std = @import("std");
const eadk = @import("eadk.zig");

// TODO: faire des benchmarks entre Fp32 et f32 (en s'assurant d'avoir bien mis le float-abi)

// TODO: faire un truc générique qui marche pour tout
/// Fixed-point number in 16.16 format
pub const Fp32 = struct {
    backing_int: i32,

    pub const pi = fromFloat(std.math.pi);
    pub const e = fromFloat(std.math.e);

    pub fn fromInt(int: i16) Fp32 {
        return .{ .backing_int = @as(i32, int) << 16 };
    }

    test fromInt {
        try std.testing.expectEqual(Fp32{ .backing_int = 0x10000 }, fromInt(1));
        try std.testing.expectEqual(Fp32{ .backing_int = 0x0 }, fromInt(0));
        try std.testing.expectEqual(Fp32{ .backing_int = 0xF0000 }, fromInt(15));
        try std.testing.expectEqual(Fp32{ .backing_int = @bitCast(@as(u32, 0xFFFF0000)) }, fromInt(-1));
    }

    pub fn fromFloat(float: f32) Fp32 {
        const modf = std.math.modf(float);
        const int: i16 = @intFromFloat(modf.ipart);
        const fractional_part: u16 = blk: {
            var fract: u16 = 0;
            var factor: f32 = 0.5;
            comptime var i = 0;
            var value = modf.fpart;
            inline while (i < 16) : (i += 1) {
                fract <<= 1;
                if (value >= factor) {
                    value -= factor;
                    fract |= 1;
                }
                factor /= 2;
            }
            break :blk fract;
        };
        return .{ .backing_int = (@as(i32, int) << 16) | @as(i32, fractional_part) };
    }

    pub inline fn L(comptime float: f32) Fp32 {
        return comptime fromFloat(float);
    }

    test fromFloat {
        try std.testing.expectEqual(Fp32{ .backing_int = 0x20000 }, fromFloat(2));
        try std.testing.expectEqual(Fp32{ .backing_int = 0x28000 }, fromFloat(2.5));
        try std.testing.expectEqual(Fp32{ .backing_int = 0x2C000 }, fromFloat(2.75));
        try std.testing.expectEqual(Fp32{ .backing_int = 0x100C000 }, fromFloat(256.75));
        try std.testing.expectEqual(fromInt(-1), fromFloat(-1));
        // TODO: test fromFloat(-1)
    }

    pub fn add(a: Fp32, b: Fp32) Fp32 {
        return .{ .backing_int = a.backing_int + b.backing_int };
    }

    test add {
        try std.testing.expectEqual(fromInt(-4), fromInt(-2).add(fromInt(-2)));
        try std.testing.expectEqual(fromInt(-6), fromInt(-2).add(fromInt(-4)));
    }

    pub fn sub(a: Fp32, b: Fp32) Fp32 {
        return .{ .backing_int = a.backing_int - b.backing_int };
    }

    test sub {
        try std.testing.expectEqual(fromInt(-1), fromInt(0).sub(fromInt(1)));
    }

    pub fn mul(a: Fp32, b: Fp32) Fp32 {
        const product = std.math.mulWide(i32, a.backing_int, b.backing_int);
        return .{ .backing_int = @intCast(product >> 16) };
    }

    test mul {
        try std.testing.expectEqual(fromInt(1), fromInt(1).mul(fromInt(1)));
        try std.testing.expectEqual(fromInt(1), fromInt(-1).mul(fromInt(-1)));
        try std.testing.expectEqual(fromInt(4), fromInt(2).mul(fromInt(2)));
        try std.testing.expectEqual(fromInt(-4), fromInt(-2).mul(fromInt(2)));
    }

    pub fn div(a: Fp32, b: Fp32) Fp32 {
        const wider: i64 = @as(i64, a.backing_int) << 16;
        const quotient = @divTrunc(wider, b.backing_int);
        return .{ .backing_int = @intCast(quotient) };
    }

    test div {
        try std.testing.expectEqual(fromInt(1), fromInt(-1).div(fromInt(-1)));
        try std.testing.expectEqual(fromInt(1), fromInt(1).div(fromInt(1)));
        try std.testing.expectEqual(fromInt(4), fromInt(16).div(fromInt(4)));
        try std.testing.expectEqual(fromFloat(0.25), fromInt(1).div(fromInt(4)));
    }

    pub fn toFloat(self: Fp32) f32 {
        if (self.backing_int < 0) {
            return -(Fp32{ .backing_int = -self.backing_int }).toFloat();
        }
        var backing_int: u32 = @bitCast(self.backing_int);
        var value: f32 = 0;
        for (0..32) |i| {
            const factor = std.math.exp2(@as(f32, @floatFromInt(15 - @as(i8, @intCast(i)))));
            if (backing_int & 0x80000000 != 0) {
                value += factor;
            }
            backing_int <<= 1;
        }
        return value;
    }

    test toFloat {
        try std.testing.expectEqual(@as(f32, 2.5), fromFloat(2.5).toFloat());
        try std.testing.expectEqual(@as(f32, 2.399994), fromFloat(2.4).toFloat());
        try std.testing.expectEqual(@as(f32, -1.0), fromInt(-1).toFloat());
    }

    /// Does the conversion by flooring instead of by rounding it.
    pub fn toInt(self: Fp32) i16 {
        return @intCast(self.backing_int >> 16);
    }

    // TODO: format function

    pub fn lerp(a: Fp32, b: Fp32, t: Fp32) Fp32 {
        // a * (1 - t) + b * t
        return a.mul(fromInt(1).sub(t)).add(b.mul(t));
    }

    // TODO: sin, cos et sqrt avec développement limité (et méthode de Newton pour sqrt)
    // ou alors utiliser des lookup tables pour sin et cos

    fn generateConstantTable(from: f32, to: f32, comptime precision: usize, func: *const fn (f32) Fp32) [precision]Fp32 {
        var table: [precision]f32 = undefined;
        @setEvalBranchQuota(precision * 10);

        var idx: usize = 0;
        var x: f32 = from;
        const increment = (to - from) / @as(f32, @floatFromInt(table.len));
        while (x < to) : (x += increment) {
            table[idx] = func(x);
            idx += 1;
        }

        return table;
    }

    const COS_PRECISION = 100;
    const cos_table = generateConstantTable(0, 2 * std.math.pi, COS_PRECISION, zigCos);
    fn zigCos(x: f32) Fp32 {
        return Fp32.fromFloat(std.math.cos(x));
    }

    fn cosf(theta: Fp32) Fp32 {
        _ = theta;
        return 0;
        // const x = @mod(theta, 2 * std.math.pi);
        // const range = 2.0 * std.math.pi - 0.0;
        // const idx = @as(usize, @intFromFloat(x / range * (COS_PRECISION - 1)));
        // if (idx != COS_PRECISION - 1) {
        //     const t = x / range * COS_PRECISION - @floor(x / range * COS_PRECISION);
        //     return lerp(cos_table[idx], cos_table[idx + 1], t);
        // }
        // return cos_table[idx];
    }

    fn sinf(theta: Fp32) Fp32 {
        const offset = fromFloat(-std.math.pi / 2.0);
        return cosf(theta.add(offset));
    }

    pub fn sqrt(self: Fp32) Fp32 {
        // TODO: use custom methods
        return fromFloat(@sqrt(self.toFloat()));
    }

    test sqrt {
        try std.testing.expectEqual(fromFloat(2), fromFloat(4).sqrt());

        // NOTE: this is maybe too strict of a requirement ?
        try std.testing.expectEqual(fromFloat(std.math.sqrt2), fromFloat(2).sqrt());
    }

    pub fn square(self: Fp32) Fp32 {
        return self.mul(self);
    }
};

pub const Vec4 = struct {
    x: Fp32,
    y: Fp32,
    z: Fp32,
    w: Fp32,

    pub fn init(x: Fp32, y: Fp32, z: Fp32, w: Fp32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub fn lengthSquared(self: Vec4) Fp32 {
        return self.x.square().add(self.y.square().add(self.z.square().add(self.w.square())));
    }

    pub fn length(self: Vec4) Fp32 {
        return self.lengthSquared().sqrt();
    }

    test length {
        try std.testing.expectEqual(
            Fp32.fromFloat(std.math.sqrt2),
            Vec4.init(Fp32.fromInt(0), Fp32.fromInt(1), Fp32.fromInt(1), Fp32.fromInt(0)).length(),
        );
    }
};

pub const Triangle = struct {
    a: Vec4,
    b: Vec4,
    c: Vec4,

    /// The triangle is assumed to be in display coordinates.
    pub fn drawWireframe(self: Triangle, color: eadk.EadkColor) void {
        eadk.display.drawTriangle(
            self.a.x.toInt(),
            self.a.y.toInt(),
            self.b.x.toInt(),
            self.b.y.toInt(),
            self.c.x.toInt(),
            self.c.y.toInt(),
            color,
        );
    }

    pub fn draw(self: Triangle, color: eadk.EadkColor) void {
        // TODO: rasterization algorithm
        _ = self;
        _ = color;
    }
};

test {
    _ = Fp32;
    _ = Vec4;
}
