import Foundation
import Hummingbird
import Liquid

/// Template is not Sendable. Keep the parsed instance inside an actor and pass
/// only Sendable request parameters and rendered HTML across the actor boundary.
private actor PageRenderer {
    private let template: Template

    init() throws {
        guard let url = Bundle.module.url(forResource: "index", withExtension: "liquid", subdirectory: "Templates") else {
            throw TemplateRenderError("Missing bundled index.liquid template")
        }
        template = try Template(String(contentsOf: url, encoding: .utf8))
    }

    func render(name: String, category: String, empty: Bool) throws -> String {
        // Build a fresh dictionary for every request; assignments and counters
        // must never leak from one visitor's response to another's.
        let products: [[String: Any]] = [
            ["name": "Jasmine Tea", "category": "tea", "price": 8, "stock": 12, "symbol": "🍵"],
            ["name": "Ceramic Cup", "category": "home", "price": 16, "stock": 4, "symbol": "☕"],
            ["name": "Travel Flask", "category": "home", "price": 24, "stock": 0, "symbol": "🫖"],
        ]
        let selected = empty ? [] : products.filter { category == "all" || $0["category"] as? String == category }
        return try template.render([
            "name": String(name.prefix(200)),
            "category": category,
            "show_empty": empty,
            "products": selected,
            "categories": ["all", "tea", "home"],
        ])
    }
}

@main
struct LiquidServer {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let hostname = environment["HOST"] ?? "127.0.0.1"
        guard let port = Int(environment["PORT"] ?? "8080"), (1...65535).contains(port) else {
            throw TemplateRenderError("PORT must be an integer between 1 and 65535")
        }
        let renderer = try PageRenderer()
        let router = Router()
        router.get("/") { request, _ -> Response in
            let query = request.uri.queryParameters
            let name = query["name"].map(String.init) ?? "Swift friend"
            let requestedCategory = query["category"].map(String.init) ?? "all"
            let category = ["all", "tea", "home"].contains(requestedCategory) ? requestedCategory : "all"
            let html = try await renderer.render(name: name, category: category, empty: query["empty"] == "1")
            return Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8", .cacheControl: "no-store"],
                body: .init(byteBuffer: ByteBuffer(string: html))
            )
        }
        router.get("/health") { _, _ in "ok" }
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )
        try await app.runService()
    }
}
