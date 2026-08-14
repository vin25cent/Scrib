import Foundation
import Testing

struct DemoAudioManifestTests {
    private struct Manifest: Decodable {
        var schemaVersion: Int
        var redistributionPolicy: String
        var sources: [Source]
    }

    private struct Source: Decodable {
        var id: String
        var language: String
        var teachingUnits: [String]
        var durationSeconds: Double
        var fileName: String
        var byteCount: Int
        var sha256: String
        var landingURL: URL
        var downloadURL: URL
        var author: String
        var license: String
        var licenseURL: URL
    }

    @Test func demoAudioManifestKeepsVerifiableLicensedSources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repositoryRoot
            .appendingPathComponent("Benchmarks/DemoAudio/sources.json")
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: manifestURL)
        )

        #expect(manifest.schemaVersion == 1)
        #expect(manifest.redistributionPolicy == "download-on-demand-never-commit-audio")
        #expect(manifest.sources.count == 2)
        #expect(manifest.sources.contains { $0.teachingUnits.contains("UE 2.11") })

        for source in manifest.sources {
            #expect(!source.id.isEmpty)
            #expect(source.language == "fr-FR")
            #expect(source.durationSeconds > 10)
            #expect(source.fileName.hasSuffix(".wav"))
            #expect(source.byteCount > 0)
            #expect(source.sha256.count == 64)
            #expect(source.landingURL.scheme == "https")
            #expect(source.downloadURL.scheme == "https")
            #expect(!source.author.isEmpty)
            #expect(source.license == "CC BY-SA 4.0")
            #expect(source.licenseURL.scheme == "https")
        }
    }
}
