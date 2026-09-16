import Foundation

/// Parameter-independent storage contract. No shipped parameter definitions or
/// legacy-preset mapping are implied by this envelope. Payload bytes are opaque
/// so newer recipes survive an older client's load/save cycle unchanged.
struct PersonalEffectRecipe: Codable, Equatable {
    struct Scope: Codable, Hashable {
        let storyID: UUID
        let clipID: String
        let authorID: String
    }

    let scope: Scope
    let schemaVersion: Int
    let rendererID: String
    let payload: Data

    enum ValidationError: Error, Equatable {
        case invalidScope
        case notOwner
        case unsupportedRecipe
    }

    /// Authorization is deliberately explicit; nil/empty authors are not the
    /// current user. This is a local editing guard, not server authorization.
    func validateEditor(_ currentAuthorID: String?) throws {
        guard !scope.clipID.isEmpty, !scope.authorID.isEmpty else {
            throw ValidationError.invalidScope
        }
        guard currentAuthorID == scope.authorID else {
            throw ValidationError.notOwner
        }
    }
}

/// A staged, non-destructive effect selection for a single source revision.
/// Both preview and export can consume the same validated recipe. No source
/// files are written, and no default renderer or preset fallback is selected.
struct PersonalEffectSelection: Equatable {
    let scope: PersonalEffectRecipe.Scope
    let sourceURL: URL
    private(set) var recipe: PersonalEffectRecipe?

    init(scope: PersonalEffectRecipe.Scope, sourceURL: URL) {
        self.scope = scope
        self.sourceURL = sourceURL
    }

    mutating func set(_ candidate: PersonalEffectRecipe, currentAuthorID: String?) throws {
        try candidate.validateEditor(currentAuthorID)
        guard candidate.scope == scope else {
            throw PersonalEffectRecipe.ValidationError.invalidScope
        }
        recipe = candidate
    }

    mutating func reset(currentAuthorID: String?) throws {
        guard !scope.clipID.isEmpty, !scope.authorID.isEmpty else {
            throw PersonalEffectRecipe.ValidationError.invalidScope
        }
        guard currentAuthorID == scope.authorID else {
            throw PersonalEffectRecipe.ValidationError.notOwner
        }
        recipe = nil
    }

    /// Callers must explicitly register an approved schema/renderer pair. An
    /// unsupported recipe remains stored; failure must not silently export raw
    /// footage while showing an effect in preview.
    func renderRecipe(supports: (Int, String) -> Bool) throws -> PersonalEffectRecipe? {
        guard let recipe else { return nil }
        guard supports(recipe.schemaVersion, recipe.rendererID) else {
            throw PersonalEffectRecipe.ValidationError.unsupportedRecipe
        }
        return recipe
    }
}
