const std = @import("std");

const vk = @import("vk.zig");
const win = @import("win.zig");

const BUFSIZE: comptime_int = 4096;

var g_hChildStd_IN_Rd: win.HANDLE = undefined;
var g_hChildStd_IN_Wr: win.HANDLE = undefined;
var g_hChildStd_OUT_Rd: win.HANDLE = undefined;
var g_hChildStd_OUT_Wr: win.HANDLE = undefined;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const hInstance: win.HINSTANCE = @ptrCast(win.GetModuleHandleW(null));
    const window_hwnd = try win.wWinMain(allocator, hInstance, null, null, 3);

    const vk_renderer = try vk.init(allocator, hInstance, window_hwnd);
    defer vk_renderer.destroy();

    _ = try win.runMessageLoop();

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

    var hpc: win.HPCON = undefined;
    if (win.CreatePseudoConsole(
        .{ .X = 1, .Y = 1 },
        g_hChildStd_IN_Rd,
        g_hChildStd_OUT_Wr,
        0,
        &hpc,
    ) != win.S_OK) return win.unexpectedError(win.GetLastError());

    var psi: win.STARTUPINFOEXW = undefined;
    if (try win.PrepareStartupInformation(
        allocator,
        &hpc,
        &psi,
        g_hChildStd_IN_Rd,
        g_hChildStd_OUT_Wr,
    ) != win.S_OK) return;

    var process_info: win.PROCESS_INFORMATION = std.mem.zeroes(win.PROCESS_INFORMATION);
    defer win.CloseHandle(process_info.hProcess);
    defer win.CloseHandle(process_info.hThread);

    try win.CreateProcessW(
        null,
        @constCast(sh_utf16.ptr), // command line
        null, // process security attributes
        null, // primary thread security attributes
        win.TRUE, // handles are inherited
        .{ .extended_startupinfo_present = true, .create_no_window = true }, // creation flags
        null, // use parent's environment
        null, // use parent's current directory
        &psi.StartupInfo, // STARTUPINFO pointer
        &process_info, // receives PROCESS_INFORMATION
    );

    win.CloseHandle(g_hChildStd_IN_Rd);
    win.CloseHandle(g_hChildStd_OUT_Wr);

    const command: []const win.CHAR = "echo Hello from Command Prompt!\n";
    try win.WriteToPipe(command, g_hChildStd_IN_Wr);

    const hParentStdOut: win.HANDLE = try win.GetStdHandle(win.STD_OUTPUT_HANDLE);
    defer win.CloseHandle(hParentStdOut);
    try win.ReadFromPipe(hParentStdOut, BUFSIZE, g_hChildStd_OUT_Rd);

    try win.WaitForSingleObject(process_info.hProcess, win.INFINITE);
}
