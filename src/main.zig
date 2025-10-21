const std = @import("std");
const win = std.os.windows;

const HPCON = win.LPVOID;
const LPPROC_THREAD_ATTRIBUTE_LIST = ?*anyopaque;

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: win.DWORD_PTR = 131_094;

extern "kernel32" fn InitializeProcThreadAttributeList(
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
    dwAttributeCount: win.DWORD,
    dwFlags: win.DWORD,
    lpSize: *win.SIZE_T,
) callconv(.winapi) win.BOOL;

extern "kernel32" fn UpdateProcThreadAttribute(
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
    dwFlags: win.DWORD,
    Attribute: win.DWORD_PTR,
    lpValue: *win.PVOID,
    cbSize: win.SIZE_T,
    lpPreviousValue: ?win.PVOID,
    lpReturnSize: ?*win.SIZE_T,
) callconv(.winapi) win.BOOL;

extern "kernel32" fn CreatePseudoConsole(
    size: win.COORD,
    hInput: win.HANDLE,
    hOutput: win.HANDLE,
    dwFlags: win.DWORD,
    phPC: *HPCON,
) callconv(.winapi) win.HRESULT;

const STARTUPINFOEXW = extern struct {
    StartupInfo: win.STARTUPINFOW,
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
};

const BUFSIZE = 4096;

var g_hChildStd_IN_Rd: win.HANDLE = undefined;
var g_hChildStd_IN_Wr: win.HANDLE = undefined;
var g_hChildStd_OUT_Rd: win.HANDLE = undefined;
var g_hChildStd_OUT_Wr: win.HANDLE = undefined;

fn PrepareStartupInformation(allocator: std.mem.Allocator, hpc: *HPCON, psi: *STARTUPINFOEXW) !win.HRESULT {
    var si: STARTUPINFOEXW = std.mem.zeroes(STARTUPINFOEXW);
    si.StartupInfo.cb = @sizeOf(STARTUPINFOEXW);
    si.StartupInfo.dwFlags = win.STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = g_hChildStd_IN_Rd;
    si.StartupInfo.hStdOutput = g_hChildStd_OUT_Wr;
    si.StartupInfo.hStdError = g_hChildStd_OUT_Wr;

    var bytesRequired: win.SIZE_T = undefined;
    _ = InitializeProcThreadAttributeList(null, 1, 0, &bytesRequired);

    const lpAttributeList = try allocator.alloc(u8, bytesRequired);

    if (InitializeProcThreadAttributeList(
        lpAttributeList.ptr,
        1,
        0,
        &bytesRequired,
    ) == 0) {
        allocator.free(lpAttributeList);
        return win.unexpectedError(win.GetLastError());
    }

    if (UpdateProcThreadAttribute(
        lpAttributeList.ptr,
        0,
        PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
        hpc,
        @sizeOf(HPCON),
        null,
        null,
    ) == 0) {
        allocator.free(lpAttributeList);
        return win.unexpectedError(win.GetLastError());
    }

    si.lpAttributeList = lpAttributeList.ptr;

    psi.* = si;

    return win.S_OK;
}

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

    var hpc: HPCON = undefined;
    if (CreatePseudoConsole(
        .{ .X = 1, .Y = 1 },
        g_hChildStd_IN_Rd,
        g_hChildStd_OUT_Wr,
        0,
        &hpc,
    ) != win.S_OK) return win.unexpectedError(win.GetLastError());

    var psi: STARTUPINFOEXW = undefined;
    if (try PrepareStartupInformation(
        allocator,
        &hpc,
        &psi,
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
