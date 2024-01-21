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

void UAlternisDialogue::Reply(int64 replyId) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;
    ade_dialogue_ctx_reply(this->ade_ctx, replyId);
}

static void GetAnsiBuffFromFName(FName name, const ANSICHAR** outBuff, int32* outLen)
{
    const auto entry = FName::GetEntry(*name.ToEName());

    // extremely questionable hack to access private instance variables of FNameEntry ;)
    // checked on Unreal engine 5.0.1, this must be more strongly checked
    struct FNameEntryHacked
    {
        #if WITH_CASE_PRESERVING_NAME
            FNameEntryId ComparisonId;
        #endif
            FNameEntryHeader Header;
            union
            {
                ANSICHAR	AnsiName[NAME_SIZE];
                WIDECHAR	WideName[NAME_SIZE];
            };
    };

    *outBuff = &reinterpret_cast<const FNameEntryHacked&>(entry).AnsiName[0];
    *outLen = entry->GetNameLength();
}

void UAlternisDialogue::SetVariableString(const FName& name, const FString& value) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;

    const ANSICHAR* namePtr;
    int32 nameLen;
    GetAnsiBuffFromFName(name, &namePtr, &nameLen);

    // HACK: need to check FName garbage collection policy... I assume no gc per process atm unwisely
    this->StringVars.Add(name, value);

    ade_dialogue_ctx_set_variable_string(this->ade_ctx, namePtr, nameLen, *value, value.Len());
}

void UAlternisDialogue::SetVariableBoolean(const FName& name, const bool value) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;

    const ANSICHAR* namePtr;
    int32 nameLen;
    GetAnsiBuffFromFName(name, &namePtr, &nameLen);

    this->BooleanVars.Add(name, value);

    ade_dialogue_ctx_set_variable_boolean(this->ade_ctx, namePtr, nameLen, value);
}

void UAlternisDialogue::SetCallback(const FName& name, UAlternisCallback* callable) {
    if (!ensureMsgf(this->ade_ctx != nullptr, TEXT("invalid alternis context")))
        return;

    const ANSICHAR* namePtr;
    int32 nameLen;
    GetAnsiBuffFromFName(name, &namePtr, &nameLen);

    this->Callbacks.Add(name, callable);

    ade_dialogue_ctx_set_callback(this->ade_ctx, namePtr, nameLen, _dispatch_callback, callable);
}