#include "AlternisDialogue.h"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

namespace alternis {

void AlternisDialogue::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_resource_path"), &AlternisDialogue::get_resource_path);
    ClassDB::bind_method(D_METHOD("set_resource_path", "resource_path"), &AlternisDialogue::set_resource_path);
    ClassDB::bind_method(D_METHOD("get_interpolate"), &AlternisDialogue::get_interpolate);
    ClassDB::bind_method(D_METHOD("set_interpolate", "interpolate"), &AlternisDialogue::set_interpolate);
    ClassDB::bind_method(D_METHOD("get_random_seed"), &AlternisDialogue::get_random_seed);
    ClassDB::bind_method(D_METHOD("set_random_seed", "random_seed"), &AlternisDialogue::set_random_seed);

    ClassDB::add_property("AlternisDialogue",
                          PropertyInfo(Variant::STRING, "alternis_json", PROPERTY_HINT_FILE, "json"),
                          "set_resource_path",
                          "get_resource_path");

    ClassDB::add_property("AlternisDialogue",
                          PropertyInfo(Variant::INT, "random_seed"),
                          "set_random_seed",
                          "get_random_seed");

    ClassDB::add_property("AlternisDialogue",
                          PropertyInfo(Variant::BOOL, "interpolate"),
                          "set_interpolate",
                          "get_interpolate");

    ADD_SIGNAL(MethodInfo("dialogue_stepped",
                          PropertyInfo(Variant::OBJECT, "self"),
                          PropertyInfo(Variant::DICTIONARY, "result")));

    ADD_SIGNAL(MethodInfo("function_called",
                          PropertyInfo(Variant::OBJECT, "self"),
                          PropertyInfo(Variant::STRING, "name")));

    ClassDB::bind_method(D_METHOD("reset"), &AlternisDialogue::reset);
    ClassDB::bind_method(D_METHOD("reply", "replyId"), &AlternisDialogue::reply);
    ClassDB::bind_method(D_METHOD("step"), &AlternisDialogue::step);

    ClassDB::bind_method(D_METHOD("set_variable_string"), &AlternisDialogue::set_variable_string);
    ClassDB::bind_method(D_METHOD("set_variable_boolean"), &AlternisDialogue::set_variable_boolean);
    ClassDB::bind_method(D_METHOD("set_callback"), &AlternisDialogue::set_callback);
}

AlternisDialogue::AlternisDialogue()
    : ade_ctx(nullptr)
    , resource_path("")
    , random_seed(0)
    , interpolate(true)
{
    ade_set_alloc(
        (void*(*)(size_t)) ::godot::Memory::alloc_static,
        (void(*)(void*)) ::godot::Memory::free_static
    );
}

AlternisDialogue::~AlternisDialogue() {
    if (this->ade_ctx != nullptr) ade_dialogue_ctx_destroy(ade_ctx);

    auto* cb_info = this->first_callback;
    while (cb_info != nullptr) {
        auto* next = cb_info->next;
        memdelete(cb_info);
        cb_info = next;
    }
}

static void _dispatch_callback(void* in_cb_info) {
    CRASH_COND(in_cb_info == nullptr);
    auto& cb_info = *static_cast<alternis::AlternisDialogue::CallbackInfo*>(in_cb_info);
    cb_info.callable.callv(Array());
}

void AlternisDialogue::_ready() {
    // FIXME: check, is this like reference count destroyed?
    auto json_bytes = godot::FileAccess::get_file_as_bytes(this->resource_path);

    random_seed = this->random_seed == 0 ? random() : this->random_seed;

    const char* errPtr = nullptr;

    this->ade_ctx = ade_dialogue_ctx_create_json(
        reinterpret_cast<const char*>(json_bytes.ptr()),
        json_bytes.size(),
        random_seed,
        !this->interpolate,
        &errPtr
    );

    if (errPtr != nullptr) {
        // FIXME: need to free the error
        fprintf(stderr, "alternis: init error '%s'", resource_path.utf8().get_data());
    }

    if (this->ade_ctx == nullptr) {
        fprintf(stderr, "alternis: got invalid context");
        return;
    }

    ade_dialogue_ctx_set_all_callbacks(this->ade_ctx, [](SetAllCallbacksPayload* payload){
        auto* _this = static_cast<AlternisDialogue*>(payload->inner_payload);
       _this->emit_signal("function_called", _this, godot::String::utf8(payload->name.ptr, payload->name.len));
    }, this);
}

