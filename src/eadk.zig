const std = @import("std");

pub extern fn eadk_random() u32;
extern fn eadk_display_wait_for_vblank() void;

/// RGB565 color
pub const EadkColor = u16;
pub const EadkRect = extern struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

pub const EadkPoint = extern struct {
    x: u16,
    y: u16,
};

pub const SCREEN_WIDTH = 320;
pub const SCREEN_HEIGHT = 240;
pub const screen_rectangle = EadkRect {
    .x = 0, .y = 0,
    .width = SCREEN_WIDTH, .height = SCREEN_HEIGHT,
};

pub fn rgb(hex: u24) EadkColor {
    const red   = (hex >> 16) & 0xFF;
    const green = (hex >>  8) & 0xFF;
    const blue  = (hex      ) & 0xFF;

    return @intCast(u16,
        (red   >> 3) << 11 | // 5 bits of red
        (green >> 2) << 5  | // 6 bits of green
        (blue  >> 3));       // 5 bits of blue
}

pub fn init() void {
    // var _data_section_start_flash = @extern(*u32, .{ .name = "_data_section_start_flash" });
    // var _data_section_start_ram = @extern(*u32, .{ .name = "_data_section_start_ram" });
    // var _data_section_end_ram = @extern(*u32, .{ .name = "_data_section_end_ram" });

    // //var _bss_section_start_ram = @extern(u32, .{ .name = "_bss_section_start_ram" });
    // //var _bss_section_end_ram = @extern(u32, .{ .name = "_bss_section_end_ram" });

    // // Init data (initializing bss shouldn't be necessary?)
    // const data_size = _data_section_end_ram.* - _data_section_start_ram.*;
    // var i: usize = 0;
    // while (i < data_size) : (i += 1) {
    //     const ram_ptr = @intToPtr(*u8, _data_section_start_ram.* + i);
    //     const flash_ptr = @intToPtr(*u8, _data_section_start_flash.* + i);
    //     ram_ptr.* = flash_ptr.*;
    // }
}

extern fn eadk_display_pull_rect(rect: EadkRect, pixels: [*]const EadkColor) void;
extern fn eadk_display_push_rect(rect: EadkRect, pixels: [*]const EadkColor) void;
extern fn eadk_display_push_rect_uniform(rect: EadkRect, color: EadkColor) void;
extern fn eadk_display_draw_string(char: [*:0]const u8, point: EadkPoint, large_font: bool, text_color: EadkColor, background_color: EadkColor) void;
pub const display = struct {
    pub fn waitForVblank() void {
        eadk_display_wait_for_vblank();
    }

    pub fn fillImage(rect: EadkRect, pixels: [*]const EadkColor) void {
        std.debug.assert(pixels.len == rect.width * rect.height);
        eadk_display_push_rect(rect, pixels);
    }

    pub fn fillRectangle(rect: EadkRect, color: EadkColor) void {
        eadk_display_push_rect_uniform(rect, color);
    }

    pub fn setPixel(x: u16, y: u16, color: EadkColor) void {
        eadk_display_push_rect_uniform(EadkRect {
            .x = x, .y = y, .width = 1, .height = 1
        }, color);
    }

    pub fn drawLine(in_x1: u16, in_y1: u16, in_x2: u16, in_y2: u16, color: EadkColor) void {
        var x1 = in_x1;
        var x2 = in_x2;
        var y1 = in_y1;
        var y2 = in_y2;
        var steep = false;
        if (std.math.absInt(@intCast(i16, x1) - @intCast(i16, x2)) catch unreachable <
            std.math.absInt(@intCast(i16, y1) - @intCast(i16, y2)) catch unreachable) {
            // toujours plus horizontal que vertical (pente réduite)
            std.mem.swap(u16, &x1, &y1);
            std.mem.swap(u16, &x2, &y2);
            steep = true;
        }
        if (x1 > x2) { // toujours de gauche à droite
            std.mem.swap(u16, &x1, &x2);
            std.mem.swap(u16, &y1, &y2);
        }

        var x: u16 = x1;
        while (x <= x2) : (x += 1) {
            const t = @intToFloat(f32, x - x1) / @intToFloat(f32, x2 - x1);
            const y = @intCast(u16,
                @intCast(i16, y1) + @floatToInt(i16, (@intToFloat(f32, y2) - @intToFloat(f32, y1)) * t));
            if (steep) {
                setPixel(y, x, color);
            } else {
                setPixel(x, y, color);
            }
        }
    }

    fn clampX(coord: f32) u16 {
        return @floatToInt(u16, std.math.clamp(coord, 0, SCREEN_WIDTH));
    }

    fn clampY(coord: f32) u16 {
        return @floatToInt(u16, std.math.clamp(coord, 0, SCREEN_HEIGHT));
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, color: EadkColor) void {
        drawLine(clampX(x1), clampY(y1), clampX(x2), clampY(y2), color); // de 1 à 2
        drawLine(clampX(x2), clampY(y2), clampX(x3), clampY(y3), color); // de 2 à 3
        drawLine(clampX(x3), clampY(y3), clampX(x1), clampY(y1), color); // de 3 à 1
    }

    pub fn drawString(char: [*:0]const u8, point: EadkPoint, large_font: bool, text_color: EadkColor, background_color: EadkColor) void {
        eadk_display_draw_string(char, point, large_font, text_color, background_color);
    }
};

extern fn eadk_keyboard_scan() u64;
pub const keyboard = struct {
    pub const Key = enum(u8) {
        Left, Up, Down, Right, OK, Back, Home, OnOff = 8,
        Shift = 12, Alpha, XNT, Var, Toolbox, Backspace,
        Exp, Ln, Log, Imaginary, Comma, Power,
        Sine, Cosine, Tangent, Pi, Sqrt, Square,
        Seven, Eight, Nine, LeftParenthesis, RightParenthesis,
        Four = 35, Five, Six, Multiplication, Division,
        One = 42, Two, Three, Plus, Minus,
        Zero = 48, Dot, EE, Ans, Exe
    };

    pub const KeyboardState = struct {
        bitfield: u64,
        
        pub fn isDown(self: KeyboardState, key: Key) bool {
            const shift = @intCast(u6, @enumToInt(key));
            return (self.bitfield >> shift) & 1 == 1;
        }
    };

    pub fn scan() KeyboardState {
        return KeyboardState { .bitfield = eadk_keyboard_scan() };
    }
};
