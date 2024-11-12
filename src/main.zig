const std = @import("std");
const draw = @import("draw.zig");

const fs = std.fs;
const io = std.io;
const mem = std.mem;
const posix = std.posix;
const stdout = io.getStdOut();

const boxed = draw.boxed;
const Box = draw.Box;
const File = std.fs.File;
const Text = draw.Text;

pub const TermiosCursorError = error{ OutOfBounds } || posix.WriteError;

pub const TermiosReadError = File.OpenError ||
                         posix.TermiosGetError ||
                         posix.UnexpectedError;

pub const TermiosWriteError = posix.TermiosSetError || posix.WriteError;

pub var TERM: ?Termios = null;

pub fn getTerm() TermiosReadError!*Termios {
    return Termios.init();
}

pub const Termios = struct {
    const Self = @This();

    tty: File,
    base_term: posix.termios,
    term: posix.termios,
    size: TermSize,
    cooked: bool,
    buff_out: @TypeOf(io.bufferedWriter(stdout.writer())),
    use_alt_buff: bool,
    auto_flush: bool,

    pub fn withAutoFlush() TermiosReadError!*Termios {
        if (TERM == null) {
            _ = try Termios.init();
        }
        TERM.?.auto_flush = true;
        return &TERM.?;
    }

    pub fn init() TermiosReadError!*Termios {
        if (TERM != null) {
            return &TERM.?;
        }

        var tty = try fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        const base_term = try posix.tcgetattr(tty.handle);

        TERM = .{
            .tty = tty,
            .base_term = base_term,
            .term = base_term,
            .size = try Termios.getSize(tty),
            .cooked = true,
            .buff_out = io.bufferedWriter(stdout.writer()),
            .use_alt_buff = false,
            .auto_flush = false,
        };

        posix.sigaction(posix.SIG.WINCH, &posix.Sigaction{
            .handler = .{ .handler = Termios.handleSigWinch },
            .mask = posix.empty_sigset,
            .flags = 0,
        }, null);

        return &TERM.?;
    }

    pub fn deinit(self: *Self) TermiosWriteError!void {
        errdefer self.tty.close();
        try self.exitNonCanonicalTerm();
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

    fn handleSigWinch(_: c_int) callconv(.C) void {
        var term = getTerm() catch return;
        term.size = Termios.getSize(term.tty) catch term.size;
    }

    fn padLine(self: *Self, cols: usize) posix.WriteError!void {
        const width = self.size.width;
        if (cols >= width) {
            return;
        }
        try self.writeByteNTimes(' ', width - cols);
    }

    pub fn cook(self: *Self) posix.TermiosSetError!void {
        try posix.tcsetattr(self.tty.handle, .FLUSH, self.base_term);
        self.cooked = true;
    }

    pub fn disableAltBuffer(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[?1049l");
        self.use_alt_buff = false;
    }

    pub fn enableAltBuffer(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[?1049h");
        self.use_alt_buff = true;
    }

    pub fn enterAltBuffer(self: *Self, hide_cursor: bool) posix.WriteError!void {
        if (hide_cursor) {
            try self.hideCursor();
        }
        try self.saveCursorPosition();
        try self.saveScreen();
        try self.enableAltBuffer();
        if (!self.auto_flush) {
            try self.flush();
        }
    }

    pub fn enterNonCanonicalTerm(self: *Self) TermiosWriteError!void {
        try self
            .rawMode()
            .setMinCharsForNonCanonicalRead(1)
            .setTimeoutForNonCanonicalRead(0)
            .uncook();

        try self.enterAltBuffer(true);
    }

    pub fn exitAltBuffer(self: *Self) posix.WriteError!void {
        try self.disableAltBuffer();
        try self.restoreScreen();
        try self.restoreCursorPosition();
        try self.showCursor();
        if (!self.auto_flush) {
            try self.flush();
        }
    }

    pub fn exitNonCanonicalTerm(self: *Self) TermiosWriteError!void {
        if (!self.cooked) {
            try self.cook();
        }
        if (self.use_alt_buff) {
            try self.exitAltBuffer();
        }
    }

    pub fn flush(self: *Self) posix.WriteError!void {
        try self.buff_out.flush();
    }

    pub fn hideCursor(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[?25l");
    }

    pub fn moveCursorTo(self: *Self, row: usize, col: usize) TermiosCursorError!void {
        if (self.size.height < row or self.size.width < col) {
            return error.OutOfBounds;
        }
        try self.printCtrlSeq("\x1B[{};{}H", .{ row + 1, col + 1 });
    }

    pub fn print(self: *Self, comptime format: []const u8, args: anytype) posix.WriteError!void {
        if (format.len == 0) {
            return;
        }

        const prev_len = self.buff_out.end;
        try self.buff_out.writer().print(format, args);

        self.buff_out.end = @min(self.buff_out.end, prev_len + self.size.width);

        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn printAll(self: *Self, comptime format: []const u8, args: anytype) posix.WriteError!void {
        if (format.len == 0) {
            return;
        }

        try self.buff_out.writer().print(format, args);

        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn printAt(self: *Self, comptime format: []const u8, args: anytype,
                   row: usize, col: usize) TermiosCursorError!void {
        try self.moveCursorTo(row, col);

        if (format.len == 0) {
            return;
        }

        const prev_len = self.buff_out.end;
        try self.buff_out.writer().print(format, args);

        self.buff_out.end = @min(self.buff_out.end, prev_len + self.size.width - col);

        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn printCtrlSeq(self: *Self, comptime format: []const u8, args: anytype) posix.WriteError!void {
        if (format.len == 0) {
            return;
        }

        try self.buff_out.writer().print(format, args);

        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn println(self: *Self, comptime format: []const u8, args: anytype) TermiosCursorError!void {
        const prev_len = self.buff_out.end;
        try self.print(format, args);
        try self.padLine(self.buff_out.end - prev_len);
    }

    pub fn printlnAt(self: *Self, comptime format: []const u8, args: anytype, row: usize, col: usize) TermiosCursorError!void {
        const prev_len = self.buff_out.end;
        try self.printAt(format, args, row, col);
        try self.padLine(self.buff_out.end - prev_len + col);
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

    pub fn restoreScreen(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[?47l");
    }

    pub fn restoreCursorPosition(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[u");
    }

    pub fn saveCursorPosition(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[s");
    }

    pub fn saveScreen(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[?47h");
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

    pub fn setMinCharsForNonCanonicalRead(self: *Self, min: u8) *Self {
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

    pub fn showCursor(self: *Self) posix.WriteError!void {
        try self.writeCtrlSeq("\x1B[?25h");
    }

    pub fn uncook(self: *Self) posix.TermiosSetError!void {
        try posix.tcsetattr(self.tty.handle, .FLUSH, self.term);
        self.cooked = false;
    }

    pub fn write(self: *Self, txt: []const u8) posix.WriteError!void {
        if (txt.len == 0) {
            return;
        }

        try self.buff_out.writer().writeAll(txt[0..@min(txt.len, self.size.width)]);

        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn writeAll(self: *Self, txt: []const u8) posix.WriteError!void {
        if (txt.len == 0) {
            return;
        }

        try self.buff_out.writer().writeAll(txt);

        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn writeAt(self: *Self, txt: []const u8, row: usize, col: usize) TermiosCursorError!void {
        try self.moveCursorTo(row, col);
        try self.write(txt[0..@min(txt.len, self.size.width - col)]);
    }

    pub fn writeByteNTimes(self: *Self, byte: u8, n: usize) posix.WriteError!void {
        if (n > 0) {
            try self.buff_out.writer().writeByteNTimes(byte, @min(n, self.size.width));
        }
        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn writeCtrlSeq(self: *Self, ctrl_seq: []const u8) posix.WriteError!void {
        if (ctrl_seq.len == 0) {
            return;
        }

        try self.buff_out.writer().writeAll(ctrl_seq);

        if (self.auto_flush) {
            try self.flush();
        }
    }

    pub fn writeln(self: *Self, txt: []const u8) posix.WriteError!void {
        try self.write(txt);
        try self.padLine(txt.len);
    }

    pub fn writelnAt(self: *Self, txt: []const u8, row: usize, col: usize) TermiosCursorError!void {
        try self.writeAt(txt, row, col);
        try self.padLine(txt.len + col);
    }
};

pub const TermSize = struct {
    height: usize,
    width: usize,
};

pub fn main() !void {
    var termios = try getTerm();
    defer termios.deinit() catch {};

    const smoke = [2][9][]const u8 {
        [9][]const u8{
            "                                                                                           z ",
            "                                 (  ) (@@) ( )  (@)  ()    @@    O     @     O     @    zzz  ",
            "                            (@@@)                                                  zzzzzz    ",
            "                       (     )                        zzzzzzzzzzz  zzzzzzzzzzzzzzzzzzzz  zzz ",
            "                  (@@@)                               zzzzzzzzz  zzzzzzzzzzzzzzzzzzzz  zzzzz ",
            "             (     )                                  zzzzzzz  zzzzzzzzzzzzzzzzzzzz  zzzzzzz ",
            "          (@@@@)                                      zzzzz                zzzzzz      zzzzz ",
            "                                                      zzzzz              zzzzzz        zzzzz ",
            "        (   )                                         zzzzz            zzzzzz          zzzzz ",
        },
        [9][]const u8{
            "                                                                                           z ",
            "                                 (@@) (  ) (@)  ()  (@)    OO    @     O     @     O    zzz  ",
            "                            (   )                                                  zzzzzz    ",
            "                       (@@@@@)                        zzzzzzzzzzz  zzzzzzzzzzzzzzzzzzzz  zzz ",
            "                  (   )                               zzzzzzzzz  zzzzzzzzzzzzzzzzzzzz  zzzzz ",
            "             (@@@@@)                                  zzzzzzz  zzzzzzzzzzzzzzzzzzzz  zzzzzzz ",
            "          (    )                                      zzzzz                zzzzzz      zzzzz ",
            "                                                      zzzzz              zzzzzz        zzzzz ",
            "        (@@@)                                         zzzzz            zzzzzz          zzzzz ",
        }
    };
    var train = [_]Text{
        Text.init(.{ 19, 0 }, "      ====        ________                ___________ zzzzz          zzzzzz            zzzzz "),
        Text.init(.{ 20, 0 }, "  _D _|  |_______/        \\__I_I_____===__|_________| zzzzz        zzzzzz              zzzzz "),
        Text.init(.{ 21, 0 }, "   |(_)---  |   H\\________/ |   |        =|___ ___|   zzzzz      zzzzzz                zzzzz "),
        Text.init(.{ 22, 0 }, "   /     |  |   H  |  |     |   |         ||_| |_||   zzzzzzz  zzzzzzzzzzzzzzzzzzzz  zzzzzzz "),
        Text.init(.{ 23, 0 }, "  |      |  |   H  |__--------------------| [___] |   zzzzz  zzzzzzzzzzzzzzzzzzzz  zzzzzzzzz "),
        Text.init(.{ 24, 0 }, "  | ________|___H__/__|_____/[][]~\\_______|       |   zzz  zzzzzzzzzzzzzzzzzzzz  zzzzzzzzzzz "),
        Text.init(.{ 25, 0 }, "  |/ |   |-----------I_____I [][] []  D   |=======|__|___zzzzzz_____________________________|_"),
    };
    const wheels = [8][3][]const u8{
        [3][]const u8{
            "__/ =| o |=-~~\\   /~~\\  /~~\\  /~~\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=    ||    ||    ||    |_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      \\_O=====O=====O=====O/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        },
        [3][]const u8{
            "__/ =| o |=-~~\\   /~~\\  /~~\\  /~~\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=   O=====O=====O=====O|_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        },
        [3][]const u8{
            "__/ =| o |=-~~O=====O=====O=====O\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=    ||    ||    ||    |_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        },
        [3][]const u8{
            "__/ =| o |=-~O=====O=====O=====O~\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=    ||    ||    ||    |_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        },
        [3][]const u8{
            "__/ =| o |=-O=====O=====O=====O~~\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=    ||    ||    ||    |_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        },
        [3][]const u8{
            "__/ =| o |=-~~\\   /~~\\  /~~\\  /~~\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=O=====O=====O=====O   |_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        },
        [3][]const u8{
            "__/ =| o |=-~~\\   /~~\\  /~~\\  /~~\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=    ||    ||    ||    |_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      O=====O=====O=====O__/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        },
        [3][]const u8{
            "__/ =| o |=-~~\\   /~~\\  /~~\\  /~~\\ ____Y___________|__|_zzz__________________________________|_",
            " |/-=|___|=    ||    ||    ||    |_____/~\\___/        z|_D__D__D_|  |_D__D__D_|  |_D__D__D_|  ",
            "  \\_/      \\O=====O=====O=====O_/      \\_/              \\_/   \\_/    \\_/   \\_/    \\_/   \\_/   ",
        }
    };

    try termios.enterNonCanonicalTerm();

    const iters = termios.size.width + train[0].box.width + 8;

    for (1..iters) |i| {
        const width = termios.size.width;

        const smokeLines = smoke[@mod(i - 1, 12) / 6];

        for (0..smokeLines.len) |j| {
            const start = if (i > width) i - width else 0;
            if (start >= smokeLines[j].len) {
                try termios.writelnAt(" ", 10 + j, 0);
                continue;
            }
            const end = @min(i, smokeLines[j].len);

            try termios.writelnAt(smokeLines[j][start..end], 10 + j, width - @min(width, i));
            try termios.flush();
        }

        for (0..train.len) |j| {
            const bounding_box = Box{
                .row = 10 + smokeLines.len + j,
                .col = if (i > width) i - width else 0,
                .height = 1,
                .width = @min(i, train[j].box.width),
            };
            const col_loc = width - @min(width, i);

            try termios.writelnAt(train[j].drawInBox(&bounding_box), bounding_box.row, col_loc);
            try termios.flush();
        }
        
        const wheelLines = wheels[@mod(i - 1, wheels.len)];

        for (0..wheelLines.len) |j| {
            const start = if (i > width) i - width else 0;
            if (start >= wheelLines[j].len) {
                try termios.writelnAt(" ", 10 + smokeLines.len + train.len + j, 0);
                continue;
            }
            const end = @min(i, wheelLines[j].len);

            try termios.writelnAt(wheelLines[j][start..end], 10 + smokeLines.len + train.len + j, width - @min(width, i));
            try termios.flush();
        }

        std.time.sleep(40_000_000);
    }

    try termios.exitNonCanonicalTerm();

    std.debug.print("({}, {})\n", .{ termios.size.height, termios.size.width });
}
