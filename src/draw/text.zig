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

    pub fn drawInBox(self: *Text, bounding_box: *const Box) []const u8 {
        if (!self.box.overlapsBox(bounding_box)) {
            return &.{};
        }
        const start = @max(self.box.col, bounding_box.col);
        const end = @min(self.box.right(), bounding_box.right());
        return self.txt[start..end];
    }

    pub fn redraw(self: *Text) []const u8 {
        return self.txt;
    }

    pub fn redrawInBox(self: *Text, bounding_box: *const Box) []const u8 {
        return self.drawInBox(bounding_box);
    }

    pub fn drawable(self: *Text) DrawableBox {
        return DrawableBox.init(self, self.box);
    }
};
