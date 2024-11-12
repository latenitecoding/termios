pub const Box = struct{
    row: usize,
    col: usize,
    height: usize,
    width: usize,
};

// row, col
pub const BoxPoint = struct { usize, usize };

// row, col, height, width
pub const BoxQuad = struct { usize, usize, usize, usize };

// height, width
pub const BoxSize = struct { usize, usize };
