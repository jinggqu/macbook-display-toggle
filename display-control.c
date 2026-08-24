#include "display-control.h"

#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <stdlib.h>
#include <string.h>

typedef CGError (*ConfigureDisplayEnabledFn)(CGDisplayConfigRef,
                                             CGDirectDisplayID,
                                             bool);
typedef CGError (*GetDisplayListFn)(uint32_t,
                                    CGDirectDisplayID *,
                                    uint32_t *);

typedef struct {
    ConfigureDisplayEnabledFn configure_enabled;
    GetDisplayListFn get_display_list;
} PrivateAPI;

typedef struct {
    CGDirectDisplayID *ids;
    uint32_t count;
} DisplayList;

static void *find_symbol(void *handle, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol == NULL && handle != NULL) {
        symbol = dlsym(handle, name);
    }
    return symbol;
}

static bool load_private_api(PrivateAPI *api) {
    static void *core_graphics = NULL;
    static void *sky_light = NULL;

    if (core_graphics == NULL) {
        core_graphics = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY | RTLD_LOCAL);
    }
    if (sky_light == NULL) {
        sky_light = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL);
    }

    void *configure =
        find_symbol(core_graphics, "CGSConfigureDisplayEnabled");
    if (configure == NULL) {
        configure = find_symbol(sky_light, "SLSConfigureDisplayEnabled");
    }

    void *get_list = find_symbol(core_graphics, "CGSGetDisplayList");
    if (get_list == NULL) {
        get_list = find_symbol(sky_light, "SLSGetDisplayList");
    }

    if (configure == NULL || get_list == NULL) {
        return false;
    }

    memcpy(&api->configure_enabled, &configure,
           sizeof(api->configure_enabled));
    memcpy(&api->get_display_list, &get_list,
           sizeof(api->get_display_list));
    return true;
}

static void free_display_list(DisplayList *list) {
    free(list->ids);
    list->ids = NULL;
    list->count = 0;
}

static CGError copy_display_list(GetDisplayListFn get_list,
                                 DisplayList *result) {
    uint32_t count = 0;
    CGError error = get_list(0, NULL, &count);
    if (error != kCGErrorSuccess) {
        return error;
    }

    result->ids = NULL;
    result->count = 0;
    if (count == 0) {
        return kCGErrorSuccess;
    }

    CGDirectDisplayID *ids = calloc(count, sizeof(*ids));
    if (ids == NULL) {
        return kCGErrorFailure;
    }

    uint32_t actual_count = count;
    error = get_list(count, ids, &actual_count);
    if (error != kCGErrorSuccess) {
        free(ids);
        return error;
    }

    result->ids = ids;
    result->count = actual_count;
    return kCGErrorSuccess;
}

static bool list_contains(const DisplayList *list, CGDirectDisplayID id) {
    for (uint32_t i = 0; i < list->count; ++i) {
        if (list->ids[i] == id) {
            return true;
        }
    }
    return false;
}

