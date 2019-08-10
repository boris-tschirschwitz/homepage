//
//  Server.swift
//  homepage
//
//  Created by Boris Tschirschwitz on 08.07.19.
//

import Foundation
import NIO
import NIOHTTP1

class Server: Database {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let contents = Contents()
    
    private var serverBootstrap: ServerBootstrap {
        return ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPHandler(database: self))
                }
        }

            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
    }

    init() {
    }


    func start() throws {
        environment.logger.info("Starting server.")
        do {
            let channel = try serverBootstrap.bind(host: environment.hostName, port: environment.port).wait()
            environment.logger.info("\(channel.localAddress?.description ?? "no address") is now open")
            try channel.closeFuture.wait()
        } catch let error {
            environment.logger.error("Server startup failed!")
            throw error
        }
    }

    func stop() {
        environment.logger.info("Stopping server.")
        do {
            try group.syncShutdownGracefully()
        } catch let error {
            environment.logger.error("Could not shutdown gracefully - forcing exit (\(error.localizedDescription))")
            exit(0)
        }
        environment.logger.info("Server closed")
    }
}

enum ContentType: String, Decodable {
    case html = "text/html"
    case markdown = "text/markdown"
    case plain = "text/plain"
}

extension ContentType {
    var options: String {
        switch self {
        case .html, .markdown, .plain: return "; charset=utf-8"
        }
    }

    var headerCode: String {
        return self.rawValue.appending(self.options)
    }
}

enum ContentEncoding {
    case text
    case gzip
}

enum PageSource {
    case text(String)
    case file([ContentEncoding : String])
}

struct Page: Decodable {
    let uri: String
    let source: PageSource
    let etag: String?
    let contentType: ContentType

    enum CodingKeys: String, CodingKey {
        case uri
        case text
        case file
        case gzip
        case etag
        case contentType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.etag = try container.decode(String.self, forKey: .etag)
        self.contentType = try container.decode(ContentType.self, forKey: .contentType)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self.source = .text(text)
        } else {
            var files: [ContentEncoding: String] = [.text: try container.decode(String.self, forKey: .file)]
            if let gzip = try container.decodeIfPresent(String.self, forKey: .gzip) {
                files[.gzip] = gzip
            }
            self.source = .file(files)
        }
    }
}

struct Contents {
    let pages: [String: Page]

    static var pagesUrl: URL = {
        environment.contentsUrl.appendingPathComponent("pages.json")
    }()

    init() {
        do {
            environment.logger.info("Path to contents: \(environment.contentsUrl.absoluteString)")
            let jsonData = try Data(contentsOf: Contents.pagesUrl)
            self.pages = Dictionary(uniqueKeysWithValues: try JSONDecoder().decode([Page].self, from: jsonData).map { ($0.uri, $0)})
        } catch {
            environment.logger.error("No contents. Error: \(error.localizedDescription)")
            fatalError()
        }
    }
}

protocol Database {
    var contents: Contents { get }
}

extension Database {
    func data(at path: String) throws -> Data {
        return try Data(contentsOf: environment.contentsUrl.appendingPathComponent(path))
    }
}
