import Foundation

// MARK: - Dog Canned Responses
//
// Client-side canned responses for dog sprites. Dogs never round-trip to the
// relay — when the user sends them a message, we synthesize a reply from a
// shared pool plus a character-specific pool.
//
// Future: Steve/Esteban and Elvis/Senor become outfit variants of the same
// dog (wardrobe system). Until then, they share per-character pools.
enum DogCannedResponses {

    /// Pool shared across every dog.
    static let shared: [String] = [
        "*tail wagging intensifies*",
        "*tilts head*",
        "woof.",
        "*rolls over for belly rubs*",
        "*stares at you, then at the treat jar*",
        "bork bork bork",
    ]

    /// Per-character pools — sampled alongside `shared` to add personality.
    /// Dachshunds (elvis/senor), cattle dogs (steve/esteban), schnauzers
    /// (kai/hoku), robot (zuckerbot).
    static let perCharacter: [CharacterType: [String]] = [
        // Cattle dogs
        .steve: cattleDogPool,
        .esteban: cattleDogPool,
        // Dachshunds
        .elvis: dachshundPool,
        .senor: dachshundPool,
        // Schnauzers
        .kai: schnauzerPool,
        .hoku: schnauzerPool,
        // Robot dog
        .zuckerbot: zuckerbotPool,
    ]

    /// Pick a random canned response for the given dog.
    /// Weighted 50/50 between the character-specific pool and the shared pool
    /// (falls back to shared if the character has no dedicated pool).
    static func randomResponse(for character: CharacterType) -> String {
        precondition(character.isDog, "DogCannedResponses only valid for dog characters")

        let specific = perCharacter[character] ?? []
        // 50% chance of character-specific if we have any; otherwise always shared.
        if !specific.isEmpty, Bool.random() {
            return specific.randomElement() ?? shared.randomElement() ?? "woof."
        }
        return shared.randomElement() ?? "woof."
    }

    // MARK: - Per-character pools

    private static let cattleDogPool: [String] = [
        "hello mama",
        "I'm a tiny dancer!",
        "Does mama need foot massage",
        "me happy!",
        "me looking for butt to sniff",
    ]

    private static let dachshundPool: [String] = [
        "I'm hungry, where's my eggs?!",
        "Hi mama",
        "Keep my brother out of my butt!",
        "I'm hungry, where's Steve's food?!",
        "I'm making biscuits over here",
        "Bury me in blanket please",
    ]

    private static let schnauzerPool: [String] = [
        "Death to mailmen!",
        "I love my mom and dad!",
        "Where's dad?!",
        "Is it greenie time yet?",
    ]

    private static let zuckerbotPool: [String] = [
        "bleet bleet bleet",
        "the metaverse is the future",
        "do you like ju jitsu?",
        "me hungry for money",
    ]
}
