#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Components/ActorComponent.h"
#include "Containers/Union.h"
#include "Containers/Array.h"
#include "Containers/Map.h"
#include "alternis.h"
#include <stddef.h>

#include "AlternisDialogue.generated.h"

static_assert(sizeof(int64) == sizeof(size_t), "unexpected size_t size");

USTRUCT(BlueprintType)
struct FAlternisReplyOption
{
    GENERATED_BODY()

    FAlternisReplyOption(): Text(), Id() {}
    FAlternisReplyOption(const FString& Text, int64 Id): Text(Text), Id(Id) {}

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Alternis|Dialogue")
        FString Text;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Alternis|Dialogue")
        int64 Id;
};

// FIXME: the type names are rather inconsistent between plugins and lib. Should fix.
USTRUCT(BlueprintType)
struct FAlternisReplyOptions
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Alternis|Dialogue")
        TArray<FAlternisReplyOption> Options;
};

USTRUCT(BlueprintType)
struct FAlternisLine
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Alternis|Dialogue")
        FString Speaker;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Alternis|Dialogue")
        FString Text;

    // FIXME: make an FJson object...
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Alternis|Dialogue")
        FString Metadata;
};

// FIXME: do we need this when we have a union?
UENUM(BlueprintType)
enum class EStepType : uint8
{
    Done = STEP_RESULT_DONE UMETA(DisplayName = "Done"),
    Options = STEP_RESULT_OPTIONS UMETA(DisplayName = "Options"),
    Line = STEP_RESULT_LINE UMETA(DisplayName = "Line"),
    FunctionCalled = STEP_RESULT_FUNCTION_CALLED UMETA(DisplayName = "FunctionCalled")
};

// NOTE: blueprint accessible (worst case) size-inefficient union
// probably better than UObject inheriting function-based size efficient union
USTRUCT(BlueprintType)
struct FStepResult
{
    GENERATED_BODY()

    FStepResult(StepResult);

    UPROPERTY(BlueprintReadonly, Category="Alternis|Dialogue")
        EStepType Type;

    /** Check Type before usage to be sure this isn't empty */
    UPROPERTY(BlueprintReadonly, Category="Alternis|Dialogue")
        FAlternisLine Line;

    /** Check Type before usage to be sure this isn't empty */
    UPROPERTY(BlueprintReadonly, Category="Alternis|Dialogue")
        FAlternisReplyOptions ReplyOptions;

    FStepResult(): Type(), Line(), ReplyOptions() {}
};

class UAlternisDialogue;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FAlternisCallbackSignature, UAlternisDialogue*, DialogueContext);

// NOTE: structs can't contain delegates so this is a full blown object :|
UCLASS(BlueprintType)
class UAlternisCallback : public UObject
{
    GENERATED_BODY()
public:

    UPROPERTY()
        UAlternisDialogue* owner;

    //UPROPERTY(BlueprintReadonly, Category = "Alternis|Dialogue|Callback")
    //FName name;

    UPROPERTY(BlueprintAssignable, Category = "Alternis|Dialogue|Callback")
        FAlternisCallbackSignature Callback;

    //void Call(UAlternisDialogue*)
};

UCLASS(BlueprintType)
class ALTERNIS_API UAlternisDialogue : public UActorComponent
{
    GENERATED_BODY()

    DialogueContext* ade_ctx = nullptr;

    // FIXME: probably insidious bugs to do with pointer invalidation since
    // lib alternis is not id based yet
    TMap<FName, FString> StringVars;
    TMap<FName, bool> BooleanVars;
    TMap<FName, UAlternisCallback*> Callbacks;

public:

    UAlternisDialogue();
    ~UAlternisDialogue();
    virtual void BeginPlay() override;

    UPROPERTY(EditAnywhere, Category="Alternis|Dialogue")
        FString ResourcePath;

    // if 0, a random number will be used for the seed
    UPROPERTY(EditAnywhere, Category="Alternis|Dialogue")
        uint64 RandomSeed = 0;

    UPROPERTY(EditAnywhere, Category="Alternis|Dialogue")
        bool bInterpolate = true;

    UFUNCTION(BlueprintCallable)
        void Reset();

    UFUNCTION(BlueprintCallable)
        FStepResult Step();

    UFUNCTION(BlueprintCallable)
        void Reply(int64 replyId);

    //UFUNCTION(BlueprintPure)
        //FString GetVariableString(const FName& VariableName);
    UFUNCTION(BlueprintCallable)
        void SetVariableString(const FName& VariableName, const FString& VariableValue);

    UFUNCTION(BlueprintPure)
        bool GetVariableBoolean(const FName& VariableName);
    UFUNCTION(BlueprintCallable)
        void SetVariableBoolean(const FName& VariableName, const bool VariableValue);

    UFUNCTION(BlueprintCallable)
        void SetCallback(const FName& CallbackName, UAlternisCallback* Callback);
};