//
//  SmartLibrarySearchService.swift
//  brWave
//
//  Translates natural language input into a strict Database Query against the patch library.
//  Uses Apple Intelligence to extract explicit parameters (include/exclude categories,
//  hardware descriptors) and timbral/affective descriptors.
//

import Foundation
import Combine
import CoreData
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Smart Query Descriptors

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct SmartLibraryQuery {
    @Guide(description: "Categories the user explicitly wants. Examples: LEAD, PAD, BASS, BRASS, ORGAN, STRINGS, ARP, FX, KEYS, PERC, CHORD, OTHER. Leave empty if no specific category is mentioned.")
    var includeCategories: [String]
    
    @Guide(description: "Categories the user explicitly does NOT want. Example: ['BASS'] if they say 'not bass'. Leave empty if none.")
    var excludeCategories: [String]
    
    @Guide(description: "Hardware parameter constraints mentioned in the prompt. Examples: 'fast attack', 'wavetable 15', 'digital waveform', 'long release'. Leave empty if none.")
    var semanticParameters: [String]
    
    @Guide(description: "Timbral vibe, mood, and motion words to use for similarity sorting. Examples: warm, pulsing, dark, bright, drone, organic.")
    var timbralKeywords: [String]
}
#endif

// MARK: - Query result

struct SmartSearchResult {
    let patches: [Patch]
    let extractedDescription: String
    let usedAppleIntelligence: Bool
}

// MARK: - Service

@MainActor
final class SmartLibrarySearchService: ObservableObject {

    @Published var isProcessing = false
    @Published var lastResult: SmartSearchResult?
    @Published var errorMessage: String?

    // MARK: - Search

