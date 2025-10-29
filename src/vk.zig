const std = @import("std");
const win = std.os.windows;

const c = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", {});
    @cInclude("vulkan/vulkan.h");
});

const QueueFamilyIndices = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    pub fn same(self: QueueFamilyIndices) bool {
        return self.graphics_family.? == self.present_family.?;
    }

    pub fn to_array(self: QueueFamilyIndices) [2]u32 {
        return .{ self.graphics_family.?, self.present_family.? };
    }
};

test "QueueFamilyIndices methods" {
    var indices: QueueFamilyIndices = .{
        .graphics_family = 1,
        .present_family = 1,
    };
    try std.testing.expect(indices.same());

    indices.present_family = 2;
    try std.testing.expect(!indices.same());

    try std.testing.expectEqual(indices.to_array(), [2]u32{ 1, 2 });
}

const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,
};

const required_device_extensions: [1][]const u8 = .{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};
const width = 640;
const height = 360;

instance: c.VkInstance,
surface: c.VkSurfaceKHR,
physical_device: c.VkPhysicalDevice,
device: c.VkDevice,
graphics_queue: c.VkQueue,
present_queue: c.VkQueue,
swapchain: c.VkSwapchainKHR,
swapchain_image_format: c.VkFormat,
swapchain_extent: c.VkExtent2D,
swapchain_images: []c.VkImage,
swapchain_image_views: []c.VkImageView,

pub fn init(
    allocator: std.mem.Allocator,
    hinstance: win.HINSTANCE,
    window_hwnd: win.HWND,
) !@This() {
    const vk_instance = try createInstance();
    const surface = try createSurface(vk_instance, hinstance, window_hwnd);

    // TODO let user specify which device to use (user_set_device param)

    const physical_devices: []c.VkPhysicalDevice = try getPhysicalDevices(allocator, vk_instance);
    defer allocator.free(physical_devices);

    var physical_device: c.VkPhysicalDevice = undefined;
    var swapchain_support: SwapChainSupportDetails = undefined;

    physical_device = for (physical_devices) |device| {
        if (try isDeviceSuitable(allocator, device, surface, &swapchain_support))
            break device;
    } else return error.FailedToFindSuitablePhysicalDevice;

    defer allocator.free(swapchain_support.formats);
    defer allocator.free(swapchain_support.present_modes);

    var device_properties: c.VkPhysicalDeviceProperties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
    c.vkGetPhysicalDeviceProperties(physical_device, &device_properties);
    std.debug.print("physical device {}: {s}, type {}\n", .{
        device_properties.deviceID,
        device_properties.deviceName,
        device_properties.deviceType,
    });

    const queue_family_indices: QueueFamilyIndices = try findQueueFamilies(
        allocator,
        physical_device,
        surface,
    );
    std.debug.assert(queue_family_indices.graphics_family != null and
        queue_family_indices.present_family != null);
    std.debug.print("graphics queue idx: {}, present queue idx: {}\n", .{
        queue_family_indices.graphics_family.?,
        queue_family_indices.present_family.?,
    });

    const enabled_features: c.VkPhysicalDeviceFeatures = .{};
    const device: c.VkDevice = try createLogicalDevice(
        allocator,
        physical_device,
        queue_family_indices,
        enabled_features,
    );

    const graphics_queue: c.VkQueue = std.mem.zeroes(c.VkQueue);
    c.vkGetDeviceQueue(
        device,
        queue_family_indices.graphics_family.?,
        0,
        @ptrCast(@constCast(&graphics_queue)),
    );

    const present_queue: c.VkQueue = std.mem.zeroes(c.VkQueue);
    c.vkGetDeviceQueue(
        device,
        queue_family_indices.present_family.?,
        0,
        @ptrCast(@constCast(&present_queue)),
    );

    const surface_format: c.VkSurfaceFormatKHR = try chooseSwapSurfaceFormat(swapchain_support.formats);
    const extent: c.VkExtent2D = try chooseSwapExtent(swapchain_support.capabilities);
    const swapchain = try createSwapChain(
        swapchain_support,
        surface,
        surface_format,
        extent,
        device,
        queue_family_indices,
    );

    var image_count: u32 = undefined;
    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &image_count, null);
    const swapchain_images = try allocator.alloc(c.VkImage, image_count);
    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &image_count, swapchain_images.ptr);

    const swapchain_image_views = try createImageViews(
        allocator,
        device,
        swapchain_images,
        surface_format.format,
    );

    _ = try createGraphicsPipeline();

    return .{
        .instance = vk_instance,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .swapchain = swapchain,
        .swapchain_image_format = surface_format.format,
        .swapchain_extent = extent,
        .swapchain_images = swapchain_images,
        .swapchain_image_views = swapchain_image_views,
    };
}

