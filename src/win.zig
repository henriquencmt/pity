const std = @import("std");
const win = std.os.windows;
const vk = @import("vk.zig");

pub const CHAR = win.CHAR;
pub const HPCON = win.LPVOID;
pub const HANDLE = win.HANDLE;
pub const HINSTANCE = win.HINSTANCE;
pub const SECURITY_ATTRIBUTES = win.SECURITY_ATTRIBUTES;
pub const PROCESS_INFORMATION = win.PROCESS_INFORMATION;

const LPPROC_THREAD_ATTRIBUTE_LIST = ?*anyopaque;

const WNDPROC = *const fn (
    hwnd: win.HWND,
    uMsg: win.UINT,
    wParam: win.WPARAM,
    lParam: win.LPARAM,
) callconv(.winapi) win.LRESULT;

pub const TRUE = win.TRUE;
pub const S_OK = win.S_OK;
pub const INFINITE = win.INFINITE;
pub const HANDLE_FLAG_INHERIT = win.HANDLE_FLAG_INHERIT;
pub const STD_OUTPUT_HANDLE = win.STD_OUTPUT_HANDLE;

const WS_OVERLAPPED = 0x00000000;
const WS_CAPTION = WS_BORDER | WS_DLGFRAME;
const WS_BORDER = 0x00800000;
const WS_DLGFRAME = 0x00400000;
const WS_SYSMENU = 0x00080000;
const WS_THICKFRAME = 0x00040000;
const WS_MINIMIZEBOX = 0x00020000;
const WS_MAXIMIZEBOX = 0x00010000;
const WS_OVERLAPPEDWINDOW = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;

const WM_DESTROY = 0x0002;
const WM_PAINT = 0x000F;

const CW_USEDEFAULT = @as(i32, @bitCast(@as(u32, 0x80000000)));

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: win.DWORD_PTR = 131_094;

const COLOR_WINDOW = 5;

pub const STARTUPINFOEXW = extern struct {
    StartupInfo: win.STARTUPINFOW,
    lpAttributeList: LPPROC_THREAD_ATTRIBUTE_LIST,
};

const WNDCLASSEXW = extern struct {
    cbSize: win.UINT = @sizeOf(WNDCLASSEXW),
    style: win.UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?win.HINSTANCE,
    hIcon: ?win.HICON,
    hCursor: ?win.HCURSOR,
    hbrBackground: ?win.HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
    hIconSm: ?win.HICON,
};

pub const MSG = extern struct {
    hWnd: ?win.HWND,
    message: win.UINT,
    wParam: win.WPARAM,
    lParam: win.LPARAM,
    time: win.DWORD,
    pt: win.POINT,
    lPrivate: win.DWORD,
};

const PAINTSTRUCT = extern struct {
    hdc: win.HDC,
    fErase: win.BOOL,
    rcPaint: win.RECT,
    fRestore: win.BOOL,
    fIncUpdate: win.BOOL,
    rgbReserved: [32]win.BYTE,
};

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

pub extern "kernel32" fn CreatePseudoConsole(
    size: win.COORD,
    hInput: win.HANDLE,
    hOutput: win.HANDLE,
    dwFlags: win.DWORD,
    phPC: *HPCON,
) callconv(.winapi) win.HRESULT;

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) win.HINSTANCE;

extern "user32" fn RegisterClassExW(window_class: *const WNDCLASSEXW) callconv(.winapi) win.ATOM;

extern "user32" fn CreateWindowExW(
    dwExStyle: win.DWORD,
    lpClassName: [*:0]const u16,
    lpWindowName: [*:0]const u16,
    dwStyle: win.DWORD,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWindParent: ?win.HWND,
    hMenu: ?win.HMENU,
    hInstance: ?win.HINSTANCE,
    lpParam: ?win.LPVOID,
) callconv(.winapi) vk.c.HWND;

extern "user32" fn ShowWindow(hWnd: vk.c.HWND, nCmdShow: i32) callconv(.winapi) win.BOOL;

pub extern "user32" fn GetMessageW(
    lpMsg: *MSG,
    hWnd: ?win.HWND,
    wMsgFilterMin: win.UINT,
    wMsgFilterMax: win.UINT,
) callconv(.winapi) win.BOOL;

pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) win.BOOL;

pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) win.LRESULT;

extern "user32" fn DefWindowProcW(
    hWnd: win.HWND,
    Msg: win.UINT,
    wParam: win.WPARAM,
    lParam: win.LPARAM,
) callconv(.winapi) win.LRESULT;

extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.winapi) void;

extern "user32" fn BeginPaint(hWnd: win.HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) win.HDC;

extern "user32" fn EndPaint(hWnd: win.HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) win.BOOL;

