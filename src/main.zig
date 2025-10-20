const std = @import("std");
const win = std.os.windows;

const BUFSIZE = 4096;

var g_hChildStd_IN_Rd: win.HANDLE = undefined;
var g_hChildStd_IN_Wr: win.HANDLE = undefined;
var g_hChildStd_OUT_Rd: win.HANDLE = undefined;
var g_hChildStd_OUT_Wr: win.HANDLE = undefined;

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

    var saAttr: win.SECURITY_ATTRIBUTES = undefined;
    saAttr.nLength = @sizeOf(win.SECURITY_ATTRIBUTES);
    saAttr.bInheritHandle = win.TRUE;
    saAttr.lpSecurityDescriptor = null;

    try win.CreatePipe(&g_hChildStd_OUT_Rd, &g_hChildStd_OUT_Wr, &saAttr);
    try win.SetHandleInformation(g_hChildStd_OUT_Rd, win.HANDLE_FLAG_INHERIT, 0);

    try win.CreatePipe(&g_hChildStd_IN_Rd, &g_hChildStd_IN_Wr, &saAttr);
    try win.SetHandleInformation(g_hChildStd_IN_Wr, win.HANDLE_FLAG_INHERIT, 0);

    var startupinfow: win.STARTUPINFOW = std.mem.zeroes(win.STARTUPINFOW);
    startupinfow.cb = @sizeOf(win.STARTUPINFOW);
    startupinfow.dwFlags = win.STARTF_USESTDHANDLES;
    startupinfow.hStdInput = g_hChildStd_IN_Rd;
    startupinfow.hStdOutput = g_hChildStd_OUT_Wr;
    startupinfow.hStdError = g_hChildStd_OUT_Wr;

    var process_info: win.PROCESS_INFORMATION = std.mem.zeroes(win.PROCESS_INFORMATION);
    defer win.CloseHandle(process_info.hProcess);
    defer win.CloseHandle(process_info.hThread);

    try win.CreateProcessW(
        null,
        @constCast(sh_utf16.ptr), // command line
        null, // process security attributes
        null, // primary thread security attributes
        win.TRUE, // handles are inherited
        .{}, // creation flags
        null, // use parent's environment
        null, // use parent's current directory
        &startupinfow, // STARTUPINFO pointer
        &process_info, // receives PROCESS_INFORMATION
    );

    win.CloseHandle(g_hChildStd_IN_Rd);
    win.CloseHandle(g_hChildStd_OUT_Wr);

    const command: []const win.CHAR = "echo Hello from Command Prompt!\n";
    try WriteToPipe(command);

    const hParentStdOut: win.HANDLE = try win.GetStdHandle(win.STD_OUTPUT_HANDLE);
    defer win.CloseHandle(hParentStdOut);
    try ReadFromPipe(hParentStdOut);

    try win.WaitForSingleObject(process_info.hProcess, win.INFINITE);
}

fn WriteToPipe(command: []const win.CHAR) !void {
    _ = win.WriteFile(g_hChildStd_IN_Wr, command, null) catch {};
    win.CloseHandle(g_hChildStd_IN_Wr);
}

fn ReadFromPipe(handle: win.HANDLE) !void {
    var dwRead: usize = undefined;
    var chBuf: [BUFSIZE]win.CHAR = undefined;

    while (true) {
        dwRead = try win.ReadFile(g_hChildStd_OUT_Rd, &chBuf, null);
        if (dwRead == 0) break;

        _ = win.WriteFile(handle, chBuf[0..dwRead], null) catch {};
    }
    win.CloseHandle(g_hChildStd_OUT_Rd);
}
