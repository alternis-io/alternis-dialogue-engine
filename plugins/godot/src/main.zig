const std = @import("std");

const c = @cImport({
    @cInclude("thirdparty/godot/gdextension_interface.h");
});

const INIT_ERROR = 0;
const INIT_SUCCESS = 1;

pub var _interface: ?c.GDExtensionPtrConstructor = null;
pub var _construct_StringName_from_String: ?c.GDExtensionPtrConstructor = null;
pub var _destroy_String: ?c.GDExtensionPtrDestructor = null;
pub var _destroy_StringName: ?c.GDExtensionPtrDestructor = null;

const gd = struct {
    const String = struct {
        ptr: ?*anyopaque = null,

        pub fn fromCString(str: []const u8) @This() {
            const interface = _interface orelse @panic("initialization should have already occurred");
            var result = @This(){};
            interface.string_new_with_utf8_chars_and_len(&result.ptr, str.ptr, str.len);
            return result;
        }
    };

    const StringName = struct {
        ptr: ?*anyopaque = null,

        pub fn fromCString(str: []const u8) @This() {
            const construct_StringName_from_String = _construct_StringName_from_String orelse @panic("initialization should have already occurred");
            const destroy_String = _destroy_String orelse @panic("initialization should have already occurred");

            const gd_string = String.fromCString(str);

            var result = @This(){};
            const constructor_args: [1]c.GDExtensionConstTypePtr = &.{ &gd_string };
            construct_StringName_from_String(&result, constructor_args);

            destroy_String(&gd_string);

            return result;
        }
    };
};

export fn initialize(user_data: ?*anyopaque, level: c.GDExtensionInitializationLevel) void {
    _ = user_data;

    if (level != c.GDEXTENSION_INITIALIZATION_SCENE) return;
    const interface = _interface orelse @panic("initialization should have already occurred");
    _ = interface;
}

export fn deinitialize(user_data: ?*anyopaque, level: c.GDExtensionInitializationLevel) void {
    _ = user_data;

    if (level != c.GDEXTENSION_INITIALIZATION_SCENE) return;
    const interface = _interface orelse @panic("initialization should have already occurred");
    _construct_StringName_from_String = interface.variant_get_ptr_constructor(c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, 2);
    _destroy_String = interface.variant_get_ptr_destructor(c.GDEXTENSION_VARIANT_TYPE_STRING);
    _destroy_StringName = interface.variant_get_ptr_destructor(c.GDEXTENSION_VARIANT_TYPE_STRING_NAME);
}

export fn alternis_extension_entry(
    in_interface: *const c.GDExtensionInterface,
    library: c.GDExtensionClassLibraryPtr,
    initialization: *c.GDExtensionInitialization,
) c.GDExtensionBool {
    _ = library;
    initialization.initialize = &initialize;
    initialization.deinitialize = &deinitialize;
    _interface = in_interface;
    return INIT_SUCCESS;
}
