const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const stdin = std.io.getStdIn().reader();

const WcConfig = struct {
    chars: bool = true,
    bytes: bool = true,
    lines: bool = true,
    words: bool = true,
};

const WcResult = struct {
    charsNum: ?usize = null,
    bytesNum: ?usize = null,
    linesNum: ?usize = null,
    wordsNum: ?usize = null,
};

const usage =
    \\usage: zwc [-clmw] [file ...]
    \\
;
// ref to https://en.wikipedia.org/wiki/Whitespace_character
fn iswhitespace(codepoint: u21) bool {
    switch (codepoint) {
        ' ',
        '\t',
        0,
        10,
        11,
        12,
        13,
        0x0085,
        0x2000,
        0x2001,
        0x2002,
        0x2003,
        0x2004,
        0x2005,
        0x2006,
        0x2008,
        0x2009,
        0x200a,
        0x2028,
        0x2029,
        0x205f,
        0x3000,
        => return true,
        else => return false,
    }
}

const assert = std.debug.assert;

test "iswhitespace function tests" {
    // Test cases for whitespace characters
    assert(iswhitespace(' ') == true);
    assert(iswhitespace('\t') == true);
    assert(iswhitespace('\n') == true);
    assert(iswhitespace('\r') == true);
    assert(iswhitespace(0x0085) == true);
    assert(iswhitespace(0x2000) == true);
    assert(iswhitespace(0x2001) == true);
    assert(iswhitespace(0x2002) == true);
    assert(iswhitespace(0x2003) == true);
    assert(iswhitespace(0x2004) == true);
    assert(iswhitespace(0x2005) == true);
    assert(iswhitespace(0x2006) == true);
    assert(iswhitespace(0x2008) == true);
    assert(iswhitespace(0x2009) == true);
    assert(iswhitespace(0x200a) == true);
    assert(iswhitespace(0x2028) == true);
    assert(iswhitespace(0x2029) == true);
    assert(iswhitespace(0x205f) == true);
    assert(iswhitespace(0x3000) == true);
    assert(iswhitespace('A') == false);
    assert(iswhitespace('a') == false);
    assert(iswhitespace('0') == false);
    assert(iswhitespace('9') == false);
    assert(iswhitespace('!') == false);
    assert(iswhitespace('@') == false);
    assert(iswhitespace('#') == false);
    assert(iswhitespace('$') == false);
    assert(iswhitespace('%') == false);

    std.debug.print("All iswhitespace tests passed.\n", .{});
}

const Utf8ChunkedIterator = struct {
    chunk: []const u8,
    i: usize = 0,
    brokenCodepointBuffer: [4]u8 = [_]u8{ 0, 0, 0, 0 },
    brokenCodepointSlice: ?[]u8 = null,
    mendingBuffer: [4]u8 = [_]u8{ 0, 0, 0, 0 },

    const Self = @This();

    pub fn init(chunk: []const u8) Utf8ChunkedIterator {
        return .{
            .chunk = chunk,
            .i = 0,
        };
    }

    pub fn setChunk(self: *Self, chunk: []const u8) void {
        if (self.i < self.chunk.len) unreachable;

        self.chunk = chunk;
        self.i = 0;
    }

    pub fn nextCodepointSlice(self: *Self) ?[]const u8 {
        if (self.brokenCodepointSlice) |slice| {
            std.debug.assert(self.i == 0);

            if (self.i >= self.chunk.len) return null;

            const codePointLen = std.unicode.utf8ByteSequenceLength(slice[0]) catch unreachable;

            var i: usize = 0;
            while (i < slice.len) {
                const sourceIdx = if (i < slice.len) i else i - slice.len;
                self.mendingBuffer[i] = if (i < slice.len) slice[sourceIdx] else self.chunk[sourceIdx];
                i += 1;
            }

            self.i += codePointLen - slice.len;
            self.brokenCodepointSlice = null;

            return self.mendingBuffer[0..codePointLen];
        }

        if (self.i >= self.chunk.len) {
            return null;
        }

        const codePointLen = std.unicode.utf8ByteSequenceLength(self.chunk[self.i]) catch unreachable;
        const codePointOverflow: bool = (self.i + codePointLen - 1) >= self.chunk.len;

        if (codePointOverflow) {
            var idx: usize = 0;
            while (idx < self.chunk.len - self.i) {
                self.brokenCodepointBuffer[idx] = self.chunk[self.i + idx];
                idx += 1;
            }
            self.brokenCodepointSlice = self.brokenCodepointBuffer[0..idx];
            self.i = self.chunk.len;
            return null;
        }

        self.i += codePointLen;
        return self.chunk[self.i - codePointLen .. self.i];
    }

    pub fn nextCodepoint(self: *Self) ?u21 {
        if (self.nextCodepointSlice()) |slice| {
            const codePoint = std.unicode.utf8Decode(slice) catch unreachable;
            return codePoint;
        }

        return null;
    }
};

