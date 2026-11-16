import Foundation

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

    func validateEditor(_ currentAuthorID: String?) throws {
        guard !scope.clipID.isEmpty, !scope.authorID.isEmpty else {
            throw ValidationError.invalidScope
        }
        guard currentAuthorID == scope.authorID else {
            throw ValidationError.notOwner
        }
    }
}

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

    func renderRecipe(supports: (Int, String) -> Bool) throws -> PersonalEffectRecipe? {
        guard let recipe else { return nil }
        guard supports(recipe.schemaVersion, recipe.rendererID) else {
            throw PersonalEffectRecipe.ValidationError.unsupportedRecipe
        }
        return recipe
    }
}
