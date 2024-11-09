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
    cooked: bool,
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
            .cooked = true,
            .buff_out = io.bufferedWriter(stdout.writer()),
        };
    }

    pub fn deinit(self: *Self) posix.TermiosSetError!void {
        errdefer self.tty.close();

        if (!self.cooked) {
            try self.cook();
        }

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

    pub fn cook(self: *Self) posix.TermiosSetError!void {
        try posix.tcsetattr(self.tty.handle, .FLUSH, self.base_term);
        self.cooked = true;
    }

    pub fn rawMode(self: *Self) *Self {
        return self
            .setIgnoreBreak(false)
            .setBreakToInterruptNotIgnored(false)
            .setParityErrorsAreMarked(false)
            .setInputStripping(false)
            .setNewLineToCarriageReturnOnInput(false)
            .setIgnoreCarriageReturn(false)
            .setCarriageReturnToNewLineOnInput(false)
            .setStartStopControlOnOutput(false)
            .setOutputProcessing(false)
            .setEchoInput(false)
            .setEchoNewLineInCanonicalMode(false)
            .setCanonicalMode(false)
            .setInterruptSignals(false)
            .setSpecialInputProcessingInCanonicalMode(false)
            .setParityDetection(false)
            .setCharacterSize(.CS8);
    }

    pub fn setBreakToInterruptNotIgnored(self: *Self, flag: bool) *Self {
        if (flag) {
            _ = self.setIgnoreBreak(false);
            self.term.iflag.BRKINT = true;
        } else {
            self.term.iflag.BRKINT = false;
        }
        return self;
    }

    pub fn setCanonicalMode(self: *Self, flag: bool) *Self {
        self.term.lflag.ICANON = flag;
        return self;
    }

    pub fn setCarriageReturnToNewLineOnInput(self: *Self, flag: bool) *Self {
        if (flag) {
            _ = self.setIgnoreCarriageReturn(false);
            self.term.iflag.ICRNL = true;
        } else {
            self.term.iflag.ICRNL = false;
        }
        return self;
    }

    pub fn setCharacterSize(self: *Self, csize: posix.CSIZE) *Self {
        self.term.cflag.CSIZE = csize;
        return self;
    }

    pub fn setEchoInput(self: *Self, flag: bool) *Self {
        self.term.lflag.ECHO = flag;
        return self;
    }

    pub fn setEchoNewLineInCanonicalMode(self: *Self, flag: bool) *Self {
        if (flag) {
            _ = self.setCanonicalMode(true);
            self.term.lflag.ECHONL = true;
        } else {
            self.term.lflag.ECHONL = false;
        }
        return self;
    }

    pub fn setInterruptSignals(self: *Self, flag: bool) *Self {
        self.term.lflag.ISIG = flag;
        return self;
    }

    pub fn setSpecialInputProcessingInCanonicalMode(self: *Self, flag: bool) *Self {
        if (flag) {
            _ = self.setCanonicalMode(true);
            self.term.lflag.IEXTEN = true;
        } else {
            self.term.lflag.IEXTEN = false;
        }
        return self;
    }

    pub fn setIgnoreBreak(self: *Self, flag: bool) *Self {
        self.term.iflag.IGNBRK = flag;
        return self;
    }

    pub fn setIgnoreCarriageReturn(self: *Self, flag: bool) *Self {
        self.term.iflag.IGNCR = flag;
        return self;
    }

    pub fn setIgnoreParityErrors(self: *Self, flag: bool) *Self {
        self.term.iflag.IGNPAR = flag;
        return self;
    }

    pub fn setIgnoreParityCheck(self: *Self, flag: bool) *Self {
        self.term.iflag.INPCK = flag;
        return self;
    }

    pub fn setInputStripping(self: *Self, flag: bool) *Self {
        self.term.iflag.ISTRIP = flag;
        return self;
    }

    pub fn setMinimumCharactersForNonCanonicalRead(self: *Self, min: u8) *Self {
        self.term.cc[@intFromEnum(posix.V.MIN)] = min;
        return self;
    }

    pub fn setNewLineToCarriageReturnOnInput(self: *Self, flag: bool) *Self {
        self.term.iflag.INLCR = flag;
        return self;
    }

    pub fn setOutputProcessing(self: *Self, flag: bool) *Self {
        self.term.oflag.OPOST = flag;
        return self;
    }

    pub fn setParityDetection(self: *Self, flag: bool) *Self {
        self.term.cflag.PARENB = flag;
        return self;
    }

    pub fn setParityErrorsAreMarked(self: *Self, flag: bool) *Self {
        if (flag) {
            _ = self
                .setIgnoreParityCheck(false)
                .setIgnoreParityErrors(false);
            self.term.iflag.PARMRK = true;
        } else {
            self.term.iflag.PARMRK = false;
        }
        return self;
    }

    pub fn setStartStopControlOnInput(self: *Self, flag: bool) *Self {
        self.term.iflag.IXOFF = flag;
        return self;
    }

    pub fn setStartStopControlOnOutput(self: *Self, flag: bool) *Self {
        self.term.iflag.IXON = flag;
        return self;
    }

    pub fn setTimeoutForNonCanonicalRead(self: *Self, time: u8) *Self {
        self.term.cc[@intFromEnum(posix.V.TIME)] = time;
        return self;
    }

    pub fn uncook(self: *Self) posix.TermiosSetError!void {
        try posix.tcsetattr(self.tty.handle, .FLUSH, self.term);
        self.cooked = false;
    }
};

pub const TermSize = struct {
    height: usize,
    width: usize,
};

pub fn main() !void {
    var termios = try Termios.init();
    defer termios.deinit() catch {};

    try termios
        .rawMode()
        .setMinimumCharactersForNonCanonicalRead(1)
        .setTimeoutForNonCanonicalRead(0)
        .uncook();
    std.debug.print("({}, {})\n", .{ termios.size.height, termios.size.width });
}
