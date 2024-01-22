using UnrealBuildTool;
using System;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;

public class Alternis : ModuleRules
{
    public Alternis(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = ModuleRules.PCHUsageMode.UseExplicitOrSharedPCHs;
        CppStandard = CppStandardVersion.Cpp17;

        PublicIncludePaths.AddRange(new string[] { });

        PrivateIncludePaths.AddRange(new string[] { });

        PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine" });

        PrivateDependencyModuleNames.AddRange(new string[] { "CoreUObject", "Engine", "Slate", "SlateCore", "Json", "JsonUtilities" });
        if (Target.bBuildEditor)
        {
            PrivateDependencyModuleNames.AddRange(new string[] { "UnrealEd" });
        }

        DynamicallyLoadedModuleNames.AddRange(new string[] { });

        string AlternisPath = Path.GetFullPath(Path.Combine(ModuleDirectory, "../../../../../../../lib"));

        PublicIncludePaths.Add(Path.Combine(AlternisPath, "headers-gen"));

        string LibFileName
            = Target.Platform == UnrealTargetPlatform.Win64
            ? "alternis-x86_64-windows-msvc.lib"
            : Target.Platform == UnrealTargetPlatform.Mac && Target.Architecture.StartsWith("x86_64")
            ? "libalternis-x86_64-macos.a"
            : Target.Platform == UnrealTargetPlatform.Mac && Target.Architecture.StartsWith("arm64")
            ? "libalternis-aarch64-macos.a"
            : null;

        if (LibFileName == null)
        {
            throw new System.NotSupportedException($"An unsupported platform '{Target.Platform}' was specified");
        }

        PublicAdditionalLibraries.Add(Path.Combine(AlternisPath, "zig-out/lib", LibFileName));

        if (Target.Platform == UnrealTargetPlatform.Win64)
        {
            var win10KitBase = "C:/Program Files (x86)/Windows Kits/10/Lib";
            var win10KitVersions = new List<string>(Directory.EnumerateDirectories(win10KitBase));
            if (win10KitVersions.Count >= 1)
            {
                PublicAdditionalLibraries.Add(Path.Combine(win10KitBase, win10KitVersions[0], "um/x64/ntdll.lib"));
            }
            else
            {
                throw new System.NotSupportedException($"Only windows versions containing ntdll.lib are supported");
            }
        }
    }
}
