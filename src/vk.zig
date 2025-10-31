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

    try std.testing.expectEqual(indices.to_array(), [_]u32{ 1, 2 });
}

const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,
};

const required_device_extensions = [_][]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};
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
swapchain_framebuffers: []c.VkFramebuffer,
render_pass: c.VkRenderPass,
pipeline_layout: c.VkPipelineLayout,
pipeline: c.VkPipeline,
command_pool: c.VkCommandPool,
command_buffer: c.VkCommandBuffer,
image_available_semaphore: c.VkSemaphore,
render_finished_semaphore: c.VkSemaphore,
in_flight_fence: c.VkFence,

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

    var graphics_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(
        device,
        queue_family_indices.graphics_family.?,
        0,
        &graphics_queue,
    );

    var present_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(
        device,
        queue_family_indices.present_family.?,
        0,
        &present_queue,
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

    const render_pass = try createRenderPass(device, surface_format.format);

    var pipeline_layout: c.VkPipelineLayout = undefined;
    const pipeline = try createGraphicsPipeline(device, extent, render_pass, &pipeline_layout);

    const swapchain_framebuffers = try createFramebuffers(
        allocator,
        device,
        swapchain_image_views,
        render_pass,
        extent,
    );

    const command_pool = try createCommandPool(device, queue_family_indices);

    const command_buffer = try createCommandBuffer(device, command_pool);

    const sync_objects = try createSyncObjects(device);

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
        .swapchain_framebuffers = swapchain_framebuffers,
        .render_pass = render_pass,
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,
        .command_pool = command_pool,
        .command_buffer = command_buffer,
        .image_available_semaphore = sync_objects.image_available_semaphore,
        .render_finished_semaphore = sync_objects.render_finished_semaphore,
        .in_flight_fence = sync_objects.in_flight_fence,
    };
}

pub fn destroy(self: @This()) void {
    _ = c.vkDeviceWaitIdle(self.device);

    c.vkDestroySemaphore(self.device, self.image_available_semaphore, null);
    c.vkDestroySemaphore(self.device, self.render_finished_semaphore, null);
    c.vkDestroyFence(self.device, self.in_flight_fence, null);
    c.vkDestroyCommandPool(self.device, self.command_pool, null);
    for (self.swapchain_framebuffers) |framebuffer| {
        c.vkDestroyFramebuffer(self.device, framebuffer, null);
    }
    c.vkDestroyPipeline(self.device, self.pipeline, null);
    c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
    c.vkDestroyRenderPass(self.device, self.render_pass, null);
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

fn createShaderModule(code: []align(@alignOf(u32)) const u8, device: c.VkDevice) !c.VkShaderModule {
    const create_info: c.VkShaderModuleCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = std.mem.bytesAsSlice(u32, code).ptr,
    };

    var shader_module: c.VkShaderModule = undefined;
    std.debug.assert(c.vkCreateShaderModule(device, &create_info, null, &shader_module) == c.VK_SUCCESS);

    return shader_module;
}

fn createRenderPass(device: c.VkDevice, swapchain_image_format: c.VkFormat) !c.VkRenderPass {
    const color_attachment = c.VkAttachmentDescription{
        .format = swapchain_image_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = c.VkSubpassDescription{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
    };

    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    const render_pass_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    var render_pass: c.VkRenderPass = undefined;
    std.debug.assert(c.vkCreateRenderPass(device, &render_pass_info, null, &render_pass) == c.VK_SUCCESS);

    return render_pass;
}

fn createGraphicsPipeline(
    device: c.VkDevice,
    swapchain_extent: c.VkExtent2D,
    render_pass: c.VkRenderPass,
    pipeline_layout: *c.VkPipelineLayout,
) !c.VkPipeline {
    const vert_shader align(4) = @embedFile("shaders/vert.spv").*;
    const vert_shader_module: c.VkShaderModule = try createShaderModule(&vert_shader, device);
    defer c.vkDestroyShaderModule(device, vert_shader_module, null);

    const frag_shader align(4) = @embedFile("shaders/frag.spv").*;
    const frag_shader_module: c.VkShaderModule = try createShaderModule(&frag_shader, device);
    defer c.vkDestroyShaderModule(device, frag_shader_module, null);

    const vert_shader_stage = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
    };

    const frag_shader_stage = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
    };

    const stages = [_]c.VkPipelineShaderStageCreateInfo{
        vert_shader_stage,
        frag_shader_stage,
    };

    const vertex_input_state = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    const input_assembly_state = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, // TODO use VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
        .primitiveRestartEnable = c.VK_FALSE, // TODO use VK_TRUE
    };

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(swapchain_extent.width),
        .height = @floatFromInt(swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain_extent,
    };

    //const dynamic_states = c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    //
    //const dynamic_state = c.VkPipelineDynamicStateCreateInfo{
    //    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    //    .dynamicStateCount = dynamic_states.len,
    //    .pDynamicStates = dynamic_states,
    //};
    //
    //const viewport_state = c.VkPipelineViewportStateCreateInfo{
    //    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    //    .viewportCount = 1,
    //    .scissorCount = 1,
    //};
    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    const rasterization_state = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    const multisample_state = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_FALSE,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    const color_blend_state = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    std.debug.assert(
        c.vkCreatePipelineLayout(
            device,
            &pipeline_layout_info,
            null,
            pipeline_layout,
        ) == c.VK_SUCCESS,
    );

    const pipeline_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &stages,
        .pVertexInputState = &vertex_input_state,
        .pInputAssemblyState = &input_assembly_state,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterization_state,
        .pMultisampleState = &multisample_state,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blend_state,
        .pDynamicState = null,
        .layout = pipeline_layout.*,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    var graphics_pipeline: c.VkPipeline = undefined;
    std.debug.assert(
        c.vkCreateGraphicsPipelines(
            device,
            null,
            1,
            &pipeline_info,
            null,
            &graphics_pipeline,
        ) == c.VK_SUCCESS,
    );

    return graphics_pipeline;
}

