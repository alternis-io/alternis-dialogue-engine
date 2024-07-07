#pragma once

// not currently generated, that will/should be a zig feature. We should consider contributing it

// FIXME: document everything here! it's a primary interface for many users
// (or just contribute header generation to zig with doc-comment copying)

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h> // for uint64_t
#include <stddef.h> // for size_t

typedef unsigned char zigbool; // extern bool as defined by zig
typedef uint32_t usz; // configured id type for alternis

void ade_set_alloc(void*(*const in_malloc)(size_t), void(*const in_free)(void*));

struct DialogueContext;

struct StringSlice {
    char* ptr;
    size_t len;
};

struct SizeTSlice {
    size_t* ptr;
    size_t len;
};


struct Line {
    // Slice of utf8
    struct StringSlice speaker;
    struct StringSlice text;
    struct StringSlice metadata;
};

struct LineSlice {
    Line* ptr;
    size_t len;
};


enum StepResultTag { STEP_RESULT_DONE, STEP_RESULT_OPTIONS, STEP_RESULT_LINE, STEP_RESULT_FUNCTION_CALLED };

struct StepResult {
    unsigned char tag;
    union {
        // void done;
        struct {
            LineSlice texts;
            SizeTSlice ids;
        } options;
        Line line;
        // void function_called;
    };
};

typedef enum DiagnosticErrors {
    NoError = 0,

    // alloc
    OutOfMemory,

    // json
    MissingField,
    UnexpectedToken,
    Overflow,
    InvalidCharacter,
    InvalidNumber,
    InvalidEnumTag,
    DuplicateField,
    UnknownField,
    LengthMismatch,
    SyntaxError,
    UnexpectedEndOfInput,
    BufferUnderrun,
    ValueTooLong,

    // alternis
    AlternisUnknownVersion,
    AlternisBadNextNode,
    AlternisInvalidNode,
    AlternisDefaultSeedUnsupportedPlatform
} DiagnosticErrors;

struct Diagnostic {
    zigbool _needs_free;
    int error_code;
    StringSlice error_message;
};

void ade_diagnostic_destroy(Diagnostic* self);

DialogueContext* ade_dialogue_ctx_create_json(
    const char* json_ptr,
    size_t json_len,
    uint64_t randomSeed,
    zigbool no_interpolate,
    Diagnostic* const c_diagnostic
);

void ade_dialogue_ctx_destroy(DialogueContext* ctx);
void ade_dialogue_ctx_reset(DialogueContext* ctx, usz dialogue_id, size_t node_index);
void ade_dialogue_ctx_reply(DialogueContext* ctx, usz dialogue_id, size_t reply_id);
size_t ade_dialogue_ctx_get_node_by_label(DialogueContext* ctx, usz dialogue_id, const char* label_ptr, size_t label_len);

void ade_dialogue_ctx_set_callback(
    DialogueContext* ctx,
    const char* name,
    size_t name_len,
    void (*const callback)(void*),
    void* payload
);

struct SetAllCallbacksPayload {
    void* inner_payload;
    StringSlice name;
};

void ade_dialogue_ctx_set_all_callbacks(
    DialogueContext* ctx,
    void (*const callback)(SetAllCallbacksPayload*),
    void* payload
);

void ade_dialogue_ctx_set_variable_boolean(
    DialogueContext* ctx,
    const char* name,
    size_t name_len,
    zigbool value
);

void ade_dialogue_ctx_set_variable_string(
    DialogueContext* ctx,
    const char* name,
    size_t name_len,
    const char* value,
    size_t value_len
);

void ade_dialogue_ctx_step(DialogueContext* ctx, usz dialogue_id, StepResult* return_val);

#ifdef __cplusplus
} // extern "C"
#endif
