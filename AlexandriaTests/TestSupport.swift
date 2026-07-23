import Foundation
@testable import Alexandria

/// Builds a PodcastEpisode from an inline JSON fixture — the same decode path
/// production uses — so tests don't depend on the wide memberwise initializer.
func makeEpisode(
    id: String,
    libraryItemId: String? = nil,
    title: String? = nil,
    publishedAt: Int? = nil,
    addedAt: Int? = nil,
    duration: Double? = nil
) throws -> PodcastEpisode {
    var fields = ["\"id\": \"\(id)\""]
    if let libraryItemId { fields.append("\"libraryItemId\": \"\(libraryItemId)\"") }
    if let title { fields.append("\"title\": \"\(title)\"") }
    if let publishedAt { fields.append("\"publishedAt\": \(publishedAt)") }
    if let addedAt { fields.append("\"addedAt\": \(addedAt)") }
    if let duration { fields.append("\"duration\": \(duration)") }
    let json = "{ \(fields.joined(separator: ", ")) }"
    return try JSONDecoder().decode(PodcastEpisode.self, from: Data(json.utf8))
}
