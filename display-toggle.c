#include "display-control.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

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

static int report_error(DTDResult result, const DTDDisplayState *state) {
    fprintf(stderr, "Error: %s", dtd_result_message(result));
    if (state != NULL && state->cg_error != 0) {
        fprintf(stderr, " (CGError %d)", state->cg_error);
    }
    fprintf(stderr, ".\n");

    if (result == DTD_ERROR_CONFIGURATION && state != NULL &&
        !state->builtin_display_active) {
        fprintf(stderr,
                "Recovery: close and reopen the lid, reconnect the external "
                "display, log out, or reboot.\n");
    }

    return result == DTD_ERROR_PRIVATE_API_UNAVAILABLE ? 3 : 2;
}

int main(int argc, char **argv) {
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

    DTDDisplayState state = {0};
    DTDResult result = dtd_get_display_state(&state);
    if (result != DTD_SUCCESS) {
        return report_error(result, &state);
    }

    if (strcmp(command, "status") == 0) {
        printf("Built-in display: %s (id %u); active external displays: %u\n",
               state.builtin_display_active ? "on" : "off",
               state.builtin_display_id,
               state.active_external_display_count);
        return 0;
    }

    bool enable = strcmp(command, "on") == 0 ||
                  (strcmp(command, "toggle") == 0 &&
                   !state.builtin_display_active);
    if (enable == state.builtin_display_active) {
        printf("Built-in display is already %s.\n", enable ? "on" : "off");
        return 0;
    }

    result = dtd_set_builtin_display_enabled(enable, &state);
    if (result != DTD_SUCCESS) {
        return report_error(result, &state);
    }

    printf("Built-in display: %s\n", enable ? "on" : "off");
    return 0;
}