extern "user32" fn FillRect(hDC: win.HDC, lprc: *const win.RECT, hbr: win.HBRUSH) callconv(.winapi) i32;

pub const CreatePipe = win.CreatePipe;
pub const CreateProcessW = win.CreateProcessW;
pub const CloseHandle = win.CloseHandle;
pub const SetHandleInformation = win.SetHandleInformation;
pub const GetStdHandle = win.GetStdHandle;
pub const unexpectedError = win.unexpectedError;
pub const GetLastError = win.GetLastError;
pub const WaitForSingleObject = win.WaitForSingleObject;

pub fn PrepareStartupInformation(
    allocator: std.mem.Allocator,
    hpc: *HPCON,
    psi: *STARTUPINFOEXW,
    g_hChildStd_IN_Rd: win.HANDLE,
    g_hChildStd_OUT_Wr: win.HANDLE,
) !win.HRESULT {
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

pub fn WriteToPipe(command: []const win.CHAR, handle: win.HANDLE) !void {
    _ = win.WriteFile(handle, command, null) catch {};
    //win.CloseHandle(handle);
}

pub fn ReadFromPipe(handle: win.HANDLE, bufsize: comptime_int, read_handle: win.HANDLE) !void {
    var dwRead: usize = undefined;
    var chBuf: [bufsize]win.CHAR = undefined;

    std.debug.print("2 before loop\n", .{});
    while (true) {
        std.debug.print("2.1 read\n", .{});
        dwRead = try win.ReadFile(read_handle, &chBuf, null);
        if (dwRead == 0) break;

        std.debug.print("2.2 write\n", .{});
        _ = win.WriteFile(handle, chBuf[0..dwRead], null) catch {};
        std.debug.print("\n2.3 end\n", .{});
    }

    std.debug.print("2 after loop\n", .{});
    win.CloseHandle(read_handle);
}

fn WindowProc(
    hwnd: win.HWND,
    uMsg: win.UINT,
    wParam: win.WPARAM,
    lParam: win.LPARAM,
) callconv(.winapi) win.LRESULT {
    switch (uMsg) {
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        WM_PAINT => {
            var ps: PAINTSTRUCT = undefined;
            const hdc: win.HDC = BeginPaint(hwnd, &ps);

            // All painting occurs here, between BeginPaint and EndPaint.
            _ = FillRect(hdc, &ps.rcPaint, @ptrFromInt(COLOR_WINDOW + 1));

            _ = EndPaint(hwnd, &ps);
            return 0;
        },
        else => return DefWindowProcW(hwnd, uMsg, wParam, lParam)
    }
}

pub fn wWinMain(
    allocator: std.mem.Allocator,
    hInstance: ?win.HINSTANCE,
    hPrevInstance: ?win.HINSTANCE,
    pCmdLine: ?win.PWSTR,
    nCmdShow: c_int,
) !vk.c.HWND {
    _ = hPrevInstance;
    _ = pCmdLine;

    const class_name_raw: []win.WCHAR = try std.unicode.utf8ToUtf16LeAlloc(allocator, "pity window class");
    defer allocator.free(class_name_raw);
    const CLASS_NAME = try allocator.allocSentinel(u16, class_name_raw.len, 0);
    std.mem.copyForwards(u16, CLASS_NAME[0..class_name_raw.len], class_name_raw);
    var wc: WNDCLASSEXW = std.mem.zeroes(WNDCLASSEXW);
    wc.cbSize = @sizeOf(WNDCLASSEXW);
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = CLASS_NAME;
    _ = RegisterClassExW(&wc);

    const window_name_raw: []win.WCHAR = try std.unicode.utf8ToUtf16LeAlloc(allocator, "pity");
    defer allocator.free(window_name_raw);
    const WINDOW_NAME = try allocator.allocSentinel(u16, window_name_raw.len, 0);
    std.mem.copyForwards(u16, WINDOW_NAME[0..window_name_raw.len], window_name_raw);
    const hwnd: vk.c.HWND = CreateWindowExW(
        0, // Optional window styles.
        CLASS_NAME, // Window class
        WINDOW_NAME, // Window text
        WS_OVERLAPPEDWINDOW, // Window style

        // Size and position
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        null, // Parent window
        null, // Menu
        hInstance, // Instance handle
        null, // Additional application data
    );

    //if (hwnd == null) return 0;

    _ = ShowWindow(hwnd, nCmdShow);

    return hwnd;
}

pub fn runMessageLoop() !c_int {
    var msg: MSG = undefined;
    while (GetMessageW(&msg, null, 0, 0) > 0) {
        //std.debug.print("msg: {any}\n", .{msg});
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
    }

    return 0;
}
