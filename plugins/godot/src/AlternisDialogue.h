#ifndef ALTERNIS_DIALOGUE_H
#define ALTERNIS_DIALOGUE_H

#include <stddef.h>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <alternis.h>

namespace alternis {

class AlternisDialogue : public godot::Node {
    GDCLASS(AlternisDialogue, godot::Node)

    struct CallbackInfo {
        AlternisDialogue* owner;
        godot::StringName name;
        godot::Callable callable;
        CallbackInfo* next = nullptr;
    };

    godot::String resource_path;
    DialogueContext* ade_ctx = nullptr;
    // if 0, a random number will be used for the seed
    uint64_t random_seed = 0;
    bool interpolate = true;

    CallbackInfo* first_callback = nullptr;
    CallbackInfo* last_callback = nullptr;

protected:
    static void _bind_methods();

public:
    AlternisDialogue();
    ~AlternisDialogue();

    virtual void _ready() override;

    void set_resource_path(const godot::String path);
    godot::String get_resource_path();

    void set_random_seed(const uint64_t value);
    uint64_t get_random_seed();

    void set_interpolate(const bool value);
    bool get_interpolate();

    void reset();
    godot::Dictionary step();
    void reply(size_t replyId);

    void set_variable_string(const godot::StringName, const godot::String);
    void set_variable_boolean(const godot::StringName, const bool);
    void set_callback(const godot::StringName, godot::Callable);
};

} // godot;

#endif
