//! Zig port of Ken Perlin's Improved Noise - https://mrl.cs.nyu.edu/~perlin/noise/
//! This implementation uses fixed-point numbers
const std = @import("std");
const lib = @import("lib.zig");
const Fp32 = lib.Fp32;
const lerp = Fp32.lerp;

/// Performs perlin noise on given X, Y and Z coordinates.
/// Returns a value between -1 and 1.
pub fn p3d(in_x: Fp32, in_y: Fp32, in_z: Fp32) Fp32 {
    // find unit cube that contains point
    const X: u9 = @as(u8, @truncate(@as(u16, @bitCast(in_x.toInt()))));
    const Y = @as(u8, @truncate(@as(u16, @bitCast(in_y.toInt()))));
    const Z = @as(u8, @truncate(@as(u16, @bitCast(in_z.toInt()))));

    // find relative x,y,z of point in cube
    const x = in_x.sub(in_x.floor());
    const y = in_y.sub(in_y.floor());
    const z = in_z.sub(in_z.floor());

    // compute fade curves for each of x,y,z
    const u = fade(x);
    const v = fade(y);
    const w = fade(z);

    // hash coordinates of the 8 cube corners
    // zig note: cast to u9 so that the two u8 can be added together without overflow
    const A = @as(u9, p[X]) + Y;
    const AA = @as(u9, p[A]) + Z;
    const AB = @as(u9, p[A + 1]) + Z;
    const B = @as(u9, p[X + 1]) + Y;
    const BA = @as(u9, p[B]) + Z;
    const BB = @as(u9, p[B + 1]) + Z;

    // and add blended results from 8 corners of cube
    const value = lerp(
        lerp(
            lerp(
                grad(p[AA], x, y, z),
                grad(p[BA], x.sub(Fp32.L(1)), y, z),
                u,
            ),
            lerp(
                grad(p[AB], x, y.sub(Fp32.L(1)), z),
                grad(p[BB], x.sub(Fp32.L(1)), y.sub(Fp32.L(1)), z),
                u,
            ),
            v,
        ),
        lerp(
            lerp(
                grad(p[AA + 1], x, y, z.sub(Fp32.L(1))),
                grad(p[BA + 1], x.sub(Fp32.L(1)), y, z.sub(Fp32.L(1))),
                u,
            ),
            lerp(
                grad(p[AB + 1], x, y.sub(Fp32.L(1)), z.sub(Fp32.L(1))),
                grad(p[BB + 1], x.sub(Fp32.L(1)), y.sub(Fp32.L(1)), z.sub(Fp32.L(1))),
                u,
            ),
            v,
        ),
        w,
    );
    if (value.compare(Fp32.L(-1)) == .lt) return Fp32.L(-1);
    if (value.compare(Fp32.L(1)) == .gt) return Fp32.L(1);
    return value;
}

/// Performs multiple perlin noises (using octaves) on given X, Y and Z coordinates.
/// Returns a value between -1 and 1.
pub fn fbm(x: Fp32, y: Fp32, z: Fp32, comptime octaves: comptime_int) Fp32 {
    var value: Fp32 = Fp32.L(0);

    const G = 0.5;
    comptime var i: u32 = 0;
    inline while (i < octaves) : (i += 1) {
        const f = Fp32.L(std.math.pow(f32, 2.0, i));
        const a = Fp32.L(std.math.pow(f32, G, i + 1));
        value = value.add(a.mul(p3d(x.mul(f), y.mul(f), z.mul(f))));
    }

    return value;
}

pub fn noise(x: Fp32, y: Fp32, z: Fp32) Fp32 {
    const qX = fbm(x, y, z, 2).add(Fp32.L(1));
    const qY = fbm(x.add(Fp32.L(5.2)), y.add(Fp32.L(1.3)), z.add(Fp32.L(2.5)), 2).add(Fp32.L(1));
    const qZ = fbm(x.add(Fp32.L(1.1)), y.add(Fp32.L(5.5)), z.add(Fp32.L(3.2)), 2).add(Fp32.L(1));
    const c = Fp32.L(1.05);
    return fbm(x.add(c.mul(qX)), y.add(c.mul(qY)), z.add(c.mul(qZ)), 2);
}

fn fade(t: Fp32) Fp32 {
    // t * t * t * (t * (t * 6 - 15) + 10)
    return t.mul(t).mul(t).mul(t.mul(t.mul(Fp32.L(6).sub(Fp32.L(15)))).add(Fp32.L(10)));
}

fn grad(hash: u8, x: Fp32, y: Fp32, z: Fp32) Fp32 {
    // convert lo 4 bits of hash code into 12 gradient directions
    const h = @as(u4, @truncate(hash));
    const u = if (h < 8) x else y;
    const v = if (h < 4) y else if (h == 12 or h == 14) x else z;
    return if (h & 1 == 0) u else u.negate().add(if (h & 2 == 0) v else v.negate());
}

const permutation = [256]u8{ 151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180 };
var p = permutation ** 2;

pub fn setSeed(seed: u64) void {
    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        p[i] = random.int(u8);
        p[i + 256] = random.int(u8);
    }
}