fn createFramebuffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    image_views: []c.VkImageView,
    render_pass: c.VkRenderPass,
    extent: c.VkExtent2D,
) ![]c.VkFramebuffer {
    var framebuffers = try allocator.alloc(c.VkFramebuffer, image_views.len);

    for (image_views, 0..) |image_view, i| {
        const attachments = [_]c.VkImageView{image_view};

        const framebuffer_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = extent.width,
            .height = extent.height,
            .layers = 1,
        };

        std.debug.assert(
            c.vkCreateFramebuffer(
                device,
                &framebuffer_info,
                null,
                &framebuffers[i],
            ) == c.VK_SUCCESS,
        );
    }

    return framebuffers;
}

fn createCommandPool(device: c.VkDevice, queue_family_indices: QueueFamilyIndices) !c.VkCommandPool {
    const pool_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
    };

    var command_pool: c.VkCommandPool = undefined;
    std.debug.assert(c.vkCreateCommandPool(device, &pool_info, null, &command_pool) == c.VK_SUCCESS);

    return command_pool;
}

fn createCommandBuffer(device: c.VkDevice, command_pool: c.VkCommandPool) !c.VkCommandBuffer {
    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: c.VkCommandBuffer = undefined;
    std.debug.assert(c.vkAllocateCommandBuffers(device, &alloc_info, &command_buffer) == c.VK_SUCCESS);

    return command_buffer;
}

fn recordCommandBuffer(
    self: @This(),
    image_index: u32,
) !void {
    var begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    std.debug.assert(c.vkBeginCommandBuffer(self.command_buffer, &begin_info) == c.VK_SUCCESS);

    const clear_color = c.VkClearValue{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } };
    const render_pass_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = self.render_pass,
        .framebuffer = self.swapchain_framebuffers[image_index],
        .renderArea = .{ .offset = c.VkOffset2D{ .x = 0, .y = 0 }, .extent = self.swapchain_extent },
        .clearValueCount = 1,
        .pClearValues = &clear_color,
    };

    c.vkCmdBeginRenderPass(self.command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdBindPipeline(self.command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);

    //VkViewport viewport{};
    //viewport.x = 0.0f;
    //viewport.y = 0.0f;
    //viewport.width = static_cast<float>(swapChainExtent.width);
    //viewport.height = static_cast<float>(swapChainExtent.height);
    //viewport.minDepth = 0.0f;
    //viewport.maxDepth = 1.0f;
    //vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

    //VkRect2D scissor{};
    //scissor.offset = {0, 0};
    //scissor.extent = swapChainExtent;
    //vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

    c.vkCmdDraw(self.command_buffer, 3, 1, 0, 0);

    c.vkCmdEndRenderPass(self.command_buffer);
    std.debug.assert(c.vkEndCommandBuffer(self.command_buffer) == c.VK_SUCCESS);
}

const SyncObjects = struct {
    image_available_semaphore: c.VkSemaphore,
    render_finished_semaphore: c.VkSemaphore,
    in_flight_fence: c.VkFence,
};

fn createSyncObjects(device: c.VkDevice) !SyncObjects {
    const semaphore_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fenceInfo = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    var sync_objects = SyncObjects{
        .image_available_semaphore = undefined,
        .render_finished_semaphore = undefined,
        .in_flight_fence = undefined,
    };

    std.debug.assert(
        c.vkCreateSemaphore(
            device,
            &semaphore_info,
            null,
            &sync_objects.image_available_semaphore,
        ) == c.VK_SUCCESS,
    );
    std.debug.assert(
        c.vkCreateSemaphore(
            device,
            &semaphore_info,
            null,
            &sync_objects.render_finished_semaphore,
        ) == c.VK_SUCCESS,
    );
    std.debug.assert(
        c.vkCreateFence(
            device,
            &fenceInfo,
            null,
            &sync_objects.in_flight_fence,
        ) == c.VK_SUCCESS,
    );

    return sync_objects;
}

pub fn drawFrame(self: @This()) !void {
    _ = c.vkWaitForFences(self.device, 1, &self.in_flight_fence, c.VK_TRUE, c.UINT64_MAX);
    _ = c.vkResetFences(self.device, 1, &self.in_flight_fence);

    var image_index: u32 = undefined;
    _ = c.vkAcquireNextImageKHR(
        self.device,
        self.swapchain,
        c.UINT64_MAX,
        self.image_available_semaphore,
        null,
        &image_index,
    );

    _ = c.vkResetCommandBuffer(self.command_buffer, 0);
    try self.recordCommandBuffer(image_index);

    const wait_semaphores = [_]c.VkSemaphore{self.image_available_semaphore};
    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const signal_semaphores = [_]c.VkSemaphore{self.render_finished_semaphore};
    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &wait_semaphores,
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &self.command_buffer,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &signal_semaphores,
        .pNext = null,
    };
    var submits = [_]c.VkSubmitInfo{submit_info};
    std.debug.assert(
        c.vkQueueSubmit(self.graphics_queue, 1, &submits, self.in_flight_fence) == c.VK_SUCCESS,
    );

    const swapchains = [_]c.VkSwapchainKHR{self.swapchain};
    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signal_semaphores,
        .swapchainCount = 1,
        .pSwapchains = &swapchains,
        .pImageIndices = &image_index,
        .pResults = null,
    };
    _ = c.vkQueuePresentKHR(self.present_queue, &present_info);
}
