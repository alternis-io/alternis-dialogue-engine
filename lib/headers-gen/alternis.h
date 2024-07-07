#ifndef LIB_ALTERNIS_H
#define LIB_ALTERNIS_H

// not currently generated, that zig feature is broken

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h> // for uint64_t
#include <stddef.h> // for size_t

typedef unsigned char zigbool; // extern bool as defined by zig
typedef uint32_t usz; // configured id type for alternis

/**
 * Set an allocator in the form of two function pointers,
 * - one to receive an allocation of a certain byte size (like libc malloc)
 * - one to free a previously allocated region (like libc free).
 *
 * For more control you can provide an allocator using the zig interface.
 */
void ade_set_alloc(void*(*const in_malloc)(size_t), void(*const in_free)(void*));

struct DialogueContext;

/* a slice of utf8 characters in memory */
typedef struct StringSlice {
    /* undefined if len is 0 */
    char* ptr;
    size_t len;
} StringSlice;

/* a slice of system-word size (sizet/intptr_t) integers in memory */
typedef struct SizeTSlice {
    /* undefined if len is 0 */
    size_t* ptr;
    size_t len;
} SizeTSlice;


/* a line spoken by a character in a dialogue */
typedef struct Line {
    /* utf8 name of the speaker of the line */
    struct StringSlice speaker;
    /* utf8 content of the spoken line */
    struct StringSlice text;
    /* optional json metadata of the line */
    struct StringSlice metadata;
} Line;

/* a slice of lines in memory */
typedef struct LineSlice {
    /* undefined if len is 0 */
    Line* ptr;
    size_t len;
} LineSlice;


/* possible states of a step result */
enum StepResultTag {
    STEP_RESULT_DONE,
    STEP_RESULT_OPTIONS,
    STEP_RESULT_LINE,
    STEP_RESULT_FUNCTION_CALLED
};

/* the result returned from calling ade_dialogue_ctx_step */
typedef struct StepResult {
    /* the StepResultTag tagging the union of possible result states */
    unsigned char tag;
    /* the union holding the value of results */
    union {
        struct {
            /* the slice of options that may be chosen by a character */
            LineSlice texts;
            /* the slice of ids for each option that may be chosen by a character */
            SizeTSlice ids;
        } options;
        /* a line to be spoken */
        Line line;
        // void states:
        // - done;
        // - function_called
    };
} StepResult;

/* possible errors from initializing a dialogue from data */
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

// FIXME: rename to error in the c api since it is not separate from the
// concept of errors as it is in zig
/**
 * A diagnostic for when an error is returned.
 * Don't forget to call ade_diagnostic_destroy on it after passing it
 * to any other functions.
 */
struct Diagnostic {
    /* initialize to false. Do not mutate this value, it is internal */
    zigbool _needs_free;
    /* a value of type DiagnosticErrors with the error result */
    int error_code;
    /* a string describing an error */
    StringSlice error_message;
};

/* must be called on diagnostics that were passed to any functions */
void ade_diagnostic_destroy(Diagnostic* self);

/**
 * Attempt to create a DialogueContext from an alternis json document
 * in a buffer.
 * if it failed, returns null and fills the Diagnostic pointer
 * with information about why
 */
DialogueContext* ade_dialogue_ctx_create_json(
    /** pointer to buffer with json */
    const char* json_ptr,
    /** length of buffer with json */
    size_t json_len,
    /** random seed to use for choice nodes */
    uint64_t randomSeed,
    /** disable interpolating of text with braces (e.g. "hello {name}") */
    zigbool no_interpolate,
    /** diagnostic information about any errors that occurred during creation */
    Diagnostic* const c_diagnostic
);

/** destroy a previously created DialogueContext */
void ade_dialogue_ctx_destroy(DialogueContext* ctx);

/**
 * reset a previously created DialogueContext to a particular node
 * 0 is always the start of the dialogue. You may get labled nodes
 * using the ade_dialogue_ctx_get_node_by_label function
 * and reset to that.
 */
void ade_dialogue_ctx_reset(DialogueContext* ctx, usz dialogue_id, size_t node_index);

/** if the dialogue is at a choice, reply with an option by its id */
void ade_dialogue_ctx_reply(DialogueContext* ctx, usz dialogue_id, size_t reply_id);

/* get the id for a node from its label */
size_t ade_dialogue_ctx_get_node_by_label(DialogueContext* ctx, usz dialogue_id, const char* label_ptr, size_t label_len);

/* set a function pointer and pointer payload to call when an event is reached  */
void ade_dialogue_ctx_set_callback(
    DialogueContext* ctx,
    const char* name,
    size_t name_len,
    void (*const callback)(void*),
    void* payload
);

/**
 * Payload passed to the function registered in
 * ade_dialogue_ctx_set_all_callbacks when any call back is called.
 */
typedef struct SetAllCallbacksPayload {
    /**
     * the global payload passed during the registeration of
     * ade_dialogue_ctx_set_callback
     */
    void* inner_payload;
    /** the name of the event/function that was called */
    StringSlice name;
} SetAllCallbacksPayload ;

/**
 * Mutually exclusive with ade_dialogue_ctx_set_callback.
 * Register one function * to be called with SetAllCallbacksPayload
 * containing the event name and your optional payload, 
 */
void ade_dialogue_ctx_set_all_callbacks(
    DialogueContext* ctx,
    void (*const callback)(SetAllCallbacksPayload*),
    void* payload
);

/**
 * Set a boolean variable by name in the given DialogueContext
 */
void ade_dialogue_ctx_set_variable_boolean(
    DialogueContext* ctx,
    const char* name,
    size_t name_len,
    zigbool value
);

/**
 * Set a string variable by name in the given DialogueContext
 */
void ade_dialogue_ctx_set_variable_string(
    DialogueContext* ctx,
    const char* name,
    size_t name_len,
    const char* value,
    size_t value_len
);

/**
 * Step to the next state for the given dialogue within the DialogueContext
 * See the StepResult type for possible states.
 */
void ade_dialogue_ctx_step(DialogueContext* ctx, usz dialogue_id, StepResult* return_val);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // LIB_ALTERNIS_H
