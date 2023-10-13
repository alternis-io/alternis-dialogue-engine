#ifndef ALTERNIS_DIALOGUE_H
#define ALTERNIS_DIALOGUE_H

#include <godot_cpp/classes/node.hpp>

namespace godot {

class AlternisDialogue : public Node {
	GDCLASS(AlternisDialogue, Node)

protected:
	static void _bind_methods();

public:
	AlternisDialogue();
	~AlternisDialogue();

    void reset();
    void step();
    void reply();
};

}

#endif
