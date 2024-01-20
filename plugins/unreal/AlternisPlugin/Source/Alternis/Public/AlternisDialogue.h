#ifndef ALTERNIS_DIALOGUE_H
#define ALTERNIS_DIALOGUE_H

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Containers/Union.h"
#include "Containers/Array.h"
#include <stddef.h>
#include <stdint.h>
#include "alternis.h"

#include "AlternisDialogue.generated.h"

USTRUCT(BlueprintType)
struct FReply
{
    GENERATED_BODY()
    FString Text;
    size_t Id;
};

USTRUCT(BlueprintType)
struct FReplyOptions
{
    GENERATED_BODY()
    TArray<FReply> Options;
};

USTRUCT(BlueprintType)
struct FLine
{
    GENERATED_BODY()
    FString Speaker;
    FString Text;
    // FIXME: make an FJson object...
    FString Metadata;
};

UENUM(BlueprintType)
// FIXME: use TUnion
enum class EStepType : unsigned char
{
    None UMETA(DisplayName = ""),
    Reply UMETA(DisplayName = "")
};

using FStepResult = TUnion<void, FReplyOptions, FLine, void>;

UCLASS()
class ALTERNIS_API UAlternisDialogue : public USceneComponent
{
    GENERATED_BODY()

    DialogueContext* ade_ctx = nullptr;

public:

    struct CallbackInfo {
        UAlternisDialogue* owner;
        FName name;
        void(*callable)(void*);
        CallbackInfo* next = nullptr;
    };


    UPROPERTY(EditAnywhere, Category="Alternis|Dialogue")
    FString resource_path;

    // if 0, a random number will be used for the seed
    UPROPERTY(EditAnywhere, Category="Alternis|Dialogue")
    uint64_t random_seed = 0;

    UPROPERTY(EditAnywhere, Category="Alternis|Dialogue")
    bool interpolate = true;

    CallbackInfo* first_callback = nullptr;
    CallbackInfo* last_callback = nullptr;

protected:
    static void _bind_methods();

public:
    UAlternisDialogue();
    ~UAlternisDialogue();

    virtual void BeginPlay() override;

    void SetResourcePath(const FString& path);
    FString GetResourcePath();

    void set_random_seed(const uint64_t value);
    uint64_t get_random_seed();

    void set_interpolate(const bool value);
    bool get_interpolate();

    void Reset();
    FStepResult step();
    void Reply(size_t replyId);

    void SetVariableString(const FString&, const FString&);
    void SetVariableBoolean(const FString&, const bool);
    void SetCallback(const FString, UFunction);
};

#endif
