#include "AlternisDialogue.h"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>

#ifdef __linux
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#endif
#ifdef WIN32
#endif

using namespace godot;

void AlternisDialogue::_bind_methods() {
    ClassDB::bind_method(D_METHOD("reset"), &AlternisDialogue::reset);
    ClassDB::bind_method(D_METHOD("reply", "replyId"), &AlternisDialogue::reply);
    ClassDB::bind_method(D_METHOD("step"), &AlternisDialogue::step);

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
                          PropertyInfo(Variant::STRING, "text")));
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
}

void AlternisDialogue::_ready() {
    const auto& ProjectSettings = *godot::ProjectSettings::get_singleton();
    const auto& OS = *godot::OS::get_singleton();

    const auto in_exported = !OS.has_feature("editor");
    const String local_path
        = in_exported
        ? OS.get_executable_path().get_base_dir()
            .path_join(this->get_resource_path().substr(sizeof("res://")))
        : ProjectSettings.globalize_path(this->get_resource_path());
    ;

#ifdef __linux
    const int fd = open(local_path.utf8().get_data(), O_RDONLY);
    if (fd == -1) {
        printf("alternis: no such file: '%s'", local_path.utf8().get_data());
        return;
    }
    struct stat file_stat;
    if (fstat(fd, &file_stat) == -1) {
        printf("alternis: file stat on '%s' failed", local_path.utf8().get_data());
        return;
    }
    const size_t file_len = file_stat.st_size;
    char* file_ptr = static_cast<char*>(mmap(NULL, file_len, PROT_READ, MAP_PRIVATE, fd, 0));
    if (file_ptr == MAP_FAILED) {
        printf("alternis: file stat on '%s' failed", local_path.utf8().get_data());
        return;
    }
#endif
#ifdef WIN32
    not_implemented;
#endif

    random_seed = this->random_seed == 0 ? random() : this->random_seed;

    const char* errPtr = nullptr;

    this->ade_ctx = ade_dialogue_ctx_create_json(
            file_ptr,
            file_len,
            random_seed,
            !this->interpolate,
            &errPtr
        );

    if (errPtr != nullptr) {
        // FIXME: need to free the error
        printf("alternis: init error '%s'", local_path.utf8().get_data());
    }

#ifdef __linux
    if (munmap(file_ptr, file_len) == -1) {
        // NOTE: not checking errno because should switch this all to zig
        printf("alternis: munmap of '%s' failed", local_path.utf8().get_data());
        return;
    }
    if (close(fd) == -1) {
        printf("alternis: closing '%s' failed", local_path.utf8().get_data());
        return;
    }
#endif
#ifdef WIN32
    not_implemented;
#endif
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

    } else if (stepResult.tag == STEP_RESULT_DONE) {
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
    StepResult nativeResult;
    if (this->ade_ctx == nullptr) {
        // FIXME: how to handle error? Print? ~~abort~~? emit_signal?
        // LOG_ERROR("dialogue context not set before calling step ()");
        return result;
    }
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
