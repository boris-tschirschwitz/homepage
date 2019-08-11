//
//  HTTPHandler.swift
//  homepage
//
//  Created by Boris Tschirschwitz on 08.07.19.
//

import Foundation
import NIO
import NIOHTTP1

class HTTPHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private var buffer: ByteBuffer? = nil
    private var context: ChannelHandlerContext! = nil
    private var responseFuture: EventLoopFuture<Void>!
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.context = context
        let reqPart = self.unwrapInboundIn(data)

        switch reqPart {
        case .head(let request):
            environment.logger.info("Request Head: \(request.description.prefix(1024))")
            self.responseFuture = responseFuture(for: request).map { context.write(self.wrapOutboundOut($0), promise: nil) }

        case .body(let body):
            environment.logger.info("Request Body: \(body.description.prefix(1024))")
            
        case .end(let maybeHeaders):
            if let headers = maybeHeaders {
                environment.logger.info("Request End with headers: \(headers.description.prefix(1024))")
            } else {
                environment.logger.info("Request End")
            }
            self.responseFuture.whenSuccess {
                if let buffer = self.buffer?.slice() {
                    context.write(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                }
                self.completeResponse(context/*, promise: self.responsePromise*/)
            }
        }
    }

    private func responseFuture(for request: HTTPRequestHead) -> EventLoopFuture<HTTPServerResponsePart> {
        let promise = self.context.eventLoop.makePromise(of: HTTPServerResponsePart.self)
        self.context.eventLoop.execute {
            var builder = self.allow([.GET], request) {
                self.ifPageIsAvailable(request, database: self.database) { (page) in
                    self.ifCacheIsInvalid(request, page: page) {
                        self.choosingContentEncoding(request, page.source) { (contentEncoding, data) in
                            return ResponseBuilder(request, .ok, data: data, contentType: page.contentType, contentEncoding: contentEncoding, scriptSrc: page.scriptSrc)
                        }
                    }
                }
            }

            builder.addContentLength(self.buffer(builder.data))
            let response = HTTPServerResponsePart.head(builder.head)
            promise.succeed(response)
        }

        return promise.futureResult
    }

    private func buffer(_ data: Data) -> Int {
        if !data.isEmpty {
            self.buffer = self.context.channel.allocator.buffer(capacity: data.count)
            self.buffer!.writeBytes(data)
        }
        return self.buffer?.readableBytes ?? 0
    }

    private func allow(_ methods: [HTTPMethod], _ request: HTTPRequestHead, closure: () -> ResponseBuilder) -> ResponseBuilder {
        guard methods.contains(request.method) else {
            environment.logger.info("Method not allowed \(request.method)")
            return ResponseBuilder(request, .methodNotAllowed, text: "Method not allowed.")
        }

        guard request.uri.count < 64 else {
            environment.logger.info("Rejected URI of length \(request.uri.count)")
            return ResponseBuilder(request, .uriTooLong, text: "URI too long!")
        }

        return closure()
    }

    private func ifPageIsAvailable(_ request: HTTPRequestHead, database: Database, closure: (Page) -> ResponseBuilder) -> ResponseBuilder {
        guard let page = database.contents.pages[request.uri] else {
            environment.logger.info("Unknown page requested.")
            return ResponseBuilder(request, .notFound, text: "Page not Found")
        }

        return closure(page)
    }

    private func ifCacheIsInvalid(_ request: HTTPRequestHead, page: Page, closure: () -> ResponseBuilder) -> ResponseBuilder {
        guard let serverETag = page.etag else {
            environment.logger.info("Don't cache \(request.uri).")
            return closure()
        }

        if let clientETag = request.eTag(),
            clientETag == serverETag {
            environment.logger.info("Resource not modified.")
            return ResponseBuilder(request, .notModified)
        }

        var builder = closure()
        builder.addCaching(eTag: serverETag)
        return builder
    }

    private func choosingContentEncoding(_ request: HTTPRequestHead, _ source: PageSource, closure: (ContentEncoding, Data) -> ResponseBuilder) -> ResponseBuilder {
        switch source {
        case .text(let pageText):
            environment.logger.info("Simple inline text content")
            return closure(.text, pageText.data(using: .utf8)!)
        case .file(let encoded):
            if request.contentEncodings().contains(.gzip),
                let gzipPath = encoded[.gzip] {
                environment.logger.info("Gzip content")
                var builder = closure(.gzip, try! self.database.data(at: gzipPath))
                builder.addContentEncoding(.gzip)
                return builder
            } else {
                environment.logger.info("File text content")
                return closure(.text, try! self.database.data(at: encoded[.text]!))
            }
        }
    }


    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        environment.logger.error("\(error.localizedDescription)")
        context.close(promise: nil)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    static func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, contentType: ContentType, headers: HTTPHeaders = HTTPHeaders(), scriptSrc: String?) -> HTTPResponseHead {
        var head = HTTPResponseHead(version: request.version, status: status, headers: headers)
        let connectionHeaders: [String] = head.headers[canonicalForm: "connection"].map { $0.lowercased() }

        if !connectionHeaders.contains("keep-alive") && !connectionHeaders.contains("close") {
            // the user hasn't pre-set either 'keep-alive' or 'close', so we might need to add headers
            switch (request.isKeepAlive, request.version.major, request.version.minor) {
            case (true, 1, 0):
                // HTTP/1.0 and the request has 'Connection: keep-alive', we should mirror that
                head.headers.add(name: "Connection", value: "keep-alive")
            case (false, 1, let n) where n >= 1:
                // HTTP/1.1 (or treated as such) and the request has 'Connection: close', we should mirror that
                head.headers.add(name: "Connection", value: "close")
            default:
                // we should match the default or are dealing with some HTTP that we don't support, let's leave as is
                ()
            }
        }
        head.headers.add(name: "content-type", value: contentType.headerCode)
        if let source = scriptSrc {
            head.headers.add(name: "content-security-policy", value: "script-src '\(source)'")
        } else {
            head.headers.add(name: "content-security-policy", value: "default-src 'self'")
        }
        head.headers.add(name: "x-content-type-options", value: "'nosniff'")
        return head
    }

    private func completeResponse(_ context: ChannelHandlerContext, trailers: HTTPHeaders? = nil, promise: EventLoopPromise<Void>? = nil) {
        let promise = promise ?? context.eventLoop.makePromise()
        context.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
        promise.futureResult.whenComplete { (_: Result<Void, Error>) in
            environment.logger.info("Response completed.")
            context.close(promise: nil)
        }
    }
}

