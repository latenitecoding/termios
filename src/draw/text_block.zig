const Box = @import("box.zig").Box;
const BoxPoint = @import("box.zig").BoxPoint;
const DrawableBox = @import("drawable.zig").DrawableBox;
const Text = @import("text.zig").Text;

pub const TextBlock = struct {
    txt: []const u8,
    box: Box,

    pub fn init(box: Box, txt: []const u8) TextBlock {
        return .{
            .txt = txt,
            .box = box,
        };
    }

    pub fn draw(self: *TextBlock) []const u8 {
        return self.txt;
    }

    pub fn drawable(self: *TextBlock) DrawableBox {
        return DrawableBox.init(self, self.box);
    }

    pub fn drawInBox(self: *TextBlock, bounding_box: *const Box) []const u8 {
        if (!self.box.overlapsBox(bounding_box)) {
            return &.{};
        }
        const start = @max(self.box.col, bounding_box.col);
        const end = @min(self.box.right(), bounding_box.right());
        return self.txt[start..end];
    }

    pub fn iterator(self: *TextBlock) TextBlockIterator {
        return TextBlockIterator.init(self);
    }

    pub fn redraw(self: *TextBlock) []const u8 {
        return self.txt;
    }

    pub fn redrawInBox(self: *TextBlock, bounding_box: *const Box) []const u8 {
        return self.drawInBox(bounding_box);
    }
};

pub const TextBlockIterator = struct {
    text_block: *TextBlock,
    cursor: usize,

    pub fn init(text_block: *TextBlock) TextBlockIterator {
        return .{
            .text_block = text_block,
            .cursor = 0,
        };
    }

    pub fn next(self: *TextBlockIterator) ?Text {
        if (self.cursor >= self.text_block.txt.len) {
            return null;
        }

        const box_point = BoxPoint {
            self.cursor / self.text_block.box.width,
            self.text_block.col,
        };

        const end = @min(self.cursor + self.text_block.box.width, self.text_block.txt.len);
        const txt = self.text_block.txt[self.cursor..end];
        self.cursor = end;

        return Text.init(box_point, txt);
    }
};
