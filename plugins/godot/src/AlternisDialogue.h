#ifndef ALTERNIS_DIALOGUE_H
#define ALTERNIS_DIALOGUE_H

#include <stddef.h>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <alternis.h>

// FIXME: don't use godot namespace
namespace godot {

class AlternisDialogue : public Node {
	GDCLASS(AlternisDialogue, Node)
    String resource_path;
    DialogueContext* ade_ctx;
    // if 0, clock will be used
    uint64_t random_seed;
    bool interpolate = true;

protected:
	static void _bind_methods();

public:
	AlternisDialogue();
	~AlternisDialogue();

    virtual void _ready() override;

    void set_resource_path(const String& path);
    String get_resource_path() const;

    void set_random_seed(uint64_t value);
    uint64_t get_random_seed() const;

    void set_interpolate(bool value);
    bool get_interpolate() const;

    void reset();
    Dictionary step();
    void reply(size_t replyId);

};

} // godot;

#endif