/*
 * macOS can leave virtual or placeholder displays in the active list while a
 * physical display is being disconnected. Such entries have no IOKit display
 * service. The vendor fallback keeps compatibility if Apple removes the
 * deprecated service-port API: physical vendors use 16-bit IDs, whereas
 * virtual displays commonly use a FourCC pseudo-vendor ID.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static bool display_is_hardware_backed(CGDirectDisplayID display_id) {
    if (CGDisplayIOServicePort(display_id) != MACH_PORT_NULL) {
        return true;
    }
    uint32_t vendor = CGDisplayVendorNumber(display_id);
    return vendor != 0 && vendor <= UINT16_MAX;
}
#pragma clang diagnostic pop

bool dtd_is_hardware_external_display(uint32_t display_id) {
#if !defined(__arm64__)
    (void)display_id;
    return false;
#else
    return display_id != kCGNullDirectDisplay &&
           !CGDisplayIsBuiltin(display_id) &&
           display_is_hardware_backed(display_id);
#endif
}

static DTDResult find_builtin_display(const PrivateAPI *api,
                                      CGDirectDisplayID *builtin_id,
                                      int32_t *cg_error) {
    DisplayList all = {0};
    CGError error = copy_display_list(api->get_display_list, &all);
    if (error != kCGErrorSuccess) {
        *cg_error = error;
        return DTD_ERROR_DISPLAY_ENUMERATION;
    }

    DTDResult result = DTD_ERROR_BUILTIN_DISPLAY_NOT_FOUND;
    for (uint32_t i = 0; i < all.count; ++i) {
        if (CGDisplayIsBuiltin(all.ids[i])) {
            *builtin_id = all.ids[i];
            result = DTD_SUCCESS;
            break;
        }
    }

    free_display_list(&all);
    return result;
}

static DTDResult copy_state(const PrivateAPI *api, DTDDisplayState *state) {
    state->builtin_display_id = kCGNullDirectDisplay;
    state->builtin_display_active = false;
    state->active_external_display_count = 0;
    state->cg_error = kCGErrorSuccess;

    CGDirectDisplayID builtin_id = kCGNullDirectDisplay;
    DTDResult result =
        find_builtin_display(api, &builtin_id, &state->cg_error);
    if (result != DTD_SUCCESS) {
        return result;
    }

    DisplayList active = {0};
    CGError error = copy_display_list(CGGetActiveDisplayList, &active);
    if (error != kCGErrorSuccess) {
        state->cg_error = error;
        return DTD_ERROR_DISPLAY_ENUMERATION;
    }

    state->builtin_display_id = builtin_id;
    state->builtin_display_active = list_contains(&active, builtin_id);
    for (uint32_t i = 0; i < active.count; ++i) {
        if (dtd_is_hardware_external_display(active.ids[i])) {
            ++state->active_external_display_count;
        }
    }

    free_display_list(&active);
    return DTD_SUCCESS;
}

static DTDResult configure_display_enabled(CGDirectDisplayID display_id,
                                           bool enabled,
                                           int32_t *cg_error) {
    PrivateAPI api = {0};
    if (!load_private_api(&api)) {
        return DTD_ERROR_PRIVATE_API_UNAVAILABLE;
    }

    if (enabled) {
        CGDisplayConfigRef recommit = NULL;
        CGError recommit_error = CGBeginDisplayConfiguration(&recommit);
        if (recommit_error == kCGErrorSuccess && recommit != NULL) {
            (void)CGCompleteDisplayConfiguration(
                recommit, kCGConfigureForSession);
        }
    }

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess || config == NULL) {
        *cg_error = error;
        return DTD_ERROR_CONFIGURATION;
    }

    error = api.configure_enabled(config, display_id, enabled);
    if (error != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        *cg_error = error;
        return DTD_ERROR_CONFIGURATION;
    }

    error = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    if (error != kCGErrorSuccess) {
        *cg_error = error;
        return DTD_ERROR_CONFIGURATION;
    }

    *cg_error = kCGErrorSuccess;
    return DTD_SUCCESS;
}

DTDResult dtd_get_display_state(DTDDisplayState *state) {
    if (state == NULL) {
        return DTD_ERROR_DISPLAY_ENUMERATION;
    }

#if !defined(__arm64__)
    *state = (DTDDisplayState){0};
    return DTD_ERROR_UNSUPPORTED_ARCHITECTURE;
#endif

    PrivateAPI api = {0};
    if (!load_private_api(&api)) {
        *state = (DTDDisplayState){0};
        return DTD_ERROR_PRIVATE_API_UNAVAILABLE;
    }

    return copy_state(&api, state);
}

DTDResult dtd_get_active_external_display_count(uint32_t *count) {
    if (count == NULL) {
        return DTD_ERROR_DISPLAY_ENUMERATION;
    }

    *count = 0;
#if !defined(__arm64__)
    return DTD_ERROR_UNSUPPORTED_ARCHITECTURE;
#endif

    DisplayList active = {0};
    CGError error = copy_display_list(CGGetActiveDisplayList, &active);
    if (error != kCGErrorSuccess) {
        return DTD_ERROR_DISPLAY_ENUMERATION;
    }

    for (uint32_t i = 0; i < active.count; ++i) {
        if (dtd_is_hardware_external_display(active.ids[i])) {
            ++*count;
        }
    }

    free_display_list(&active);
    return DTD_SUCCESS;
}

DTDResult dtd_set_builtin_display_enabled(bool enabled,
                                          DTDDisplayState *resulting_state) {
    DTDDisplayState current = {0};
    DTDResult result = dtd_get_display_state(&current);
    if (result != DTD_SUCCESS) {
        if (resulting_state != NULL) {
            *resulting_state = current;
        }
        return result;
    }

    if (current.builtin_display_active == enabled) {
        if (resulting_state != NULL) {
            *resulting_state = current;
        }
        return DTD_SUCCESS;
    }

    if (!enabled && current.active_external_display_count == 0) {
        if (resulting_state != NULL) {
            *resulting_state = current;
        }
        return DTD_ERROR_NO_ACTIVE_EXTERNAL_DISPLAY;
    }

    if (enabled) {
        return dtd_restore_builtin_display(
            current.builtin_display_id, resulting_state);
    }

    result = configure_display_enabled(current.builtin_display_id, enabled,
                                       &current.cg_error);
    if (result != DTD_SUCCESS) {
        if (resulting_state != NULL) {
            *resulting_state = current;
        }
        return result;
    }

    current.builtin_display_active = enabled;
    if (resulting_state != NULL) {
        *resulting_state = current;
    }
    return DTD_SUCCESS;
}

DTDResult dtd_restore_builtin_display(uint32_t builtin_display_id,
                                      DTDDisplayState *resulting_state) {
    DTDDisplayState recovered = {
        .builtin_display_id = builtin_display_id,
        .builtin_display_active = false,
        .active_external_display_count = 0,
        .cg_error = kCGErrorSuccess,
    };

    PrivateAPI api = {0};
    if (!load_private_api(&api)) {
        if (resulting_state != NULL) {
            *resulting_state = recovered;
        }
        return DTD_ERROR_PRIVATE_API_UNAVAILABLE;
    }

    CGDirectDisplayID current_builtin_id = kCGNullDirectDisplay;
    int32_t discovery_error = kCGErrorSuccess;
    DTDResult discovery_result = find_builtin_display(
        &api, &current_builtin_id, &discovery_error);
    if (discovery_result == DTD_SUCCESS) {
        builtin_display_id = current_builtin_id;
        recovered.builtin_display_id = current_builtin_id;
    }

    if (builtin_display_id == kCGNullDirectDisplay) {
        recovered.cg_error = discovery_error;
        if (resulting_state != NULL) {
            *resulting_state = recovered;
        }
        return DTD_ERROR_BUILTIN_DISPLAY_NOT_FOUND;
    }

    uint32_t external_count = 0;
    if (dtd_get_active_external_display_count(&external_count) ==
        DTD_SUCCESS) {
        recovered.active_external_display_count = external_count;
    }

    DTDResult result = configure_display_enabled(
        builtin_display_id, true, &recovered.cg_error);
    bool is_online = CGDisplayIsOnline(builtin_display_id);
    bool is_active = CGDisplayIsActive(builtin_display_id);
    if (is_online || is_active) {
        result = DTD_SUCCESS;
        recovered.builtin_display_active = true;
        recovered.cg_error = kCGErrorSuccess;
    } else if (result == DTD_SUCCESS) {
        result = DTD_ERROR_CONFIGURATION;
        recovered.cg_error = kCGErrorCannotComplete;
    }

    if (resulting_state != NULL) {
        *resulting_state = recovered;
    }
    return result;
}

DTDResult dtd_toggle_builtin_display(DTDDisplayState *resulting_state) {
    DTDDisplayState current = {0};
    DTDResult result = dtd_get_display_state(&current);
    if (result != DTD_SUCCESS) {
        if (resulting_state != NULL) {
            *resulting_state = current;
        }
        return result;
    }

    return dtd_set_builtin_display_enabled(!current.builtin_display_active,
                                           resulting_state);
}

const char *dtd_result_message(DTDResult result) {
    switch (result) {
        case DTD_SUCCESS:
            return "Success";
        case DTD_ERROR_UNSUPPORTED_ARCHITECTURE:
            return "This tool supports Apple Silicon Macs only";
        case DTD_ERROR_PRIVATE_API_UNAVAILABLE:
            return "Required private macOS display APIs are unavailable";
        case DTD_ERROR_DISPLAY_ENUMERATION:
            return "Unable to enumerate displays";
        case DTD_ERROR_BUILTIN_DISPLAY_NOT_FOUND:
            return "Built-in display not found (the lid may be closed)";
        case DTD_ERROR_NO_ACTIVE_EXTERNAL_DISPLAY:
            return "No active external display; refusing to turn off the "
                   "built-in display";
        case DTD_ERROR_CONFIGURATION:
            return "Unable to change the display configuration";
    }
    return "Unknown display error";
}
