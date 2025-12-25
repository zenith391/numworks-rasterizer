const std = @import("std");

const BmpError = error{ InvalidHeader, InvalidCompression, UnsupportedFormat };

pub const ImageFormat = enum { GRAY8, BGR24 };

pub const Image = struct { width: u32, height: u32, data: []const u8, format: ImageFormat };

pub fn comptimeRead(comptime fileBytes: []const u8) !Image {
    comptime {
        // var fbs = std.io.fixedBufferStream(fileBytes);
        // const reader = fbs.reader();
        // const seekable = fbs.seekableStream();

        var reader = std.Io.Reader.fixed(fileBytes);

        const signature = try reader.takeArray(2);
        if (!std.mem.eql(u8, signature, "BM")) {
            return BmpError.UnsupportedFormat;
        }

        const size = try reader.takeInt(u32, .little);
        _ = size;
        _ = reader.toss(4); // skip the reserved bytes
        const offset = try reader.takeInt(u32, .little);
        const dibSize = try reader.takeInt(u32, .little);

        if (dibSize == 40 or dibSize == 108) { // BITMAPV4HEADER
            const width: usize = @intCast(try reader.takeInt(i32, .little));
            const height: usize = @intCast(try reader.takeInt(i32, .little));
            const colorPlanes = try reader.takeInt(u16, .little);
            const bpp = try reader.takeInt(u16, .little);
            _ = colorPlanes;

            const compression = try reader.takeInt(u32, .little);
            const imageSize = try reader.takeInt(u32, .little);
            const horzRes = try reader.takeInt(i32, .little);
            const vertRes = try reader.takeInt(i32, .little);
            const colorsNum = try reader.takeInt(u32, .little);
            const importantColors = try reader.takeInt(u32, .little);
            _ = compression;
            _ = imageSize;
            _ = horzRes;
            _ = vertRes;
            _ = colorsNum;
            _ = importantColors;

            reader.toss(offset - reader.seek);
            const bytesPerPixel = @as(usize, @intCast(bpp / 8));

            var data: [width * height * bytesPerPixel]u8 = undefined;

            var i: usize = height - 1;
            var j: usize = 0;
            const bytesPerLine = width * bytesPerPixel;

            if (bytesPerPixel == 1) {
                const skipAhead: usize = @mod(width, 4);
                while (i >= 0) {
                    j = 0;
                    while (j < width) {
                        const pos = j + i * bytesPerLine;
                        data[pos] = try reader.readByte();
                        j += 1;
                    }
                    reader.toss(skipAhead);
                    if (i == 0) break;
                    i -= 1;
                }
                return Image{ .data = &data, .width = width, .height = height, .format = ImageFormat.GRAY8 };
            } else if (bytesPerPixel == 3) {
                const skipAhead: usize = @mod(width, 4);
                while (i >= 0) {
                    const pos = i * bytesPerLine;
                    _ = try reader.readSliceAll(data[pos..(pos + bytesPerLine)]);
                    reader.toss(skipAhead);
                    if (i == 0) break;
                    i -= 1;
                }
                return Image{ .data = &data, .width = width, .height = height, .format = ImageFormat.BGR24 };
            } else {
                return BmpError.UnsupportedFormat;
            }
        } else {
            return BmpError.InvalidHeader;
        }
    }
}
