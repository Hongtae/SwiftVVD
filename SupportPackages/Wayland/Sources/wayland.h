#pragma once

#include "protocols/xdg-shell-client.h"
#include "protocols/xdg-decoration-client.h"

/*
  Helper macro for Swift.
*/
#define WL_INTERFACE_PTR(x) const struct wl_interface* x ## _ptr = &x

/* core interfaces */
WL_INTERFACE_PTR(wl_display_interface);
WL_INTERFACE_PTR(wl_registry_interface);
WL_INTERFACE_PTR(wl_callback_interface);
WL_INTERFACE_PTR(wl_compositor_interface);
WL_INTERFACE_PTR(wl_shm_pool_interface);
WL_INTERFACE_PTR(wl_shm_interface);
WL_INTERFACE_PTR(wl_buffer_interface);
WL_INTERFACE_PTR(wl_data_offer_interface);
WL_INTERFACE_PTR(wl_data_source_interface);
WL_INTERFACE_PTR(wl_data_device_interface);
WL_INTERFACE_PTR(wl_data_device_manager_interface);
WL_INTERFACE_PTR(wl_shell_interface);
WL_INTERFACE_PTR(wl_shell_surface_interface);
WL_INTERFACE_PTR(wl_surface_interface);
WL_INTERFACE_PTR(wl_seat_interface);
WL_INTERFACE_PTR(wl_pointer_interface);
WL_INTERFACE_PTR(wl_keyboard_interface);
WL_INTERFACE_PTR(wl_touch_interface);
WL_INTERFACE_PTR(wl_output_interface);
WL_INTERFACE_PTR(wl_region_interface);
WL_INTERFACE_PTR(wl_subcompositor_interface);
WL_INTERFACE_PTR(wl_subsurface_interface);

/* xdg-shell */
WL_INTERFACE_PTR(xdg_wm_base_interface);

/* xdg-decoration */
WL_INTERFACE_PTR(zxdg_decoration_manager_v1_interface);
WL_INTERFACE_PTR(zxdg_toplevel_decoration_v1_interface);