extension HTTPRequestHead {
    func eTag() -> String? {
        guard self.headers.contains(name: "if-none-match") else { return nil }
        return self.headers["if-none-match"].first
    }

    func contentEncodings() -> [ContentEncoding] {
        var encodings: [ContentEncoding] = [.text]
        guard self.headers.contains(name: "accept-encoding") else { return encodings }
        let encodingTexts = self.headers["accept-encoding"][0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if encodingTexts.contains("gzip") {
            encodings.append(.gzip)
        }
        return encodings
    }
}

extension HTTPHandler {
    struct ResponseBuilder {
        let request: HTTPRequestHead
        let data: Data
        var head: HTTPResponseHead

        init(_ request: HTTPRequestHead, _ status: HTTPResponseStatus, text: String = "", contentType: ContentType = .plain, scriptSrc: String? = nil) {
            self.request = request
            self.head = HTTPHandler.httpResponseHead(request: request, status: status, contentType: contentType, scriptSrc: scriptSrc)
            self.data = text.data(using: .utf8)!
        }

        init(_ request: HTTPRequestHead, _ status: HTTPResponseStatus, data: Data, contentType: ContentType = .plain, contentEncoding: ContentEncoding = .text, scriptSrc: String? = nil) {
            self.request = request
            self.head = HTTPHandler.httpResponseHead(request: request, status: status, contentType: contentType, scriptSrc: scriptSrc)
            self.data = data
        }

        mutating func addCaching(eTag: String) {
            self.head.headers.add(name: "cache-control", value: "public")
            self.head.headers.add(name: "etag", value: eTag)
        }

        mutating func addContentLength(_ length: Int) {
            self.head.headers.add(name: "content-length", value: "\(length))")
        }

        mutating func addContentEncoding(_ encoding: ContentEncoding) {
            self.head.headers.add(name: "content-encoding", value: "gzip")
        }
    }
}
