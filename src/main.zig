const std = @import("std");

const fs = std.fs;
const io = std.io;
const mem = std.mem;
const posix = std.posix;
const stdout = io.getStdOut();

const File = std.fs.File;

pub const TermiosError = File.OpenError ||
                         posix.TermiosGetError ||
                         posix.UnexpectedError;

pub const Termios = struct {
    const Self = @This();

    tty: File,
    base_term: posix.termios,
    term: posix.termios,
    buff_out: @TypeOf(io.bufferedWriter(stdout.writer())),
    pub fn init() TermiosError!Termios {
        var tty = try fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        const base_term = try posix.tcgetattr(tty.handle);

        return .{
            .tty = tty,
            .base_term = base_term,
            .term = base_term,
            .buff_out = io.bufferedWriter(stdout.writer()),
        };
    }

    pub fn deinit(self: Self) posix.TermiosSetError!void {
        try posix.tcsetattr(self.tty.handle, .FLUSH, self.base_term);
        self.tty.close();
    }

};

};
pub fn main() !void {
    const termios = try Termios.init();
    std.debug.print("({}, {})\n", .{ termios.size.height, termios.size.width });
}
