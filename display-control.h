#ifndef DISPLAY_CONTROL_H
#define DISPLAY_CONTROL_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    DTD_SUCCESS = 0,
    DTD_ERROR_UNSUPPORTED_ARCHITECTURE,
    DTD_ERROR_PRIVATE_API_UNAVAILABLE,
    DTD_ERROR_DISPLAY_ENUMERATION,
    DTD_ERROR_BUILTIN_DISPLAY_NOT_FOUND,
    DTD_ERROR_NO_ACTIVE_EXTERNAL_DISPLAY,
    DTD_ERROR_CONFIGURATION
} DTDResult;

typedef struct {
    uint32_t builtin_display_id;
    bool builtin_display_active;
    uint32_t active_external_display_count;
    int32_t cg_error;
} DTDDisplayState;

DTDResult dtd_get_display_state(DTDDisplayState *state);
DTDResult dtd_set_builtin_display_enabled(bool enabled,
                                          DTDDisplayState *resulting_state);
DTDResult dtd_toggle_builtin_display(DTDDisplayState *resulting_state);
const char *dtd_result_message(DTDResult result);

#ifdef __cplusplus
}
#endif

#endif
