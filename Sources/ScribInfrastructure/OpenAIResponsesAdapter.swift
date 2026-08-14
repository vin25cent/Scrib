import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ScribApplication
import ScribDomain

public final class OpenAIResponsesAdapter: AICloudGenerating, @unchecked Sendable {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func generate(
        _ request: AIProviderGenerationRequest,
        credential: String?
    ) async throws -> AIProviderGenerationResponse {
        guard let credential = credential?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credential.isEmpty else {
            throw AIGenerationError.missingCredential(.openAI)
        }
        var urlRequest = try OpenAIResponsesRequestBuilder.makeRequest(
            request,
            endpoint: endpoint
        )
        urlRequest.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            let retryable: Set<URLError.Code> = [
                .timedOut, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet
            ]
            throw AIGenerationError.provider(
                message: "Connexion impossible (\(error.code.rawValue)).",
                retryable: retryable.contains(error.code)
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIGenerationError.provider(message: "Réponse HTTP invalide.", retryable: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            let rawMessage = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?.error.message
                ?? "Erreur HTTP \(http.statusCode)."
            let message = String(rawMessage.prefix(500))
            let retryable = http.statusCode == 408 || http.statusCode == 409
                || http.statusCode == 429 || http.statusCode >= 500
            throw AIGenerationError.provider(message: message, retryable: retryable)
        }

        let decoded: OpenAIResponseEnvelope
        do {
            decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        } catch {
            throw AIGenerationError.provider(message: "Format de réponse inconnu.", retryable: false)
        }
        let contentItems = decoded.output.flatMap { $0.content ?? [] }
        guard let outputText = contentItems
            .first(where: { $0.type == "output_text" })?.text,
              let payload = outputText.data(using: .utf8) else {
            let refusal = contentItems.first { $0.type == "refusal" }?.refusal
            throw AIGenerationError.provider(
                message: refusal ?? "Aucun JSON structuré dans la réponse.",
                retryable: false
            )
        }
        return AIProviderGenerationResponse(
            payload: payload,
            usage: AIProviderUsage(
                providerRequestID: decoded.id,
                inputTokens: decoded.usage?.inputTokens ?? 0,
                cachedInputTokens: decoded.usage?.inputTokenDetails?.cachedTokens ?? 0,
                outputTokens: decoded.usage?.outputTokens ?? 0
            )
        )
    }
}

enum OpenAIResponsesRequestBuilder {
    static func makeRequest(
        _ request: AIProviderGenerationRequest,
        endpoint: URL
    ) throws -> URLRequest {
        let schema = try JSONSerialization.jsonObject(with: Data(strictSchema.utf8))
        let body: [String: Any] = [
            "model": request.modelID,
            "store": false,
            "max_output_tokens": request.maximumOutputTokens,
            "input": [
                [
                    "role": "developer",
                    "content": [["type": "input_text", "text": request.developerPrompt]]
                ],
                [
                    "role": "user",
                    "content": [["type": "input_text", "text": request.input]]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "scrib_course_generation_v1",
                    "description": "Deux documents de cours conformes au contrat Scrib 1.0",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "metadata": [
                "scrib_course_id": request.courseID.rawValue.uuidString,
                "scrib_idempotency_key": request.idempotencyKey
            ]
        ]
        var result = URLRequest(url: endpoint)
        result.httpMethod = "POST"
        result.timeoutInterval = 180
        result.httpBody = try JSONSerialization.data(withJSONObject: body)
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        result.setValue(request.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        result.setValue("Scrib/0.1", forHTTPHeaderField: "User-Agent")
        return result
    }

    static let strictSchema = #"""
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["schemaVersion", "courseID", "documents", "sources"],
      "properties": {
        "schemaVersion": {"type": "string", "const": "1.0"},
        "courseID": {"type": "string"},
        "documents": {"type": "array", "items": {"$ref": "#/$defs/document"}},
        "sources": {"type": "array", "items": {"$ref": "#/$defs/source"}}
      },
      "$defs": {
        "metadata": {
          "type": "object", "additionalProperties": false,
          "required": ["label", "value"],
          "properties": {"label": {"type": "string"}, "value": {"type": "string"}}
        },
        "source": {
          "type": "object", "additionalProperties": false,
          "required": ["id", "authority", "title", "canonicalURL", "verifiedAt"],
          "properties": {
            "id": {"type": "string"}, "authority": {"type": "string"},
            "title": {"type": "string"}, "canonicalURL": {"type": "string"},
            "verifiedAt": {"type": "string"}
          }
        },
        "table": {
          "type": "object", "additionalProperties": false,
          "required": ["caption", "headers", "rows", "columnWidthWeights"],
          "properties": {
            "caption": {"type": ["string", "null"]},
            "headers": {"type": "array", "items": {"type": "string"}},
            "rows": {"type": "array", "items": {"type": "array", "items": {"type": "string"}}},
            "columnWidthWeights": {"type": ["array", "null"], "items": {"type": "integer"}}
          }
        },
        "callout": {
          "type": "object", "additionalProperties": false,
          "required": ["kind", "title", "body", "audioTimestampSeconds"],
          "properties": {
            "kind": {"enum": ["information", "uncertainty", "medicalImportance", "scientificUpdate"]},
            "title": {"type": "string"}, "body": {"type": "string"},
            "audioTimestampSeconds": {"type": ["number", "null"]}
          }
        },
        "figure": {
          "type": "object", "additionalProperties": false,
          "required": ["assetID", "caption", "altText", "widthPoints"],
          "properties": {
            "assetID": {"type": "string"}, "caption": {"type": "string"},
            "altText": {"type": "string"}, "widthPoints": {"type": ["number", "null"]}
          }
        },
        "block": {
          "type": "object", "additionalProperties": false,
          "required": ["type", "text", "items", "table", "callout", "figure", "sourceIDs"],
          "properties": {
            "type": {"enum": ["paragraph", "bullets", "table", "callout", "figure"]},
            "text": {"type": ["string", "null"]},
            "items": {"type": ["array", "null"], "items": {"type": "string"}},
            "table": {"anyOf": [{"$ref": "#/$defs/table"}, {"type": "null"}]},
            "callout": {"anyOf": [{"$ref": "#/$defs/callout"}, {"type": "null"}]},
            "figure": {"anyOf": [{"$ref": "#/$defs/figure"}, {"type": "null"}]},
            "sourceIDs": {"type": "array", "items": {"type": "string"}}
          }
        },
        "section": {
          "type": "object", "additionalProperties": false,
          "required": ["title", "blocks"],
          "properties": {
            "title": {"type": "string"},
            "blocks": {"type": "array", "items": {"$ref": "#/$defs/block"}}
          }
        },
        "document": {
          "type": "object", "additionalProperties": false,
          "required": ["kind", "title", "subtitle", "metadata", "sections"],
          "properties": {
            "kind": {"enum": ["fullCourse", "revisionSheet"]},
            "title": {"type": "string"}, "subtitle": {"type": "string"},
            "metadata": {"type": "array", "items": {"$ref": "#/$defs/metadata"}},
            "sections": {"type": "array", "items": {"$ref": "#/$defs/section"}}
          }
        }
      }
    }
    """#
}

private struct OpenAIResponseEnvelope: Decodable {
    struct Output: Decodable {
        struct Content: Decodable {
            var type: String
            var text: String?
            var refusal: String?
        }
        var content: [Content]?
    }
    struct Usage: Decodable {
        struct InputTokenDetails: Decodable {
            var cachedTokens: Int?
            enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
        }
        var inputTokens: Int
        var outputTokens: Int
        var inputTokenDetails: InputTokenDetails?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case inputTokenDetails = "input_tokens_details"
        }
    }
    var id: String
    var output: [Output]
    var usage: Usage?
}

private struct OpenAIErrorEnvelope: Decodable {
    struct APIError: Decodable { var message: String }
    var error: APIError
}
