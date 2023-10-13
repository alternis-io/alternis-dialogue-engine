//#include "../../lib/zig-out/lib/libalternis.a"
#include "AlternisDialogue.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void AlternisDialogue::_bind_methods() {
  ClassDB::bind_method(D_METHOD("reset"), &AlternisDialogue::reset);
  ClassDB::bind_method(D_METHOD("reply"), &AlternisDialogue::reply);
  ClassDB::bind_method(D_METHOD("step"), &AlternisDialogue::step);
  ClassDB::add_property("AlternisDialogue", PropertyInfo(Variant::STRING, "alternis_json", PROPERTY_HINT_FILE, "json"), "set_resource", "get_resource");
  ADD_SIGNAL(MethodInfo("position_changed", PropertyInfo(Variant::OBJECT, "node"), PropertyInfo(Variant::STRING, "text")));
}

AlternisDialogue::AlternisDialogue() {
	// Initialize any variables here.
}

AlternisDialogue::~AlternisDialogue() {
	// Add your cleanup here.
}

void AlternisDialogue::step() {
}

void AlternisDialogue::reset() {
}

void AlternisDialogue::reply() {
}
