const Box = @import("draw.zig").Box;
const BoxPoint = @import("draw.zig").BoxPoint;
const DrawableBox = @import("draw.zig").DrawableBox;

pub const Text = struct {
    txt: []const u8,
    box: Box,

    pub fn init(vert: BoxPoint, txt: []const u8) Text {
        return .{
            .txt = txt,
            .box = .{
                .row = vert[0],
                .col = vert[1],
                .height = 1,
                .width = txt.len,
            },
        };
    }

    pub fn draw(self: *Text) []const u8 {
        return self.txt;
    }

    pub fn redraw(self: *Text) []const u8 {
        return self.txt;
    }

    pub fn drawable(self: *Text) DrawableBox {
        return DrawableBox.init(self, self.box);
    }
};