fn wcFile(comptime buf_size: comptime_int, filename: []const u8, config: WcConfig) !WcResult {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    return wcFileHandle(buf_size, file.handle, config);
}

fn wcFileHandle(comptime buf_size: comptime_int, fileHandle: std.fs.File.Handle, config: WcConfig) !WcResult {
    var buf: [buf_size]u8 = undefined;

    if (config.bytes and !config.words and !config.lines and !config.chars) {
        var bytes: usize = 0;
        while (true) {
            const bytes_read = try std.posix.read(fileHandle, &buf);
            if (bytes_read == 0) break;
            bytes += bytes_read;
        }

        return .{ .bytesNum = bytes };
    }

    var bytesNum: usize = 0;
    var charsNum: usize = 0;
    var linesNum: usize = 0;
    var wordsNum: usize = 0;

    // false: indicates the current character being processed does not belong to a word, possibly whitespace, punctuation, or other non-word characters.
    // true represents being inside a word. indicates that the current char being processed is part of a word.
    var isInsideWordFlag: bool = false;

    var it = Utf8ChunkedIterator.init(&[_]u8{});

    while (true) {
        const bytes_read = try std.posix.read(fileHandle, &buf);
        if (bytes_read == 0) break;

        bytesNum += bytes_read;

        it.setChunk(buf[0..bytes_read]);

        while (it.nextCodepoint()) |c| {
            charsNum += 1;
            switch (isInsideWordFlag) {
                false => {
                    if (c == '\n') {
                        linesNum += 1;
                    } else if (!iswhitespace(c)) {
                        isInsideWordFlag = true;
                    }
                },
                true => {
                    if (iswhitespace(c)) {
                        if (c == '\n') {
                            linesNum += 1;
                        }
                        wordsNum += 1;
                        isInsideWordFlag = false;
                    }
                },
            }
        }
    }

    return .{
        .charsNum = if (config.chars) charsNum else null,
        .bytesNum = if (config.bytes) bytesNum else null,
        .linesNum = if (config.lines) linesNum else null,
        .wordsNum = if (config.words) wordsNum else null,
    };
}

fn printResult(result: WcResult, filename: ?[]const u8) !void {
    if (result.linesNum) |linesNum| {
        try stdout.print(" {:>7}", .{linesNum});
    }

    if (result.wordsNum) |wordsNum| {
        try stdout.print(" {:>7}", .{wordsNum});
    }

    if (result.bytesNum) |bytesNum| {
        try stdout.print(" {:>7}", .{bytesNum});
    }

    if (result.charsNum) |charsNum| {
        try stdout.print(" {:>7}", .{charsNum});
    }

    if (filename) |_filename| {
        try stdout.print(" {s}\n", .{_filename});
    } else {
        try stdout.writeByte('\n');
    }
}

pub fn main() !void {
    var arena_instance = ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();

    const arena = arena_instance.allocator();

    const args = try std.process.argsAlloc(arena);

    var config = WcConfig{};

    var filenames = try arena.alloc([:0]u8, args.len - 1);
    var num_files: usize = 0;

    var byteFlag: bool = false;
    var lineFlag: bool = false;
    var charFlag: bool = false;
    var wordFlag: bool = false;

    var cursor: usize = 1;
    while (cursor < args.len) {
        var arg = args[cursor];
        cursor += 1;

        if (arg.len == 0) {
            continue;
        }

        if (arg[0] == '-') {
            if (arg.len == 1) {
                try stdout.writeAll(usage);
                std.posix.exit(0);
            }

            for (arg[1..]) |ch| {
                switch (ch) {
                    'c' => {
                        byteFlag = true;
                    },
                    'l' => {
                        lineFlag = true;
                    },
                    'm' => {
                        charFlag = true;
                    },
                    'w' => {
                        wordFlag = true;
                    },
                    else => {
                        try stderr.print("zwc: illegal option -- {c}\n", .{ch});
                        try stdout.writeAll(usage);
                        std.posix.exit(1);
                    },
                }
            }
        } else {
            filenames[num_files] = arg;
            num_files += 1;
        }
    }

    if (!byteFlag and !lineFlag and !wordFlag and !charFlag) {
        byteFlag = true;
        lineFlag = true;
        wordFlag = true;
    }

    config.bytes = byteFlag and !charFlag;
    config.chars = charFlag;
    config.lines = lineFlag;
    config.words = wordFlag;

    var i: usize = 0;

    while (i < num_files) : (i += 1) {
        const result: ?WcResult = wcFile(4096, filenames[i], config) catch |err|
            blk: {
            switch (err) {
                std.fs.File.OpenError.FileNotFound => {
                    try stderr.print("zwc: {s}: open: no such file or directory\n", .{filenames[i]});
                },
                else => {},
            }

            break :blk null;
        };

        if (result) |_result| {
            try printResult(_result, filenames[i]);
        }
    }

    if (num_files == 0) {
        const result = try wcFileHandle(4096, std.io.getStdIn().handle, config);
        try printResult(result, null);
    }
}
