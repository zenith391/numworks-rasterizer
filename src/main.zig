const std = @import("std");
const eadk = @import("eadk.zig");
const resources = @import("resources.zig");
const lib = @import("lib.zig");
const perlin = @import("perlin.zig");
const Fp32 = lib.Fp32;
const Vec2 = lib.Vec2;
const Vec4 = lib.Vec4;
const Mat4x4 = lib.Mat4x4;
const Triangle = lib.Triangle;
const Texture = lib.Texture;

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
    position: Vec4 = Vec4.L(2.5, 8, 2.5, 0),
    /// World-induced speed (does not account for manual movement)
    speed: Vec4 = Vec4.L(0, 0, 0, 0),
    pitch: Fp32 = Fp32.L(0),
    yaw: Fp32 = Fp32.L(0),
};

var state = GameState.MainMenu;
var fps: Fp32 = Fp32.L(40);
var camera: Camera = .{};

const model_vertices = [_]Vec4{
    // front face
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, 0.5, 1),
    Vec4.L(0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    // back face
    Vec4.L(-0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
    // left face
    Vec4.L(-0.5, -0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    // right face
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
    Vec4.L(0.5, 0.5, 0.5, 1),
    // top face
    Vec4.L(0.5, 0.5, 0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(-0.5, 0.5, 0.5, 1),
    Vec4.L(0.5, 0.5, -0.5, 1),
    Vec4.L(-0.5, 0.5, -0.5, 1),
    // bottom face
    Vec4.L(0.5, -0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    Vec4.L(-0.5, -0.5, -0.5, 1),
    Vec4.L(0.5, -0.5, 0.5, 1),
    Vec4.L(-0.5, -0.5, 0.5, 1),
};

const tex_coords = [_]Vec2{
    Vec2.L(1.0, 1.0),
    Vec2.L(1.0, 0.0),
    Vec2.L(0.0, 1.0),
    Vec2.L(0.0, 1.0),
    Vec2.L(1.0, 0.0),
    Vec2.L(0.0, 0.0),
};

const Facing = enum(u3) {
    south = 0,
    north = 1,
    west = 2,
    east = 3,
    top = 4,
    bottom = 5,

    pub fn getVertexOffset(self: Facing) usize {
        return 6 * @as(usize, @intFromEnum(self));
    }

    pub fn getDebugColor(self: Facing) eadk.EadkColor {
        return switch (self) {
            .top => eadk.rgb(0xFFFFFF),
            .bottom => eadk.rgb(0x888888),
            .north => eadk.rgb(0xFF0000),
            .south => eadk.rgb(0x880000),
            .west => eadk.rgb(0x00FF00),
            .east => eadk.rgb(0x008800),
        };
    }
};

fn drawPlane(PM: Mat4x4, x: Fp32, y: Fp32, z: Fp32, facing: Facing, texture: Texture) void {
    const offset = facing.getVertexOffset();
    const model_matrix =
        Mat4x4.translation(Vec4.init(x, y, z, Fp32.L(0)));
    const M = PM.mul(model_matrix);
    inline for (0..2) |i| {
        const a = M.project(model_vertices[i * 3 + 0 + offset]);
        const b = M.project(model_vertices[i * 3 + 1 + offset]);
        const c = M.project(model_vertices[i * 3 + 2 + offset]);
        const ta = tex_coords[(i * 3) + 0];
        const tb = tex_coords[(i * 3) + 1];
        const tc = tex_coords[(i * 3) + 2];
        const tri = (Triangle{
            .a = a,
            .b = b,
            .c = c,
            .ta = ta,
            .tb = tb,
            .tc = tc,
        }).projected();
        if (debug_mode) {
            tri.draw(facing.getDebugColor(), false, null);
        } else {
            tri.draw(0, true, texture);
        }
    }
}

const Block = enum(u8) {
    air,
    grass,
    dirt,
    wall,
    stone,
    sand,
    gravel,

    pub fn getTexture(self: Block, facing: Facing) Texture {
        return switch (self) {
            .air => undefined,
            .grass => switch (facing) {
                .top => resources.grass_top,
                .bottom => resources.dirt,
                else => resources.grass_side,
            },
            .dirt => resources.dirt,
            .wall => resources.wall_2,
            .stone => resources.stone,
            .sand => resources.sand,
            .gravel => resources.gravel,
        };
    }
};

const BlockFace = packed struct {
    block: Block,
    x: i8,
    y: i8,
    z: i8,
    facing: Facing,
};

pub const Chunk = struct {
    pub const CHUNK_SIZE = 16;
    pub const CHUNK_HEIGHT = 8;
    blocks: [CHUNK_SIZE][CHUNK_HEIGHT][CHUNK_SIZE]Block,
    ox: i8,
    oz: i8,

    pub fn init(ox: i8, oz: i8) Chunk {
        var blocks: [CHUNK_SIZE][CHUNK_HEIGHT][CHUNK_SIZE]Block = undefined;
        for (0..CHUNK_SIZE) |rx| {
            for (0..CHUNK_SIZE) |rz| {
                const x = @as(i16, ox) * CHUNK_SIZE + @as(i16, @intCast(rx));
                const z = @as(i16, oz) * CHUNK_SIZE + @as(i16, @intCast(rz));
                const noise_level = perlin.noise(
                    Fp32.fromInt(x).div(Fp32.L(64)).add(Fp32.L(5)),
                    Fp32.fromInt(z).div(Fp32.L(64)).add(Fp32.L(5)),
                    Fp32.L(5.5),
                );
                const level: usize = @intCast(noise_level.add(Fp32.L(1)).mul(Fp32.L(4)).toInt());
                for (0..CHUNK_HEIGHT) |y| {
                    if (y <= level) {
                        blocks[rx][y][rz] = .dirt;
                        if (y == level) blocks[rx][y][rz] = .grass;
                        if (y <= 1) blocks[rx][y][rz] = .stone;
                    } else {
                        blocks[rx][y][rz] = .air;
                    }
                }
            }
        }
        return Chunk{
            .blocks = blocks,
            .ox = ox,
            .oz = oz,
        };
    }
};

const World = struct {
    const MAX_FACES = 500; // this should be NUM_BLOCKS * 6 but that's too much space and far beyond what can be rendered
    const MAX_RENDERED_FACES = 128; // the render limit for faces
    const CHUNK_QUEUE_SIZE = 8;
    const BlockFaceArray = std.BoundedArray(BlockFace, MAX_FACES);

    faces: BlockFaceArray,
    /// Whether faces should be recomputed
    dirty: bool = true,
    chunks: [CHUNK_QUEUE_SIZE]Chunk,
    loaded_chunks: [CHUNK_QUEUE_SIZE]bool,
    // used for garbage collecting chunks from the queue
    used_chunks: [CHUNK_QUEUE_SIZE]bool,
    last_player_position: Vec4,

    pub fn init() World {
        return World{
            .chunks = undefined,
            .loaded_chunks = [1]bool{false} ** CHUNK_QUEUE_SIZE,
            .used_chunks = undefined,
            .faces = BlockFaceArray.init(0) catch unreachable,
            .last_player_position = Vec4.L(-100, -100, -100, -100),
        };
    }

    fn loadChunk(self: *World, ox: i8, oz: i8) *Chunk {
        const chunk = Chunk.init(ox, oz);
        var free_index: usize = 0;
        while (free_index < self.chunks.len) {
            if (self.loaded_chunks[free_index] == false) break;
            free_index += 1;
        }
        if (free_index == self.chunks.len) free_index = self.chunks.len - 1;
        self.chunks[free_index] = chunk;
        self.loaded_chunks[free_index] = true;
        self.used_chunks[free_index] = true;
        return &self.chunks[free_index];
    }

    pub fn getChunk(self: *World, ox: i8, oz: i8) ?*const Chunk {
        var i: usize = 0;
        while (i < self.chunks.len) : (i += 1) {
            if (self.loaded_chunks[i]) {
                const chunk = &self.chunks[i];
                if (chunk.ox == ox and chunk.oz == oz) {
                    self.used_chunks[i] = true;
                    return chunk;
                }
            }
        }
        return null;
    }

    pub fn getChunkOrLoad(self: *World, ox: i8, oz: i8) *const Chunk {
        if (self.getChunk(ox, oz)) |chunk| {
            return chunk;
        } else {
            return self.loadChunk(ox, oz);
        }
    }

    pub fn getBlock(self: *World, x: i16, y: i16, z: i16) Block {
        if (y < 0) return .grass;
        if (y >= Chunk.CHUNK_HEIGHT) return .air;
        const ox: i8 = @intCast(@divFloor(x, Chunk.CHUNK_SIZE));
        const oz: i8 = @intCast(@divFloor(z, Chunk.CHUNK_SIZE));
        const rx = @mod(x, Chunk.CHUNK_SIZE);
        const rz = @mod(z, Chunk.CHUNK_SIZE);
        const chunk = self.getChunkOrLoad(ox, oz);
        return chunk.blocks[@intCast(rx)][@intCast(y)][@intCast(rz)];
    }

    pub fn isFilled(self: *World, x: i16, y: i16, z: i16) bool {
        return self.getBlock(x, y, z) != .air;
    }

    pub fn hasNeighbour(self: *World, x: i16, y: i16, z: i16, facing: Facing) bool {
        return self.isFilled(
            x + @as(i16, switch (facing) {
                .west => -1,
                .east => 1,
                else => 0,
            }),
            y + @as(i16, switch (facing) {
                .top => 1,
                .bottom => -1,
                else => 0,
            }),
            z + @as(i16, switch (facing) {
                .north => -1,
                .south => 1,
                else => 0,
            }),
        );
    }

    pub fn addBlockFaces(self: *World, x: i16, y: i16, z: i16) void {
        const facings = std.meta.tags(Facing);
        for (facings) |facing| {
            if (!self.hasNeighbour(x, y, z, facing)) {
                self.faces.append(.{
                    .x = @intCast(x),
                    .y = @intCast(y),
                    .z = @intCast(z),
                    .facing = facing,
                    .block = self.getBlock(x, y, z),
                }) catch {};
            }
        }
    }

    pub fn computeRenderedFaces(self: *World) void {
        // Loops over nearest chunks
        const pos = camera.position;
        if (pos.x.toIntRound() == self.last_player_position.x.toInt() and pos.z.toIntRound() == self.last_player_position.z.toInt()) {
            return;
        } else {
            self.last_player_position = Vec4.init(pos.x.round(), Fp32.L(0), pos.z.round(), Fp32.L(0));
        }
        self.faces.clear();
        self.used_chunks = [1]bool{false} ** CHUNK_QUEUE_SIZE;
        const RANGE = 8;
        const maxx = pos.x.toIntRound() + RANGE;
        const minz = pos.z.toIntRound() - RANGE;
        const maxz = pos.z.toIntRound() + RANGE;
        var x: i16 = pos.x.toIntRound() - RANGE;
        while (x < maxx) : (x += 1) {
            var y: i16 = 0;
            while (y < Chunk.CHUNK_HEIGHT) : (y += 1) {
                var z: i16 = minz;
                while (z < maxz) : (z += 1) {
                    if (self.isFilled(@intCast(x), @intCast(y), @intCast(z))) {
                        self.addBlockFaces(@intCast(x), @intCast(y), @intCast(z));
                    }
                }
            }
        }
        self.sortFaces();
        // unload unused chunks
        self.loaded_chunks = self.used_chunks;
    }

    pub fn sortFaces(self: *World) void {
        std.mem.sortUnstable(BlockFace, self.faces.slice(), {}, struct {
            fn lessThan(_: void, lhs: BlockFace, rhs: BlockFace) bool {
                const vec1 = Vec4.init(
                    Fp32.fromInt(lhs.x),
                    Fp32.fromInt(lhs.y),
                    Fp32.fromInt(lhs.z),
                    Fp32.L(0),
                );
                const vec2 = Vec4.init(
                    Fp32.fromInt(rhs.x),
                    Fp32.fromInt(rhs.y),
                    Fp32.fromInt(rhs.z),
                    Fp32.L(0),
                );
                return vec1.sub(camera.position).lengthSquared().compare(vec2.sub(camera.position).lengthSquared()) == .gt;
            }
        }.lessThan);
    }

    pub fn renderFaces(self: World, PM: Mat4x4) void {
        const len = @min(self.faces.len, MAX_RENDERED_FACES);
        for (self.faces.len - len..self.faces.len) |i| {
            const face = self.faces.buffer[i];
            const xf = Fp32.fromInt(face.x);
            const yf = Fp32.fromInt(face.y);
            const zf = Fp32.fromInt(face.z);
            drawPlane(
                PM,
                xf,
                yf,
                zf,
                face.facing,
                face.block.getTexture(face.facing),
            );
        }
    }

    pub fn render(self: World, PM: Mat4x4) void {
        self.renderFaces(PM);
    }

    pub fn update(self: *World, dt: Fp32) void {
        // add gravity acceleration
        camera.speed = camera.speed.add(Vec4.L(0, -10, 0, 0).scale(dt));
        // TODO: horizontal collision detection
        const pos = camera.position;
        var new_pos = camera.position.add(camera.speed.scale(dt));
        if (self.isFilled(pos.x.toIntRound(), new_pos.y.toInt() -| 2, pos.z.toIntRound()) and camera.speed.y.compare(Fp32.L(0)) == .lt) {
            // vertical collision
            camera.speed.y = Fp32.L(0);
            new_pos.y = new_pos.y.round();
        }
        camera.position = new_pos;

        if (self.dirty) {
            self.computeRenderedFaces();
            self.dirty = false;
        }
    }
};

var world = World.init();
var debug_mode = false;

fn draw() void {
    if (state == .Playing) {
        const view_matrix = Mat4x4.identity()
            .mul(Mat4x4.rotation(camera.yaw, Vec4.L(-1, 0, 0, 0)))
            .mul(Mat4x4.rotation(camera.pitch, Vec4.L(0, 1, 0, 0)))
            .mul(Mat4x4.translation(camera.position.scale(Fp32.L(-1))));
        const perspective_matrix = Mat4x4.perspective(std.math.degreesToRadians(70.0), 320.0 / 240.0, 0.1, 5);
        // premultiplied matrix
        const PM = perspective_matrix.mul(view_matrix);

        world.render(PM);
        // {
        //     var buf: [100]u8 = undefined;
        //     const pos = camera.position;
        //     const slice = std.fmt.bufPrintZ(&buf, "camera: {d:.1}, {d:.1}, {d:.1}, {d:.1}", .{ pos.x.toFloat(), pos.y.toFloat(), pos.z.toFloat(), pos.w.toFloat() }) catch unreachable;
        //     eadk.display.drawString(slice, .{ .x = 0, .y = 30 }, false, eadk.rgb(0xFFFFFF), 0);
        // }
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

        const dt = Fp32.L(1).div(fps);
        const speed = Fp32.L(3).mul(dt);
        const angular_speed = Fp32.L(1).mul(dt);
        var moved = false;
        if (kbd.isDown(.Up)) {
            camera.position = camera.position.add(Vec4.init(Fp32.sin(camera.pitch), Fp32.L(0), Fp32.cos(camera.pitch).mul(Fp32.L(-1)), Fp32.L(0)).scale(speed));
            moved = true;
        }
        if (kbd.isDown(.Left)) {
            camera.pitch = camera.pitch.sub(angular_speed);
        }
        if (kbd.isDown(.Down)) {
            camera.position = camera.position.sub(Vec4.init(Fp32.sin(camera.pitch), Fp32.L(0), Fp32.cos(camera.pitch).mul(Fp32.L(-1)), Fp32.L(0)).scale(speed));
            moved = true;
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
        if (kbd.isDown(.Zero)) {
            debug_mode = true;
        } else if (kbd.isDown(.One)) {
            debug_mode = false;
        }
        if (kbd.isDown(.Exe)) {
            if (camera.speed.y.compare(Fp32.L(0)) == .eq) {
                camera.speed.y = Fp32.L(5);
            }
        }
        if (moved) {
            world.dirty = true;
        }
        world.update(dt);

        const end = eadk.eadk_timing_millis();
        const frame_fps = Fp32.L(1.0).div(Fp32.fromInt(@intCast(end - start)).div(Fp32.L(1000)));
        fps = fps.mul(Fp32.L(0.9)).add(frame_fps.mul(Fp32.L(0.1))); // faire interpolation linéaire vers la valeur fps
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
        if (fps.compare(Fp32.L(40)) == .gt) eadk.display.waitForVblank();
        // eadk.display.waitForVblank();
    }
}

export fn main() void {
    eadk_main();
}

comptime {
    _ = @import("c.zig");
}