    func search(input: String, in context: NSManagedObjectContext, within bank: PatchSet? = nil) async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastResult = nil
            return
        }

        isProcessing = true
        errorMessage = nil

        do {
            if #available(macOS 26.0, *) {
                print("[SmartSearch] AI availability: \(SystemLanguageModel.default.availability)")
                lastResult = try await searchWithAppleIntelligence(input: input, in: context, bank: bank)
            } else {
                lastResult = searchWithKeywords(input: input, in: context, bank: bank)
            }
        } catch {
            print("[SmartSearch] AI error: \(error)")
            lastResult = searchWithKeywords(input: input, in: context, bank: bank)
        }

        isProcessing = false
    }

    // MARK: - Apple Intelligence path

    @available(macOS 26.0, *)
    private static let aiSession = LanguageModelSession(
        instructions: "You are a synthesizer librarian system. Extract rigid filtering rules (categories to include/exclude) and abstract sonic qualities from the user's input."
    )

    @available(macOS 26.0, *)
    private func searchWithAppleIntelligence(input: String, in context: NSManagedObjectContext, bank: PatchSet?) async throws -> SmartSearchResult {
        guard case .available = SystemLanguageModel.default.availability else {
            return searchWithKeywords(input: input, in: context, bank: bank)
        }
        let session = Self.aiSession

        let prompt = "Parse this library search query: \"\(input)\""

        let response = try await session.respond(to: prompt, generating: SmartLibraryQuery.self)
        let query = response.content

        let description = buildDescription(from: query)
        let patches = findPatches(for: query, in: context, bank: bank)

        return SmartSearchResult(
            patches: patches,
            extractedDescription: description,
            usedAppleIntelligence: true
        )
    }

    // MARK: - Keyword fallback

    private func searchWithKeywords(input: String, in context: NSManagedObjectContext, bank: PatchSet?) -> SmartSearchResult {
        let words = input.lowercased()
            .components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { $0.count > 2 }

        let allPatches = fetchAllPatches(in: context, bank: bank)

        // Simple word overlap scoring
        let scored: [(Patch, Int)] = allPatches.map { patch in
            let name     = (patch.name ?? "").lowercased()
            let category = (patch.category ?? "").lowercased()
            var score = 0
            for word in words {
                if name.contains(word)     { score += 2 }
                if category.contains(word) { score += 1 }
            }
            return (patch, score)
        }

        let results = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)

        return SmartSearchResult(
            patches: Array(results.prefix(50)),
            extractedDescription: "Keyword match: \(words.prefix(4).joined(separator: ", "))",
            usedAppleIntelligence: false
        )
    }

    // MARK: - Patch matching from AI Descriptors

    @available(macOS 26.0, *)
    private func findPatches(for query: SmartLibraryQuery, in context: NSManagedObjectContext, bank: PatchSet?) -> [Patch] {
        let allPatches = fetchAllPatches(in: context, bank: bank)
        guard !allPatches.isEmpty else { return [] }

        let includes = query.includeCategories.map { $0.uppercased() }
        let excludes = query.excludeCategories.map { $0.uppercased() }
        let vibeWords = query.timbralKeywords.map { $0.lowercased() }
        let paramKeywords = query.semanticParameters.map { $0.lowercased() }

        // Start by strictly filtering out exclusions
        var candidatePatches = allPatches
        if !excludes.isEmpty {
            candidatePatches = candidatePatches.filter { patch in
                let category = (patch.category ?? "").uppercased()
                return !excludes.contains(where: { category.contains($0) })
            }
        }

        // Score the remaining patches
        var scored: [(Patch, Double)] = candidatePatches.map { patch in
            var score: Double = 0
            let category = (patch.category ?? "").uppercased()
            let name = (patch.name ?? "").lowercased()

            // Strict Include Matches
            if !includes.isEmpty {
                if includes.contains(where: { category.contains($0) }) {
                    score += 10.0 // Massive bonus for hitting explicitly requested category
                } else {
                    // Small penalty if it doesn't match the requested categories
                    score -= 5.0
                }
            }

            // Semantic Parameter / Vibe Keyword Hits
            for word in vibeWords + paramKeywords {
                if name.contains(word) {
                    score += 2.0
                }
            }

            return (patch, score)
        }

        // Drop anything with a negative score (failed strict inclusion check)
        scored = scored.filter { $0.1 >= 0 }

        // Add similarity bonus using the SimilarityEngine (if available, e.g., for vibes)
        if !vibeWords.isEmpty {
            // Find centroid of the best matches, and boost similar patches
            let topTier = scored.filter { $0.1 > 0 }.map(\.0)
            if !topTier.isEmpty {
                let vectors = topTier.map { SimilarityEngine.patchToVector($0.values) }
                let dim = vectors.first?.count ?? 0
                if dim > 0 {
                    var centroid = [Double](repeating: 0, count: dim)
                    for v in vectors {
                        for i in 0..<min(v.count, dim) { centroid[i] += v[i] }
                    }
                    let n = Double(vectors.count)
                    centroid = centroid.map { $0 / n }

                    scored = scored.map { (patch, score) in
                        let v = SimilarityEngine.patchToVector(patch.values)
                        let dist = SimilarityEngine.euclideanDistance(v1: v, v2: centroid)
                        let bonus = max(0, 1.0 - (dist / 500.0)) // normalize
                        return (patch, score + bonus * 3.0)
                    }
                }
            }
        }

        // Sort descending
        let sortedPositive = scored.sorted { $0.1 > $1.1 }.map(\.0)

        // Return up to 64 items (a standard bank size)
        return Array(sortedPositive.prefix(64))
    }

    private func fetchAllPatches(in context: NSManagedObjectContext, bank: PatchSet?) -> [Patch] {
        let request: NSFetchRequest<Patch> = Patch.fetchRequest()
        if let bank = bank {
            // Limit to a specific patch set if provided
            request.predicate = NSPredicate(format: "ANY slots.patchSet == %@", bank)
        }
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Description builder

    @available(macOS 26.0, *)
    private func buildDescription(from q: SmartLibraryQuery) -> String {
        var parts: [String] = []
        if !q.includeCategories.isEmpty { parts.append("Include: \(q.includeCategories.joined(separator: ", "))") }
        if !q.excludeCategories.isEmpty { parts.append("Exclude: \(q.excludeCategories.joined(separator: ", "))") }
        if !q.semanticParameters.isEmpty { parts.append("Rules: \(q.semanticParameters.joined(separator: ", "))") }
        if !q.timbralKeywords.isEmpty { parts.append("Vibe: \(q.timbralKeywords.joined(separator: ", "))") }
        return parts.isEmpty ? "All patches" : parts.joined(separator: " · ")
    }

    // MARK: - Clear

    func clear() {
        lastResult   = nil
        errorMessage = nil
    }
}
