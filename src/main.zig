const std = @import("std");
const win = std.os.windows;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();

    const sh = if (args.next()) |arg|
        std.mem.sliceTo(arg, 0)
    else
        // default shell
        try std.process.getEnvVarOwned(allocator, "COMSPEC");

    const sh_utf16_raw = try std.unicode.utf8ToUtf16LeAlloc(allocator, sh);
    defer allocator.free(sh_utf16_raw);

    const sh_utf16 = try allocator.allocSentinel(u16, sh_utf16_raw.len, 0);
    std.mem.copyForwards(u16, sh_utf16[0..sh_utf16_raw.len], sh_utf16_raw);

    var startupinfow: win.STARTUPINFOW = std.mem.zeroes(win.STARTUPINFOW);
    startupinfow.cb = @sizeOf(win.STARTUPINFOW);
    startupinfow.dwFlags = win.STARTF_USESTDHANDLES;
    startupinfow.hStdInput = try win.GetStdHandle(win.STD_INPUT_HANDLE);
    startupinfow.hStdOutput = try win.GetStdHandle(win.STD_OUTPUT_HANDLE);
    startupinfow.hStdError = try win.GetStdHandle(win.STD_ERROR_HANDLE);

    var process_info: win.PROCESS_INFORMATION = std.mem.zeroes(win.PROCESS_INFORMATION);

    try win.CreateProcessW(
        null,
        @constCast(sh_utf16.ptr),
        null,
        null,
        win.TRUE,
        .{},
        null,
        null,
        &startupinfow,
        &process_info,
    );

    try win.WaitForSingleObject(process_info.hProcess, win.INFINITE);

    win.CloseHandle(process_info.hProcess);
    win.CloseHandle(process_info.hThread);
}
