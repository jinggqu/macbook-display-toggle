#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
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

static void usage(FILE *stream) {
    fprintf(stream,
            "Usage: display-toggle [toggle|on|off|status]\n"
            "       don\n"
            "       doff\n"
            "\n"
            "With no command, display-toggle toggles the built-in display.\n"
            "don and doff are shortcuts for display-toggle on and off.\n");
}

static const char *base_name(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash == NULL ? path : slash + 1;
}

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

    core_graphics = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY | RTLD_LOCAL);
    sky_light = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY | RTLD_LOCAL);
    (void)core_graphics;
    (void)sky_light;

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
        fprintf(stderr,
                "Error: required private macOS display API is unavailable.\n");
        if (configure == NULL) {
            fprintf(stderr,
                    "  Missing CGSConfigureDisplayEnabled / "
                    "SLSConfigureDisplayEnabled\n");
        }
        if (get_list == NULL) {
            fprintf(stderr,
                    "  Missing CGSGetDisplayList / SLSGetDisplayList\n");
        }
        return false;
    }

    memcpy(&api->configure_enabled, &configure, sizeof(configure));
    memcpy(&api->get_display_list, &get_list, sizeof(get_list));
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

static CGError copy_active_displays(DisplayList *result) {
    return copy_display_list(CGGetActiveDisplayList, result);
}

static bool list_contains(const DisplayList *list, CGDirectDisplayID id) {
    for (uint32_t i = 0; i < list->count; ++i) {
        if (list->ids[i] == id) {
            return true;
        }
    }
    return false;
}

static bool find_builtin_display(const PrivateAPI *api,
                                 CGDirectDisplayID *builtin_id) {
    DisplayList all = {0};
    CGError error = copy_display_list(api->get_display_list, &all);
    if (error != kCGErrorSuccess) {
        fprintf(stderr, "Error: cannot enumerate displays (CGError %d).\n",
                error);
        return false;
    }

    bool found = false;
    for (uint32_t i = 0; i < all.count; ++i) {
        if (CGDisplayIsBuiltin(all.ids[i])) {
            *builtin_id = all.ids[i];
            found = true;
            break;
        }
    }
    free_display_list(&all);

    if (!found) {
        fprintf(stderr,
                "Error: built-in display not found (is the lid closed?).\n");
    }
    return found;
}

static bool get_display_state(CGDirectDisplayID builtin_id,
                              bool *is_active,
                              uint32_t *active_external_count) {
    DisplayList active = {0};
    CGError error = copy_active_displays(&active);
    if (error != kCGErrorSuccess) {
        fprintf(stderr,
                "Error: cannot enumerate active displays (CGError %d).\n",
                error);
        return false;
    }

    *is_active = list_contains(&active, builtin_id);
    *active_external_count = 0;
    for (uint32_t i = 0; i < active.count; ++i) {
        if (!CGDisplayIsBuiltin(active.ids[i])) {
            ++*active_external_count;
        }
    }

    free_display_list(&active);
    return true;
}

static bool set_builtin_enabled(const PrivateAPI *api,
                                CGDirectDisplayID builtin_id,
                                bool enabled) {
    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess || config == NULL) {
        fprintf(stderr,
                "Error: cannot begin display configuration (CGError %d).\n",
                error);
        return false;
    }

    error = api->configure_enabled(config, builtin_id, enabled);
    if (error != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        fprintf(stderr,
                "Error: cannot %s built-in display (CGError %d).\n",
                enabled ? "enable" : "disable", error);
        return false;
    }

    error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    if (error != kCGErrorSuccess) {
        fprintf(stderr,
                "Error: cannot commit display configuration (CGError %d).\n",
                error);
        return false;
    }
    return true;
}

int main(int argc, char **argv) {
#if !defined(__arm64__)
    fprintf(stderr, "Error: this tool supports Apple Silicon Macs only.\n");
    return 2;
#endif

    const char *invoked_as = base_name(argv[0]);
    const char *command = NULL;
    bool shortcut = false;
    if (strcmp(invoked_as, "don") == 0) {
        command = "on";
        shortcut = true;
    } else if (strcmp(invoked_as, "doff") == 0) {
        command = "off";
        shortcut = true;
    } else {
        command = argc == 1 ? "toggle" : argv[1];
    }

    if ((shortcut && argc != 1) || (!shortcut && argc > 2)) {
        usage(stderr);
        return 1;
    }
    if (strcmp(command, "-h") == 0 || strcmp(command, "--help") == 0 ||
        strcmp(command, "help") == 0) {
        usage(stdout);
        return 0;
    }
    if (strcmp(command, "toggle") != 0 && strcmp(command, "on") != 0 &&
        strcmp(command, "off") != 0 && strcmp(command, "status") != 0) {
        fprintf(stderr, "Error: unknown command '%s'.\n", command);
        usage(stderr);
        return 1;
    }

    PrivateAPI api = {0};
    if (!load_private_api(&api)) {
        return 3;
    }

    CGDirectDisplayID builtin_id = kCGNullDirectDisplay;
    if (!find_builtin_display(&api, &builtin_id)) {
        return 2;
    }

    bool is_active = false;
    uint32_t active_external_count = 0;
    if (!get_display_state(builtin_id, &is_active,
                           &active_external_count)) {
        return 2;
    }

    if (strcmp(command, "status") == 0) {
        printf("Built-in display: %s (id %u); active external displays: %u\n",
               is_active ? "on" : "off", builtin_id,
               active_external_count);
        return 0;
    }

    bool enable = strcmp(command, "on") == 0 ||
                  (strcmp(command, "toggle") == 0 && !is_active);
    if (enable == is_active) {
        printf("Built-in display is already %s.\n", enable ? "on" : "off");
        return 0;
    }

    if (!enable && active_external_count == 0) {
        fprintf(stderr,
                "Refusing to turn off the built-in display: no active "
                "external display was found.\n");
        return 2;
    }

    if (!set_builtin_enabled(&api, builtin_id, enable)) {
        if (enable) {
            fprintf(stderr,
                    "Recovery: close and reopen the lid, reconnect the "
                    "external display, or reboot.\n");
        }
        return 2;
    }

    printf("Built-in display: %s\n", enable ? "on" : "off");
    return 0;
}
