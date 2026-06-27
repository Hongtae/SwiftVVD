import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EntryMacro.self,
        EntryDefaultValueMacro.self,
        AnimatableValuesMacro.self,
        AnimatableIgnoredMacro.self,
        AnimatableValuesDataPropertyMacro.self,
        AnimatableValuesDataMacro.self,
        AnimatablePairDataMacro.self,
        AnimatablePropertyMacro.self,
        InvalidAnimatablePropertyMacro.self,
    ]
}