static Dictionary stepResultToDict(StepResult stepResult) {
    Dictionary result;
    if (stepResult.tag == STEP_RESULT_DONE) {
        result["done"] = true;

    } else if (stepResult.tag == STEP_RESULT_OPTIONS) {
        Dictionary subdict;
        result["options"] = subdict;
        Array texts, ids;
        subdict["texts"] = texts;
        subdict["ids"] = ids;

        for (int i = 0; i < stepResult.options.texts.len; ++i) {
            const auto& line = stepResult.options.texts.ptr[i];

            Dictionary textDict;
            textDict["speaker"] = String::utf8(line.speaker.ptr, line.speaker.len);
            textDict["text"] = String::utf8(line.text.ptr, line.text.len);
            if (line.metadata.ptr != nullptr)
                textDict["metadata"] = String::utf8(line.metadata.ptr, line.metadata.len);

            const auto& id = stepResult.options.ids.ptr[i];

            texts.append(textDict);
            ids.append(id);
        }

    } else if (stepResult.tag == STEP_RESULT_LINE) {
        Dictionary subdict;
        const auto& line = stepResult.line;
        subdict["speaker"] = String::utf8(line.speaker.ptr, line.speaker.len);
        subdict["text"] = String::utf8(line.text.ptr, line.text.len);
        if (line.metadata.ptr != nullptr)
            subdict["metadata"] = String::utf8(line.metadata.ptr, line.metadata.len);

        result["line"] = subdict;

    } else if (stepResult.tag == STEP_RESULT_FUNCTION_CALLED) {
        result["function_called"] = true;

    } else {
        // FIXME: not win32 capable
        fprintf(stderr, "alternis: unreachable, invalid step result tag");
        abort();
    }

    return result;
}

Dictionary AlternisDialogue::step() {
    Dictionary result;

    if (this->ade_ctx == nullptr) {
        // FIXME: how to handle error? Print? ~~abort~~? emit_signal?
        // LOG_ERROR("dialogue context not set before calling step ()");
        return result;
    }

    StepResult nativeResult;
    ade_dialogue_ctx_step(this->ade_ctx, &nativeResult);

    result = stepResultToDict(nativeResult);

    emit_signal("dialogue_stepped", this, result);
    return result;
}

void AlternisDialogue::reset() {
    if (this->ade_ctx == nullptr) return;
    ade_dialogue_ctx_reset(this->ade_ctx);
}

void AlternisDialogue::reply(size_t replyId) {
    if (this->ade_ctx == nullptr) return;
    ade_dialogue_ctx_reply(this->ade_ctx, replyId);
}

// FIXME: can this be made void?
void AlternisDialogue::set_resource_path(const String value) { this->resource_path = value; }
String AlternisDialogue::get_resource_path() { return this->resource_path; }

void AlternisDialogue::set_random_seed(const uint64_t value) { this->random_seed = value; }
uint64_t AlternisDialogue::get_random_seed() { return this->random_seed; }

void AlternisDialogue::set_interpolate(const bool value) { this->interpolate = value; }
bool AlternisDialogue::get_interpolate() { return this->interpolate; }

void AlternisDialogue::set_variable_string(const godot::StringName name, const godot::String value) {
    const String name_data{name};
    ade_dialogue_ctx_set_variable_string(
        // NOTE: seemingly godot includes the null byte in the size
        this->ade_ctx, name_data.utf8().get_data(), name_data.utf8().size() - 1,
        value.utf8().get_data(), value.utf8().size() - 1
    );
}

void AlternisDialogue::set_variable_boolean(const godot::StringName name, const bool value) {
    const String name_data{name};
    ade_dialogue_ctx_set_variable_boolean(
        // NOTE: seemingly godot includes the null byte in the size
        this->ade_ctx, name_data.utf8().get_data(), name_data.utf8().size() - 1,
        value
    );
}

void AlternisDialogue::set_callback(const godot::StringName name, godot::Callable callable) {
    if (this->ade_ctx == nullptr) return;

    auto cb_info = memnew(CallbackInfo);
    *cb_info = CallbackInfo{
        .owner = this,
        .name = name,
        .callable = callable,
    };

    if (this->last_callback != nullptr)
        this->last_callback->next = cb_info;
    else
        this->first_callback = cb_info;

    // FIXME: isn't this string temporary? doesn't that violate the ade_dialogue_ctx_set_callback API?
    const String name_data{name};
    ade_dialogue_ctx_set_callback(
        // NOTE: seemingly godot includes the null byte in the size
        this->ade_ctx, name_data.utf8().get_data(), name_data.utf8().size() - 1, _dispatch_callback, cb_info
    );
}

} // namespace alternis
