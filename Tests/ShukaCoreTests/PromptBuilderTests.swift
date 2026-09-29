import Testing
@testable import ShukaCore

@Suite struct PromptBuilderTests {
    let email = StyleCategory.defaults.first { $0.id == "email" }!
    let dictionary = [
        DictionaryEntry(term: "Supabase", aliases: ["super base"]),
        DictionaryEntry(term: "kubectl"),
        DictionaryEntry(term: "  "),
    ]

    @Test func dictationPromptContainsStyleContextAndVocabulary() {
        let prompt = PromptBuilder.dictation(
            transcript: "hello",
            category: email,
            dictionary: dictionary,
            context: AppContext(appName: "Google Chrome", host: "mail.google.com")
        )
        #expect(prompt.system.contains(StylePreset.formal.rule))
        #expect(prompt.system.contains(email.customInstructions))
        #expect(prompt.system.contains("mail.google.com in Google Chrome"))
        #expect(prompt.system.contains("- Supabase (may be transcribed as: super base)"))
        #expect(prompt.system.contains("- kubectl"))
        #expect(prompt.system.contains("NEVER translate"))
        #expect(prompt.user == "<transcript>\nhello\n</transcript>")
    }

    @Test func emptyOptionalSectionsAreOmitted() {
        let other = StyleCategory.defaults.first { $0.isFallback }!
        let prompt = PromptBuilder.dictation(transcript: "x", category: other, dictionary: [], context: AppContext())
        #expect(!prompt.system.contains("Additional instructions"))
        #expect(!prompt.system.contains("<sample>"))
        #expect(!prompt.system.contains("Always spell"))
    }

    @Test func vocabularyIsDeduplicatedAndTrimmed() {
        let entries = dictionary + [DictionaryEntry(term: "supabase")]
        #expect(PromptBuilder.vocabulary(entries) == ["Supabase", "kubectl"])
    }

    @Test func transformIncludesInstructionsAndSamples() {
        let transform = Transform(slot: 5, name: "Pirate", instructions: "Talk like a pirate.", samples: ["Arr!", " "])
        let prompt = PromptBuilder.transform(transform, text: "hello", dictionary: [])
        #expect(prompt.system.contains("Talk like a pirate."))
        #expect(prompt.system.contains("<example>\nArr!\n</example>"))
        #expect(!prompt.system.contains("<example>\n\n</example>"))
        #expect(prompt.user == "<text>\nhello\n</text>")
    }

    @Test func voiceTransformWithAndWithoutSelection() {
        let edit = PromptBuilder.voiceTransform(instruction: "shorter", selection: "long text", dictionary: [])
        #expect(edit.user.contains("<text>\nlong text\n</text>"))
        #expect(edit.user.contains("<instruction>\nshorter\n</instruction>"))

        let write = PromptBuilder.voiceTransform(instruction: "write a haiku", selection: nil, dictionary: [])
        #expect(!write.user.contains("<text>"))
        #expect(write.system.contains("You write text"))
    }
}
