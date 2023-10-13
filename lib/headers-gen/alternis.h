// not currently generated, that will/should be a zig feature. We should consider contributing it

#include <cstdint> // for uint64_t
#include <stddef.h> // for size_t

typedef unsigned char zigbool; // extern bool as defined by zig

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

DialogueContext* ade_dialogue_ctx_create_json(
    const char* json_ptr,
    size_t json_len,
    uint64_t randomSeed,
    zigbool no_interpolate,
    const char** err
);

void ade_dialogue_ctx_destroy(DialogueContext* ctx);
void ade_dialogue_ctx_reset(DialogueContext* ctx);

size_t ade_dialogue_ctx_set_callback(
    DialogueContext* ctx,
    const char* name,
    size_t name_len,
    void (*const callback)(void*),
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

void ade_dialogue_ctx_step(DialogueContext* ctx, StepResult* return_val);