pub fn destroy(self: @This()) void {
    for (self.swapchain_image_views) |image_view| {
        c.vkDestroyImageView(self.device, image_view, null);
    }
    c.vkDestroySwapchainKHR(self.device, self.swapchain, null);
    c.vkDestroyDevice(self.device, null);
    c.vkDestroySurfaceKHR(self.instance, self.surface, null);
    c.vkDestroyInstance(self.instance, null);
}

fn createInstance() !c.VkInstance {
    var app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "pity",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "none",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    const extensions = [_][*c]const u8{
        c.VK_KHR_SURFACE_EXTENSION_NAME,
        c.VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
    };

    var create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = extensions.len,
        .ppEnabledExtensionNames = @ptrCast(&extensions),
    };

    var instance: c.VkInstance = undefined;
    std.debug.assert(c.vkCreateInstance(&create_info, null, &instance) == c.VK_SUCCESS);

    return instance;
}

fn createSurface(vk_instance: c.VkInstance, hinstance: win.HINSTANCE, window_hwnd: win.HWND) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;

    const create_info = c.VkWin32SurfaceCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .hinstance = @ptrCast(@alignCast(@constCast(hinstance))),
        .hwnd = @ptrCast(@alignCast(@constCast(window_hwnd))),
    };

    std.debug.assert(c.vkCreateWin32SurfaceKHR(vk_instance, &create_info, null, &surface) == c.VK_SUCCESS);

    return surface;
}

fn findQueueFamilies(
    allocator: std.mem.Allocator,
    device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = undefined;

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    var present_support: c.VkBool32 = c.VK_FALSE;
    for (queue_families, 0..) |queue_family, i| {
        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphics_family = @intCast(i);
        }

        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &present_support);
        if (present_support == c.VK_TRUE) indices.present_family = @intCast(i);

        if (indices.graphics_family != null and indices.present_family != null) break;
    }

    return indices;
}

fn isDeviceSuitable(
    allocator: std.mem.Allocator,
    device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
    swapchain_support_ptr: *SwapChainSupportDetails,
) !bool {
    //var device_features: c.VkPhysicalDeviceFeatures = undefined;
    //c.vkGetPhysicalDeviceFeatures(device, &device_features);

    var required_extensions: std.BufSet = .init(allocator);

    for (required_device_extensions) |extension| try required_extensions.insert(extension);

    var property_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &property_count, null);

    const properties = try allocator.alloc(c.VkExtensionProperties, property_count);
    _ = c.vkEnumerateDeviceExtensionProperties(device, null, &property_count, properties.ptr);

    for (properties) |property| {
        const cstr_ptr: [*:0]const u8 = @ptrCast(&property.extensionName);
        const name_slice = std.mem.span(cstr_ptr);
        required_extensions.remove(name_slice);
    }

    if (required_extensions.count() == 0) {
        const swapchain_support: SwapChainSupportDetails = try querySwapChainSupport(
            allocator,
            device,
            surface,
        );
        if (swapchain_support.formats.len != 0 and
            swapchain_support.present_modes.len != 0)
        {
            swapchain_support_ptr.* = swapchain_support;
            return true;
        }
    }

    return false;
}

fn getPhysicalDevices(allocator: std.mem.Allocator, vk_instance: c.VkInstance) ![]c.VkPhysicalDevice {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(vk_instance, &device_count, null);

    std.debug.assert(device_count > 0);

    const devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    _ = c.vkEnumeratePhysicalDevices(vk_instance, &device_count, devices.ptr);

    return devices;
}

