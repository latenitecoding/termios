const Box = @import("draw.zig").Box;

pub const DrawableBox = struct{
    ctx: *anyopaque,
    box: *Box,

    drawFn: *const fn (ctx: *anyopaque) []const u8,
    redrawFn: *const fn(ctx: *anyopaque) []const u8,

    pub fn init(ctx: *anyopaque, box: *Box) DrawableBox {
        const T = @TypeOf(ctx);
        const ctx_info = @typeInfo(T);

        const generic = struct {
            pub fn draw(context: *anyopaque) []const u8 {
                const self: T = @ptrCast(@alignCast(context));
                return ctx_info.Pointer.child.draw(self);
            }

            pub fn redraw(context: *anyopaque) []const u8 {
                const self: T = @ptrCast(@alignCast(context));
                return ctx_info.Pointer.child.redraw(self);
            }
        };

        return .{
            .ctx = ctx,
            .box = box,
            .drawFn = generic.draw,
            .redrawFn = generic.redraw,
        };
    }

    pub fn draw(self: *DrawableBox) []const u8 {
        self.drawFn(self.ctx);
    }

    pub fn redraw(self: *DrawableBox) []const u8 {
        self.redrawFn(self.ctx);
    }
};
