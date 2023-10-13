const std = @import("std");

const c = @cImport({
    @cInclude("thirdparty/godot/gdextension_interface.h");
});

const INIT_ERROR = 0;
const INIT_SUCCESS = 1;

export fn alternis_extension_entry(
    interface: *const c.GDExtensionInterface,
    library: c.GDExtensionClassLibraryPtr,
    initialization: *c.GDExtensionInitialization,
) c.GDExtensionBool {
    _ = interface;
    _ = library;
    _ = initialization;
    return INIT_SUCCESS;
}
