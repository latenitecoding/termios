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
    size: TermSize,
    buff_out: @TypeOf(io.bufferedWriter(stdout.writer())),

    pub fn init() TermiosError!Termios {
        var tty = try fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        const base_term = try posix.tcgetattr(tty.handle);

        return .{
            .tty = tty,
            .base_term = base_term,
            .term = base_term,
            .size = try Termios.getSize(tty),
            .buff_out = io.bufferedWriter(stdout.writer()),
        };
    }

    pub fn deinit(self: Self) posix.TermiosSetError!void {
        try posix.tcsetattr(self.tty.handle, .FLUSH, self.base_term);
        self.tty.close();
    }

    fn getSize(tty: File) posix.UnexpectedError!TermSize {
        var win_size = mem.zeroes(posix.winsize);

        const err = posix.system.ioctl(tty.handle, posix.T.IOCGWINSZ, @intFromPtr(&win_size));
        if (posix.errno(err) != .SUCCESS) {
            return posix.unexpectedErrno(@enumFromInt(err));
        }

        return .{
            .height = win_size.row,
            .width = win_size.col,
        };
    }
};

pub const TermSize = struct {
    height: usize,
    width: usize,
};

pub fn main() !void {
    const termios = try Termios.init();
    std.debug.print("({}, {})\n", .{ termios.size.height, termios.size.width });
}
