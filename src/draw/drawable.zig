const Box = @import("draw.zig").Box;

pub const DrawableBox = struct{
    ctx: *anyopaque,
    box: *Box,

    drawFn: *const fn (ctx: *anyopaque) []const u8,
    drawInBoxFn: *const fn (ctx: *anyopaque, bounding_box: *const Box) []const u8,
    redrawFn: *const fn (ctx: *anyopaque) []const u8,
    redrawInBoxFn: *const fn (ctx: *anyopaque, bounding_box: *const Box) []const u8,

    pub fn init(ctx: *anyopaque, box: *Box) DrawableBox {
        const T = @TypeOf(ctx);
        const ctx_info = @typeInfo(T);

        const generic = struct {
            pub fn draw(context: *anyopaque) []const u8 {
                const self: T = @ptrCast(@alignCast(context));
                return ctx_info.Pointer.child.draw(self);
            }

            pub fn drawInBox(context: *anyopaque, bounding_box: *const Box) []const u8 {
                const self: T = @ptrCast(@alignCast(context));
                return ctx_info.Pointer.child.drawInBox(self, bounding_box);
            }

            pub fn redraw(context: *anyopaque) []const u8 {
                const self: T = @ptrCast(@alignCast(context));
                return ctx_info.Pointer.child.redraw(self);
            }

            pub fn redrawInBox(context: *anyopaque, bounding_box: *const Box) []const u8 {
                const self: T = @ptrCast(@alignCast(context));
                return ctx_info.Pointer.child.redrawInBox(self, bounding_box);
            }
        };

        return .{
            .ctx = ctx,
            .box = box,
            .drawFn = generic.draw,
            .drawInBoxFn = generic.drawInBox,
            .redrawFn = generic.redraw,
            .redrawInBoxFn = generic.redrawInBox,
        };
    }

    pub fn draw(self: *DrawableBox) []const u8 {
        self.drawFn(self.ctx);
    }

    pub fn drawInBox(self: *DrawableBox, bounding_box: *const Box) []const u8 {
        return self.drawInBoxFn(self.ctx, bounding_box);
    }

    pub fn redraw(self: *DrawableBox) []const u8 {
        self.redrawFn(self.ctx);
    }

    pub fn redrawInBox(self: *DrawableBox, bounding_box: *const Box) []const u8 {
        return self.redrawInBoxFn(self.ctx, bounding_box);
    }
};
