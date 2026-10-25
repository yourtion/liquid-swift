import Foundation
import Liquid

// JSON-RPC 2.0 over newline-delimited stdin/stdout, as specified by Shopify/liquid-spec.
// stdout is reserved for protocol messages. No Ruby reference rendering occurs here.
var templates: [String: Template] = [:]
var sequence = 0
while let line = readLine() {
    var response: [String: Any] = ["jsonrpc": "2.0", "id": NSNull()]
    do {
        guard let data = line.data(using: .utf8),
              let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TemplateRenderError("Invalid JSON request")
        }
        response["id"] = request["id"] ?? NSNull()
        let parameters = request["params"] as? [String: Any] ?? [:]
        let method = request["method"] as? String ?? ""
        if method == "quit" { break }
        switch method {
        case "initialize":
            response["result"] = ["version": "1.0", "implementation": "liquid-swift", "features": []] as [String: Any]
        case "compile":
            guard let source = parameters["template"] as? String else { throw TemplateRenderError("Missing template") }
            do {
                #if LIQUID_SWIFT_BASELINE
                let template = try Template(source)
                #else
                let template = try Template(source, partials: parameters["filesystem"] as? [String: String] ?? [:])
                #endif
                sequence += 1
                let identifier = "template_\(sequence)"
                templates[identifier] = template
                response["result"] = ["template_id": identifier]
            } catch {
                response["result"] = ["template_id": NSNull(), "error": ["type": "syntax_error", "message": String(describing: error)]] as [String: Any]
            }
        case "render":
            guard let identifier = parameters["template_id"] as? String, let template = templates[identifier] else {
                throw TemplateRenderError("Unknown template_id")
            }
            do {
                #if LIQUID_SWIFT_BASELINE
                let output = try template.render(parameters["environment"] as? [String: Any] ?? [:])
                #else
                let options = parameters["options"] as? [String: Any] ?? [:]
                let registers = options["registers"] as? [String: Any] ?? [:]
                let now = (registers["current_time"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                let output = try template.render(parameters["environment"] as? [String: Any] ?? [:], currentTime: now)
                #endif
                response["result"] = ["output": output, "errors": []] as [String: Any]
            } catch {
                response["error"] = ["code": -32001, "message": String(describing: error), "data": ["type": "render_error"]] as [String: Any]
            }
        default:
            response["error"] = ["code": -32601, "message": "Method not found"]
        }
    } catch {
        response["error"] = ["code": -32600, "message": String(describing: error)]
    }
    if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) {
        print(json)
        fflush(nil)
    }
}
