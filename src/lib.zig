const std = @import("std");
const eadk = @import("eadk.zig");

// TODO: faire des benchmarks entre Fp32 et f32 (en s'assurant d'avoir bien mis le float-abi)
// The performance of fixed-point numbers is about 10 to 15 times better than that of floating
// point numbers.
//
// According to https://kristoffer-dyrkorn.github.io/triangle-rasterizer/7, for triangle
// rasterization, 4 bits is enough for the fractional part (especially considering that the goal is
// not pixel-perfect rendering, given the hardware constraints). Therefore, a 12.4 format would
// suffice (and would also have much faster multiplication). However this would not be enough
// precision or range for world space vectors and for matrix multiplications, so the conversion
// from 16.16 to 12.4 could be done only for rasterization, as a last step.

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
        if (float < 0) {
            return fromInt(0).sub(fromFloat(-float));
        }
        std.debug.assert(std.math.isFinite(float));
        std.debug.assert(float >= 0);
        std.debug.assert(float <= 0x8000 - (1.0 / 65536.0));
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
        @setEvalBranchQuota(100_000);
        return comptime fromFloat(float);
    }

    test fromFloat {
        try std.testing.expectEqual(Fp32{ .backing_int = 0x20000 }, fromFloat(2));
        try std.testing.expectEqual(Fp32{ .backing_int = 0x28000 }, fromFloat(2.5));
        try std.testing.expectEqual(Fp32{ .backing_int = 0x2C000 }, fromFloat(2.75));
        try std.testing.expectEqual(Fp32{ .backing_int = 0x100C000 }, fromFloat(256.75));
        try std.testing.expectEqual(fromInt(-1), fromFloat(-1));
        try std.testing.expect(fromFloat(-0.02).compare(fromInt(0)) == .lt);

        try std.testing.fuzz(testFloats, .{});
        // TODO: test fromFloat(-1)
    }

    fn testFloats(input: []const u8) !void {
        for (0..input.len / 4) |i| {
            const bytes = input[i * 4 .. i * 4 + 4];
            const float: f32 = @bitCast(bytes[0..4].*);
            // Test only if the float is in the bounds
            if (@abs(float) <= 0x8000 - (1.0 / 65536.0)) {
                const fp32 = Fp32.fromFloat(float);
                const result = fp32.toFloat();
                if (!std.math.approxEqAbs(f32, float, result, 1.0 / 65536.0)) {
                    return error.TestFailed;
                }
            }
        }
    }

    pub fn add(a: Fp32, b: Fp32) Fp32 {
        return .{ .backing_int = a.backing_int +% b.backing_int };
    }

    test add {
        try std.testing.expectEqual(fromInt(-4), fromInt(-2).add(fromInt(-2)));
        try std.testing.expectEqual(fromInt(-6), fromInt(-2).add(fromInt(-4)));
    }

    pub fn sub(a: Fp32, b: Fp32) Fp32 {
        return .{ .backing_int = a.backing_int -% b.backing_int };
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

    /// Floor the fixed point number (round the number to negative infinity)
    pub fn floor(self: Fp32) Fp32 {
        return .{ .backing_int = self.backing_int & @as(i32, @bitCast(@as(u32, 0xFFFF0000))) };
    }

    pub fn round(self: Fp32) Fp32 {
        return self.add(L(0.5)).floor();
    }

    test round {
        try std.testing.expectEqual(L(1.0), L(0.5).round());
        try std.testing.expectEqual(L(0.0), L(0.499).round());
        try std.testing.expectEqual(L(0.0), L(-0.499).round());
        try std.testing.expectEqual(L(0.0), L(-0.5).round());
    }

    /// Converts the fixed point number to an integer by flooring
    pub fn toInt(self: Fp32) i16 {
        return @intCast(self.backing_int >> 16);
    }

    /// Converts the fixed point number to an integer by rounding
    pub fn toIntRound(self: Fp32) i16 {
        return self.add(L(0.5)).toInt();
    }

    pub fn format(value: Fp32, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        const float = value.toFloat();
        try writer.print("{" ++ fmt ++ "}", .{float});
    }

    pub fn lerp(a: Fp32, b: Fp32, t: Fp32) Fp32 {
        std.debug.assert(t.compare(Fp32.L(0)) != .lt);
        std.debug.assert(t.compare(Fp32.L(1)) != .gt);
        // a * (1 - t) + b * t
        return a.mul(fromInt(1).sub(t)).add(b.mul(t));
    }

    pub fn mod(self: Fp32, divider: Fp32) Fp32 {
        return .{ .backing_int = @mod(self.backing_int, divider.backing_int) };
    }

    fn generateConstantTable(from: f32, to: f32, comptime precision: usize, func: *const fn (f32) Fp32) [precision]Fp32 {
        var table: [precision]Fp32 = undefined;
        @setEvalBranchQuota(precision * 100);

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

    pub fn cos(theta: Fp32) Fp32 {
        const range = L(2.0 * std.math.pi);
        const x = theta.mod(range);
        const idx = x.mul(L(@as(comptime_float, COS_PRECISION - 1) / (2.0 * std.math.pi)));
        const idx_int: usize = @intCast(idx.toInt());
        // Linear interpolation between the value and the following one
        const t = idx.sub(idx.floor()); // this gives the fractional part, supposing idx > 0
        const next_value = blk: {
            if (idx_int != COS_PRECISION - 1) break :blk idx_int + 1;
            break :blk 0;
        };
        return lerp(cos_table[idx_int], cos_table[next_value], t);
    }

    pub fn sin(theta: Fp32) Fp32 {
        return cos(theta.sub(L(std.math.pi / 2.0)));
    }

    // TODO: use Taylor series and Newton's method for computing an approximation of sqrt
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

    pub fn min(a: Fp32, b: Fp32) Fp32 {
        return .{ .backing_int = @min(a.backing_int, b.backing_int) };
    }

    pub fn min3(a: Fp32, b: Fp32, c: Fp32) Fp32 {
        return .{ .backing_int = @min(a.backing_int, b.backing_int, c.backing_int) };
    }

    test min3 {
        try std.testing.expectEqual(L(-5), min3(L(-5), L(0.2), L(1.5)));
    }

    pub fn max(a: Fp32, b: Fp32) Fp32 {
        return .{ .backing_int = @max(a.backing_int, b.backing_int) };
    }

    pub fn max3(a: Fp32, b: Fp32, c: Fp32) Fp32 {
        return .{ .backing_int = @max(a.backing_int, b.backing_int, c.backing_int) };
    }

    test max3 {
        try std.testing.expectEqual(L(1.5), max3(L(-5), L(0.2), L(1.5)));
    }

    pub fn compare(a: Fp32, b: Fp32) std.math.Order {
        if (a.backing_int < b.backing_int) {
            return .lt;
        } else if (a.backing_int > b.backing_int) {
            return .gt;
        } else {
            return .eq;
        }
    }

    test compare {
        try std.testing.expectEqual(std.math.Order.lt, L(1.5).compare(L(5)));
        try std.testing.expectEqual(std.math.Order.gt, L(5).compare(L(1.5)));
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

    pub inline fn L(comptime x: f32, comptime y: f32, comptime z: f32, comptime w: f32) Vec4 {
        return init(Fp32.L(x), Fp32.L(y), Fp32.L(z), Fp32.L(w));
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

    pub fn add(a: Vec4, b: Vec4) Vec4 {
        return .{
            .x = a.x.add(b.x),
            .y = a.y.add(b.y),
            .z = a.z.add(b.z),
            .w = a.w.add(b.w),
        };
    }

    test add {
        const vec = Vec4.L(1, 2, 0, 0).add(Vec4.L(-5, -3, -0.02, -1));
        try std.testing.expectEqual(Vec4.L(-4, -1, -0.02, -1), vec);
    }

    pub fn sub(a: Vec4, b: Vec4) Vec4 {
        return .{
            .x = a.x.sub(b.x),
            .y = a.y.sub(b.y),
            .z = a.z.sub(b.z),
            .w = a.w.sub(b.w),
        };
    }

    pub fn scale(self: Vec4, scalar: Fp32) Vec4 {
        return .{
            .x = self.x.mul(scalar),
            .y = self.y.mul(scalar),
            .z = self.z.mul(scalar),
            .w = self.w.mul(scalar),
        };
    }

    test scale {
        const vec = Vec4.L(1, 2, 3, 4.5).scale(Fp32.L(0.5));
        try std.testing.expectEqual(Vec4.L(0.5, 1, 1.5, 2.25), vec);
    }

    pub fn scaleDiv(self: Vec4, scalar: Fp32) Vec4 {
        return .{
            .x = self.x.div(scalar),
            .y = self.y.div(scalar),
            .z = self.z.div(scalar),
            .w = self.w.div(scalar),
        };
    }

    test scaleDiv {
        const vec = Vec4.L(1, 2, 3, 4.5).scaleDiv(Fp32.L(0.25));
        try std.testing.expectEqual(Vec4.L(4, 8, 12, 18), vec);
    }

    pub fn normalize(self: Vec4) Vec4 {
        const l = self.lengthSquared();
        if (l.compare(Fp32.L(1)) == .eq) return self; // avoid computations if possible
        return self.scaleDiv(l.sqrt());
    }

    pub fn round(self: Vec4) Vec4 {
        return .{
            .x = self.x.round(),
            .y = self.y.round(),
            .z = self.z.round(),
            .w = self.w.round(),
        };
    }
};

pub const Vec2 = struct {
    x: Fp32,
    y: Fp32,

    pub fn init(x: Fp32, y: Fp32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub inline fn L(comptime x: f32, comptime y: f32) Vec2 {
        return init(Fp32.L(x), Fp32.L(y));
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x.add(b.x), .y = a.y.add(b.y) };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x.sub(b.x), .y = a.y.sub(b.y) };
    }

    pub fn mul(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x.mul(b.x), .y = a.y.mul(b.y) };
    }

    pub fn scale(self: Vec2, scalar: Fp32) Vec2 {
        return .{ .x = self.x.mul(scalar), .y = self.y.mul(scalar) };
    }
};

/// Computes the "determinant" of the vectors AB and AC
/// This is used to find on which "side" point C is compared to the line (AB)
fn getDeterminant(a: Vec4, b: Vec4, c: Vec4) Fp32 {
    const ab = b.sub(a);
    const ac = c.sub(a);
    return ab.y.mul(ac.x).sub(ab.x.mul(ac.y));
}

test getDeterminant {
    const a = Vec4.L(0, 50, 0, 0);
    const b = Vec4.L(20, 20, 0, 0);
    const c = Vec4.L(10, 10, 0, 0);
    try std.testing.expect(getDeterminant(a, b, c).toFloat() > 0);
    try std.testing.expect(getDeterminant(b, c, a).toFloat() > 0);
}

pub const Texture = struct {
    width: u16,
    height: u16,
    colors: [*]const eadk.EadkColor,
};

/// Triangles are assumed to be in CCW (counter-clockwise) order
pub const Triangle = struct {
    a: Vec4,
    b: Vec4,
    c: Vec4,
    // Texture coordinates
    ta: Vec2,
    tb: Vec2,
    tc: Vec2,

    pub fn projected(self: Triangle) Triangle {
        // This divides the vectors by their w component, and then projects them from NDC
        // coordinates (from -1 to 1) to screen coordinates (from 0 to 320 and from 0 to 240)
        const L = Fp32.L;
        // const a2 = self.a;
        // const b2 = self.b;
        // const c2 = self.c;
        const a2 = self.a.scaleDiv(self.a.w);
        const b2 = self.b.scaleDiv(self.b.w);
        const c2 = self.c.scaleDiv(self.c.w);
        return .{
            .a = Vec4.init(
                a2.x.add(L(1)).mul(L(320 / 2)).floor(),
                a2.y.add(L(1)).mul(L(240 / 2)).floor(),
                a2.z,
                a2.w,
            ),
            .b = Vec4.init(
                b2.x.add(L(1)).mul(L(320 / 2)).floor(),
                b2.y.add(L(1)).mul(L(240 / 2)).floor(),
                b2.z,
                b2.w,
            ),
            .c = Vec4.init(
                c2.x.add(L(1)).mul(L(320 / 2)).floor(),
                c2.y.add(L(1)).mul(L(240 / 2)).floor(),
                c2.z,
                c2.w,
            ),
            .ta = self.ta,
            .tb = self.tb,
            .tc = self.tc,
        };
    }

    /// Assumes the triangle is projected
    pub fn drawWireframe(self: Triangle, color: eadk.EadkColor) void {
        eadk.display.drawTriangle(
            self.a.x.toFloat(),
            self.a.y.toFloat(),
            self.b.x.toFloat(),
            self.b.y.toFloat(),
            self.c.x.toFloat(),
            self.c.y.toFloat(),
            color,
        );
    }

    /// Assumes the triangle is projected
    pub fn draw(self: Triangle, color: eadk.EadkColor, comptime interpolate: bool, texture: ?Texture) void {
        // Compute the bounding box of the triangle
        const xmin = Fp32.max(Fp32.L(0), Fp32.min3(self.a.x, self.b.x, self.c.x));
        const xmax = Fp32.min(Fp32.L(eadk.SCREEN_WIDTH), Fp32.max3(self.a.x, self.b.x, self.c.x));
        const ymin = Fp32.max(Fp32.L(0), Fp32.min3(self.a.y, self.b.y, self.c.y));
        const ymax = Fp32.min(Fp32.L(eadk.SCREEN_HEIGHT), Fp32.max3(self.a.y, self.b.y, self.c.y));
        // TODO: clip the triangle to the framebuffer's bounds
        // TODO: utiliser du 24.8 pour le rendu graphique (car pour le déterminant, il y a des
        // multiplication de x par y, donc potentiellement, une multiplication de 320 par 240 donc
        // un overflow, et ça c'est en ayant A, B et C des points sur l'écran, en pratique ils
        // peuvent ne pas l'être)

        const zmin = Fp32.min3(self.a.z, self.b.z, self.c.z);
        if (zmin.compare(Fp32.L(1)) != .lt) return; // only draw triangle if it's in front
        if (zmin.compare(Fp32.L(0)) != .gt) return; // only draw triangle if it's in front

        const det = getDeterminant(self.a, self.b, self.c);
        if (det.compare(Fp32.L(0)) != .gt) return; // only draw the triangle if it's in CCW order

        // Compute the determinants for the top-left point of the triangle
        const tl = Vec4.init(xmin, ymin, Fp32.L(0), Fp32.L(0));
        const wtl0 = getDeterminant(self.a, self.b, tl);
        const wtl1 = getDeterminant(self.b, self.c, tl);
        const wtl2 = getDeterminant(self.c, self.a, tl);

        // Compute the difference in determinant, horizontally and vertical, between two neighbouring points
        const dwdx0 = self.a.y.sub(self.b.y);
        const dwdx1 = self.b.y.sub(self.c.y);
        const dwdx2 = self.c.y.sub(self.a.y);
        const dwdy0 = self.a.x.sub(self.b.x);
        const dwdy1 = self.b.x.sub(self.c.x);
        const dwdy2 = self.c.x.sub(self.a.x);

        const denom = getDeterminant(self.a, self.b, self.c);
        const dwdxa = dwdx1.div(denom);
        const dwdxb = dwdx2.div(denom);
        const dwdxc = dwdx0.div(denom);
        const dwdya = dwdy1.div(denom);
        const dwdyb = dwdy2.div(denom);
        const dwdyc = dwdy0.div(denom);

        var y = ymin;
        var wl0 = wtl0;
        var wl1 = wtl1;
        var wl2 = wtl2;

        // Starting weights for vertices
        var wla = wl1.div(denom);
        var wlb = wl2.div(denom);
        var wlc = wl0.div(denom);

        const tex_size = blk: {
            if (texture) |tex| {
                break :blk Vec2.init(Fp32.fromInt(@intCast(tex.width)), Fp32.fromInt(@intCast(tex.height)));
            } else {
                break :blk Vec2.L(0, 0);
            }
        };
        const dwdtexc = self.ta.scale(dwdxa).add(self.tb.scale(dwdxb)).add(self.tc.scale(dwdxc)).mul(tex_size);

        while (y.compare(ymax) == .lt) : (y = y.add(Fp32.L(1))) {
            var x = xmin;
            var w0 = wl0;
            var w1 = wl1;
            var w2 = wl2;
            var wa = wla;
            var wb = wlb;
            var wc = Fp32.L(1).sub(wa).sub(wb);
            var texc = self.ta.scale(wa).add(self.tb.scale(wb)).add(self.tc.scale(wc)).mul(tex_size);
            while (x.compare(xmax) == .lt) : (x = x.add(Fp32.L(1))) {
                // const p = Vec4.init(x, y, Fp32.L(0), Fp32.L(0));
                // const w0 = getDeterminant(self.a, self.b, p);
                // const w1 = getDeterminant(self.b, self.c, p);
                // const w2 = getDeterminant(self.c, self.a, p);
                const col = blk: {
                    if (interpolate) {
                        if (texture) |tex| {
                            const tx: u16 = @intCast(texc.x.toInt());
                            const ty: u16 = @intCast(texc.y.toInt());
                            break :blk tex.colors[ty * tex.width + tx];
                        } else {
                            break :blk eadk.rgb(@as(u16, @bitCast(Fp32.lerp(Fp32.L(0x80), Fp32.L(0xFF), wb).toInt())));
                        }
                    } else {
                        break :blk color;
                    }
                };
                if (w0.compare(Fp32.L(0)) != .lt and w1.compare(Fp32.L(0)) != .lt and w2.compare(Fp32.L(0)) != .lt) {
                    eadk.display.setPixel(@intCast(x.toInt()), @intCast(y.toInt()), col);
                }
                w0 = w0.sub(dwdx0);
                w1 = w1.sub(dwdx1);
                w2 = w2.sub(dwdx2);
                if (interpolate) {
                    wa = wa.sub(dwdxa);
                    wb = wb.sub(dwdxb);
                    wc = wc.sub(dwdxc);
                    texc = texc.sub(dwdtexc);
                }
                // TODO: clamp the weights to compensate for precision issues
            }
            wl0 = wl0.add(dwdy0);
            wl1 = wl1.add(dwdy1);
            wl2 = wl2.add(dwdy2);
            if (interpolate) {
                wla = wla.add(dwdya);
                wlb = wlb.add(dwdyb);
                wlc = wlc.add(dwdyc);
            }
        }
    }
};

/// Column-major matrices (as opposed to row-major matrices like OpenGL uses!)
pub const Mat4x4 = struct {
    /// [row][column]Fp32
    data: [4][4]Fp32,

    const L = Fp32.L;

    pub fn identity() Mat4x4 {
        return .{ .data = .{
            .{ L(1), L(0), L(0), L(0) },
            .{ L(0), L(1), L(0), L(0) },
            .{ L(0), L(0), L(1), L(0) },
            .{ L(0), L(0), L(0), L(1) },
        } };
    }

    /// fov is assumed to be in radians
    pub fn perspective(comptime fov: f32, comptime aspect_ratio: f32, comptime z_near: f32, comptime z_far: f32) Mat4x4 {
        std.debug.assert(z_near < z_far);
        const S = L(1 / @tan(fov / 2));
        return .{ .data = .{
            .{ S.div(L(aspect_ratio)), L(0), L(0), L(0) },
            .{ L(0), S, L(0), L(0) },
            .{ L(0), L(0), L((z_near + z_far) / (z_near - z_far)), L(2 * z_far * z_near / (z_near - z_far)) },
            .{ L(0), L(0), L(-1), L(0) },
        } };
    }

    pub fn translation(vector: Vec4) Mat4x4 {
        return .{ .data = .{
            .{ L(1), L(0), L(0), vector.x },
            .{ L(0), L(1), L(0), vector.y },
            .{ L(0), L(0), L(1), vector.z },
            .{ L(0), L(0), L(0), L(1) },
        } };
    }

    pub fn rotation(angle: Fp32, axis: Vec4) Mat4x4 {
        const norm = axis.normalize();
        const s = Fp32.sin(angle);
        const c = Fp32.cos(angle);
        const cv = Fp32.L(1).sub(c);
        const x = norm.x;
        const y = norm.y;
        const z = norm.z;
        return .{ .data = .{
            .{ x.mul(x.mul(cv)).add(c), y.mul(x.mul(cv)).sub(z.mul(s)), z.mul(x.mul(cv)).add(y.mul(s)), L(0) },
            .{ x.mul(y.mul(cv)).add(z.mul(s)), y.mul(y.mul(cv)).add(c), z.mul(y.mul(cv)).sub(x.mul(s)), L(0) },
            .{ x.mul(z.mul(cv)).sub(y.mul(s)), y.mul(z.mul(cv)).add(x.mul(s)), z.mul(z.mul(cv)).add(c), L(0) },
            .{ L(0), L(0), L(0), L(1) },
        } };
    }

    /// Project the given column vector
    pub fn project(self: Mat4x4, vector: Vec4) Vec4 {
        return Vec4.init(
            self.data[0][0].mul(vector.x).add(self.data[0][1].mul(vector.y)).add(self.data[0][2].mul(vector.z)).add(self.data[0][3].mul(vector.w)),
            self.data[1][0].mul(vector.x).add(self.data[1][1].mul(vector.y)).add(self.data[1][2].mul(vector.z)).add(self.data[1][3].mul(vector.w)),
            self.data[2][0].mul(vector.x).add(self.data[2][1].mul(vector.y)).add(self.data[2][2].mul(vector.z)).add(self.data[2][3].mul(vector.w)),
            self.data[3][0].mul(vector.x).add(self.data[3][1].mul(vector.y)).add(self.data[3][2].mul(vector.z)).add(self.data[3][3].mul(vector.w)),
        );
    }

    test project {
        const a = Vec4.L(1, 2, 3, 4);
        try std.testing.expectEqual(a, Mat4x4.identity().project(a));
    }

    pub fn mul(a: Mat4x4, b: Mat4x4) Mat4x4 {
        var data: [4][4]Fp32 = undefined;
        for (0..4) |row| {
            for (0..4) |column| {
                var sum: Fp32 = L(0);
                inline for (0..4) |i| {
                    sum = sum.add(a.data[row][i].mul(b.data[i][column]));
                }
                data[row][column] = sum;
            }
        }
        return .{ .data = data };
    }

    test mul {
        try std.testing.expectEqual(Mat4x4.identity(), Mat4x4.identity().mul(Mat4x4.identity()));
    }
};

test {
    std.testing.refAllDecls(@This());
}
