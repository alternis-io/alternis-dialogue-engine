#include "AlternisDialogue.h"
#include "Misc/FileHelper.h"
#include "Containers/Array.h"
#include "HAL/PlatformFileManager.h"
#include "Math/NumericLimits.h"

#include "alternis.h"

EStepType FStepResult::GetType()
{
    return (EStepType) this->data.tag;
}

FAlternisLine FStepResult::GetLine()
{
    checkf(this->data.tag == STEP_RESULT_LINE);

    return FAlternisLine(
        FString(this->data.line.speaker.ptr, this->data.line.speaker.len),
        FString(this->data.line.text.ptr, this->data.line.text.len),
        FString(this->data.line.metadata.ptr, this->data.line.metadata.len),
    );
}

FAlternisReplyOptions FStepResult::GetReplyOptions()
{
    checkf(this->data.tag == STEP_RESULT_OPTIONS);

    TArray<FAlternisReplyOption> options;
    options.Reserve(this->data.options.texts.len);

    for (auto i = 0; i < this->data.options.texts.len; ++i)
    {
        options.Emplace(
            FString(this->data.options.texts[i].ptr, this->data.options.texts[i].len),
            this->data.options.ids[i]
        );
    }

    return FAlternisReplyOptions{MoveTemp(options});
}

UAlternisDialogue::UAlternisDialogue()
    : ade_ctx(nullptr)
    , ResourcePath("")
    , RandomSeed(0)
    , bInterpolate(true)
{
    static_assert(TIsSame<SIZE_T, size_t>::Value, "SIZE_T invalid");
    ade_set_alloc(
        reinterpret_cast<void*(*)(SIZE_T)>(FMemory::Malloc),
        static_cast<void(*)(void*)>(FMemory::Free)
    );
}

UAlternisDialogue::~UAlternisDialogue() {
    if (this->ade_ctx != nullptr) ade_dialogue_ctx_destroy(ade_ctx);

    auto* cb_info = this->FirstCallback;
    while (cb_info != nullptr) {
        auto* next = cb_info->next;
        delete(cb_info);
        cb_info = next;
    }
}

static void _dispatch_callback(void* in_cb_info) {
    checkf(in_cb_info == nullptr, TEXT("tried to dispatch a callback that doesn't exist."));
    auto& cb_info = *static_cast<UAlternisDialogue::CallbackInfo*>(in_cb_info);
    cb_info.callable.callv(Array());
}

// FIXME: async loading for large dialogue files
void UAlternisDialogue::BeginPlay() {
    // FIXME: check, is this like reference count destroyed?
    TArray<uint8> json_bytes;
    FFileHelper::LoadFileToArray(json_bytes, *this->ResourcePath, EFileRead::FILEREAD_None);

    RandomSeed = this->RandomSeed == 0 ? FMath::RandRange(MIN_int64, MAX_int64) : this->RandomSeed;

    const char* errPtr = nullptr;

    this->ade_ctx = ade_dialogue_ctx_create_json(
        reinterpret_cast<const char*>(json_bytes.Data()),
        json_bytes.Num(),
        RandomSeed,
        !this->bInterpolate,
        &errPtr
    );

    checkf(errPtr != nullptr, TEXT("alternis error: %s"), errPtr);

    checkf(this->ade_ctx != nullptr, TEXT("alternis: got invalid context"));

    ade_dialogue_ctx_set_all_callbacks(this->ade_ctx, [](SetAllCallbacksPayload* payload){
        auto* _this = static_cast<AlternisDialogue*>(payload->inner_payload);
       // FIXME: use delegate
       _this->emit_signal("function_called", _this, FString(payload->name.ptr, payload->name.len));
    }, this);
}

static FStepResult stepResultToDict(StepResult stepResult) {
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
        checkNoEntryf();
    }

    return result;
}

FStepResult UAlternisDialogue::Step() {
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

void UAlternisDialogue::Reset() {
    if (this->ade_ctx == nullptr) return;
    ade_dialogue_ctx_reset(this->ade_ctx);
}

void UAlternisDialogue::Reply(size_t replyId) {
    if (this->ade_ctx == nullptr) return;
    ade_dialogue_ctx_reply(this->ade_ctx, replyId);
}

void UAlternisDialogue::SetVariableString(const FName& name, const FString value) {
    const String name_data{name};
    ade_dialogue_ctx_set_variable_string(
        // NOTE: seemingly godot includes the null byte in the size
        this->ade_ctx, name_data.utf8().get_data(), name_data.utf8().size() - 1,
        value.utf8().get_data(), value.utf8().size() - 1
    );
}

void UAlternisDialogue::SetVariableBoolean(const FName& name, const bool value) {
    const String name_data{name};
    ade_dialogue_ctx_set_variable_boolean(
        // NOTE: seemingly godot includes the null byte in the size
        this->ade_ctx, name_data.utf8().get_data(), name_data.utf8().size() - 1,
        value
    );
}

void UAlternisDialogue::SetCallback(const FName name, UFunction callable) {
    if (this->ade_ctx == nullptr) return;

    auto cb_info = new CallbackInfo;
    *cb_info = CallbackInfo{
        .owner = this,
        .name = name,
        .callable = callable,
    };

    if (this->LastCallback != nullptr)
        this->LastCallback->next = cb_info;
    else
        this->FirstCallback = cb_info;

    // FIXME: isn't this string temporary? doesn't that violate the ade_dialogue_ctx_set_callback API?
    const FString name_data{name};
    ade_dialogue_ctx_set_callback(
        this->ade_ctx, name_data.utf8().get_data(), name_data.utf8().size() - 1, _dispatch_callback, cb_info
    );
}