import HTTP
import Routing

extension Droplet: Responder {
    /// Returns a response to the given request
    ///
    /// - parameter request: received request
    /// - throws: error if something fails in finding response
    /// - returns: response if possible
    public func respond(to request: Request) -> Response {
        log.info("\(request.method) \(request.uri.path)")
        
        let isHead = request.method == .head
        if isHead {
            /// The HEAD method is identical to GET.
            ///
            /// https://tools.ietf.org/html/rfc2616#section-9.4
            request.method = .get
        }
        
        let response: Response
        do {
            response = try responder.respond(to: request)
        } catch {
            response = errorResponse(with: request, and: error)
        }
        
        if isHead {
            /// The server MUST NOT return a message-body in the response for HEAD.
            ///
            /// https://tools.ietf.org/html/rfc2616#section-9.4
            response.body = .data([])
        }
        
        return response
    }

    private func errorResponse(with request: Request, and error: Error) -> Response {
        logError(error)
        guard !request.accept.prefers("html") else { return view.make(error).makeResponse() }

        let status = Status(error)
        let response = Response(status: status)
        response.json = JSON(error, env: environment)
        return response
    }

    private func logError(_ error: Error) {
        if let debuggable = error as? Debuggable {
            log.error(debuggable.loggable)
        } else {
            let type = String(reflecting: type(of: error))
            log.error("[\(type): \(error)]")
            log.info("Conform '\(type)' to Debugging.Debuggable to provide more debug information.")
        }
    }
}

extension Status {
    internal init(_ error: Error) {
        if let abort = error as? AbortError {
            self = abort.status
        } else {
            self = .internalServerError
        }
    }
}

extension JSON {
    fileprivate init(_ error: Error, env: Environment) {
        let status = Status(error)

        var json = JSON(["error": true])
        if let abort = error as? AbortError {
            json.set("reason", abort.reason)
        } else {
            json.set("reason", status.reasonPhrase)
        }

        guard env != .production else {
            self = json
            return
        }

        if env != .production {
            if let abort = error as? AbortError {
                json.set("metadata", abort.metadata)
            }

            if let debug = error as? Debuggable {
                json.set("debugReason", debug.reason)
                json.set("identifier", debug.fullIdentifier)
                json.set("possibleCauses", debug.possibleCauses)
                json.set("suggestedFixes", debug.suggestedFixes)
                json.set("documentationLinks", debug.documentationLinks)
                json.set("stackOverflowQuestions", debug.stackOverflowQuestions)
                json.set("gitHubIssues", debug.gitHubIssues)
            }
        }

        self = json
    }
}

extension StructuredDataWrapper {
    fileprivate mutating func set(_ key: String, _ closure: (Context?) throws -> Node) rethrows {
        let node = try closure(context)
        set(key, node)
    }

    fileprivate mutating func set(_ key: String, _ value: String?) {
        guard let value = value, !value.isEmpty else { return }
        set(key, value.makeNode)
    }

    fileprivate mutating func set(_ key: String, _ node: Node?) {
        guard let node = node else { return }
        self[key] = Self(node, context)
    }

    fileprivate mutating func set(_ key: String, _ array: [String]?) {
        guard let array = array?.map(StructuredData.string).map(Self.init), !array.isEmpty else { return }
        self[key] = .array(array)
    }
}

extension StructuredDataWrapper {
    // TODO: I expected this, maybe put in node
    init(_ node: Node, _ context: Context) {
        self.init(node: node.wrapped, in: context)
    }
}

extension Debuggable {
    var loggable: String {
        var print: [String] = []

        print.append("\(Self.readableName): \(reason)")
        print.append("Identifier: \(fullIdentifier)")

        if !possibleCauses.isEmpty {
            print.append("Possible Causes: \(possibleCauses.commaSeparated)")
        }

        if !suggestedFixes.isEmpty {
            print.append("Suggested Fixes: \(suggestedFixes.commaSeparated)")
        }

        if !documentationLinks.isEmpty {
            print.append("Documentation Links: \(documentationLinks.commaSeparated)")
        }

        if !stackOverflowQuestions.isEmpty {
            print.append("Stack Overflow Questions: \(stackOverflowQuestions.commaSeparated)")
        }

        if !gitHubIssues.isEmpty {
            print.append("GitHub Issues: \(gitHubIssues.commaSeparated)")
        }

        return print.map { "[\($0)]" }.joined(separator: " ")
    }
}

extension Sequence where Iterator.Element == String {
    var commaSeparated: String {
        return joined(separator: ", ")
    }
}


extension RouterError: AbortError {
    public var status: Status { return Abort.notFound.status }
    public var reason: String { return Abort.notFound.reason }
    public var metadata: Node? { return Abort.notFound.metadata }
}
