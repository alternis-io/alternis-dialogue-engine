#include "AlternisDialogue.h"
#include "Misc/FileHelper.h"
#include "Containers/Array.h"
#include "HAL/PlatformFileManager.h"
#include "Math/NumericLimits.h"
#include "Templates/UnrealTypeTraits.h"

#include "alternis.h"

FStepResult::FStepResult(StepResult nativeResult)
{
    this->Type = (EStepType) nativeResult.tag;

    if (nativeResult.tag == STEP_RESULT_LINE)
    {
        this->Line = FAlternisLine{
            FString(nativeResult.line.speaker.ptr, nativeResult.line.speaker.len),
            FString(nativeResult.line.text.ptr, nativeResult.line.text.len),
            FString(nativeResult.line.metadata.ptr, nativeResult.line.metadata.len)
        };
    }
    else if (nativeResult.tag == STEP_RESULT_OPTIONS)
    {
        TArray<FAlternisReplyOption> options;
        options.Reserve(nativeResult.options.texts.len);

        for (auto i = 0; i < nativeResult.options.texts.len; ++i)
        {
            options.Emplace(
                FString(nativeResult.options.texts.ptr[i].text.ptr, nativeResult.options.texts.ptr[i].text.len),
                nativeResult.options.ids.ptr[i]
            );
        }

        this->ReplyOptions = FAlternisReplyOptions{MoveTemp(options)};
    }
}

UAlternisDialogue::UAlternisDialogue()
    : ade_ctx(nullptr)
    // FIXME: no such thing as an empty TList?
    , StringVars({FName{}, FString{}}, nullptr)
    , BooleanVars({FName{}, false}, nullptr)
    // FIXME: need to make sure to replace these?
    , Callbacks({FName{}, nullptr}, nullptr)
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
    // FIXME: will TList deallocate our Callbacks?
}

static void _dispatch_callback(void* inCtx) {
    if (!ensureMsgf(inCtx != nullptr, TEXT("tried to dispatch a null callback")))
        return;
    auto& callback = *static_cast<UAlternisCallback*>(inCtx);
    callback.Callback.Broadcast(callback.owner);
}

// FIXME: async loading for large dialogue files
void UAlternisDialogue::BeginPlay() {
    // FIXME: check, is this like reference count destroyed?
    TArray<uint8> json_bytes;
    FFileHelper::LoadFileToArray(json_bytes, *this->ResourcePath, EFileRead::FILEREAD_None);

    RandomSeed = this->RandomSeed == 0 ? FMath::RandRange(MIN_int64, MAX_int64) : this->RandomSeed;

    const char* errPtr = nullptr;

    this->ade_ctx = ade_dialogue_ctx_create_json(
        reinterpret_cast<const char*>(json_bytes.GetData()),
        json_bytes.Num(),
        RandomSeed,
        !this->bInterpolate,
        &errPtr
    );

    if (!ensureMsgf(errPtr != nullptr, TEXT("alternis error: %s"), errPtr))
        return;

    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("alternis: got invalid context")))
        return;
}

FStepResult UAlternisDialogue::Step()
{
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("alternis: got invalid context")))
        return FStepResult{};

    StepResult nativeResult;
    ade_dialogue_ctx_step(this->ade_ctx, &nativeResult);

    return FStepResult(nativeResult);
}

void UAlternisDialogue::Reset() {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;
    ade_dialogue_ctx_reset(this->ade_ctx);
}

void UAlternisDialogue::Reply(size_t replyId) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;
    ade_dialogue_ctx_reply(this->ade_ctx, replyId);
}

void UAlternisDialogue::SetVariableString(const FName& name, const FString value) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;

    TCHAR name_buf;
    int32 name_len = name.ToString(name_buf);
    ade_dialogue_ctx_set_variable_string(
        // NOTE: seemingly godot includes the null byte in the size
        *this->ade_ctx, &name_buf, name_len,
        *value, value.GetLength(),
    );
}

void UAlternisDialogue::SetVariableBoolean(const FName& name, const bool value) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;

    ade_dialogue_ctx_set_variable_boolean(
        // NOTE: seemingly godot includes the null byte in the size
        this->ade_ctx, name_data.utf8().get_data(), name_data.utf8().size() - 1,
        value
    );
}

void UAlternisDialogue::SetCallback(const FName name, UFunction callable) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;

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