fn createLogicalDevice(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    queue_family_indices: QueueFamilyIndices,
    enabled_features: c.VkPhysicalDeviceFeatures,
) !c.VkDevice {
    var queue_create_infos: std.ArrayList(c.VkDeviceQueueCreateInfo) = try .initCapacity(allocator, 2);
    defer queue_create_infos.deinit(allocator);

    const g_queue_create_info: c.VkDeviceQueueCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
        .queueCount = 1,
        .pQueuePriorities = &@as(f32, 1.0),
    };
    try queue_create_infos.append(allocator, g_queue_create_info);

    if (queue_family_indices.graphics_family.? != queue_family_indices.present_family.?) {
        const p_queue_create_info: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_family_indices.present_family.?,
            .queueCount = 1,
            .pQueuePriorities = &@as(f32, 1.0),
        };
        try queue_create_infos.append(allocator, p_queue_create_info);
    }

    const create_info: c.VkDeviceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .enabledExtensionCount = required_device_extensions.len,
        .ppEnabledExtensionNames = @ptrCast(@constCast(&required_device_extensions)),
        .pEnabledFeatures = &enabled_features,
    };

    var device: c.VkDevice = undefined;
    std.debug.assert(c.vkCreateDevice(physical_device, &create_info, null, &device) == c.VK_SUCCESS);

    return device;
}

fn querySwapChainSupport(
    allocator: std.mem.Allocator,
    device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !SwapChainSupportDetails {
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities);

    var format_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, null);

    const formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
    if (format_count != 0)
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, formats.ptr);

    var present_mode_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null);

    const present_modes = try allocator.alloc(c.VkPresentModeKHR, present_mode_count);
    if (present_mode_count != 0)
        _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(
            device,
            surface,
            &present_mode_count,
            present_modes.ptr,
        );

    return .{
        .capabilities = capabilities,
        .formats = formats,
        .present_modes = present_modes,
    };
}

fn chooseSwapSurfaceFormat(available_formats: []c.VkSurfaceFormatKHR) !c.VkSurfaceFormatKHR {
    for (available_formats) |available_format| {
        if (available_format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            available_format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return available_format;
        }
    }

    return available_formats[0];
}

fn chooseSwapPresentMode(available_present_modes: []c.VkPresentModeKHR) !c.VkPresentModeKHR {
    for (available_present_modes) |available_present_mode| {
        if (available_present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return available_present_mode;
        }
    }

    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(capabilities: c.VkSurfaceCapabilitiesKHR) !c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        var actual_extent: c.VkExtent2D = .{
            .width = width,
            .height = height,
        };

        actual_extent.width = @max(
            capabilities.minImageExtent.width,
            @min(capabilities.maxImageExtent.width, actual_extent.width),
        );
        actual_extent.height = @max(
            capabilities.minImageExtent.height,
            @min(capabilities.maxImageExtent.height, actual_extent.height),
        );

        return actual_extent;
    }
}

fn createSwapChain(
    swapchain_support: SwapChainSupportDetails,
    surface: c.VkSurfaceKHR,
    surface_format: c.VkSurfaceFormatKHR,
    extent: c.VkExtent2D,
    device: c.VkDevice,
    queue_family_indices: QueueFamilyIndices,
) !c.VkSwapchainKHR {
    const present_mode: c.VkPresentModeKHR = try chooseSwapPresentMode(swapchain_support.present_modes);

    var image_count: u32 = swapchain_support.capabilities.minImageCount + 1;
    if (swapchain_support.capabilities.maxImageCount > 0 and
        image_count > swapchain_support.capabilities.maxImageCount)
    {
        image_count = swapchain_support.capabilities.maxImageCount;
    }

    var create_info: c.VkSwapchainCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .preTransform = swapchain_support.capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    if (!queue_family_indices.same()) {
        create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount = 2;
        create_info.pQueueFamilyIndices = @ptrCast(@constCast(&queue_family_indices.to_array()));
    } else {
        create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        create_info.queueFamilyIndexCount = 0; // optional
        create_info.pQueueFamilyIndices = null; // optional
    }

    var swapchain: c.VkSwapchainKHR = undefined;
    std.debug.assert(c.vkCreateSwapchainKHR(device, &create_info, null, &swapchain) == c.VK_SUCCESS);

    return swapchain;
}

fn createImageViews(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    swapchain_images: []c.VkImage,
    format: c.VkFormat,
) ![]c.VkImageView {
    var swapchain_image_views = try allocator.alloc(c.VkImageView, swapchain_images.len);
    errdefer allocator.free(swapchain_image_views);

    for (swapchain_images, 0..) |image, i| {
        var create_info: c.VkImageViewCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        std.debug.assert(c.vkCreateImageView(device, &create_info, null, &swapchain_image_views[i]) == c.VK_SUCCESS);
    }

    return swapchain_image_views;
}

fn createGraphicsPipeline() !void {}
