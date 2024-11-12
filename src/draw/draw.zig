pub const DrawableBox = @import("drawable.zig").DrawableBox;
pub const Text = @import("text.zig").Text;

pub const Box = struct{
    row: usize,
    col: usize,
    height: usize,
    width: usize,

    pub inline fn bottom(self: *const Box) usize {
        return self.row + self.height;
    }

    pub inline fn overlapsBox(self: *const Box, other_box: *const Box) bool {
        return !(self.bottom() <= other_box.row or
                 other_box.bottom() <= self.row or
                 self.right() <= other_box.col or
                 other_box.right() <= self.col);
    }

    pub inline fn right(self: *const Box) usize {
        return self.col + self.width;
    }
};

// row, col
pub const BoxPoint = struct { usize, usize };

// row, col, height, width
pub const BoxQuad = struct { usize, usize, usize, usize };

// height, width
pub const BoxSize = struct { usize, usize };

pub const BoxTypeTag = enum {
    box,
    point,
    quad,
    size,
};

pub const BoxType = union(BoxTypeTag) {
    box: Box,
    point: BoxPoint,
    quad: BoxQuad,
    size: BoxSize,
};

pub inline fn boxed(box_type: BoxType) Box {
    return switch(box_type) {
        .box => box_type.box,
        .point => .{
            .row = box_type.point[0],
            .col = box_type.point[1],
            .height = 1,
            .width = 1,
        },
        .quad => .{
            .row = box_type.quad[0],
            .col = box_type.quad[1],
            .height = box_type.quad[2],
            .width = box_type.quad[3],
        },
        .size => .{
            .row = 0,
            .col = 0,
            .height = box_type.size[0],
            .width = box_type.size[1],
        },
    };
}
