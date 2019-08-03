//
//  Environment.swift
//  Basic
//
//  Created by Boris Tschirschwitz on 24.07.19.
//

import Foundation
import Logging
import SPMUtility

struct Environment {
    let logger: Logger
    let contentsUrl: Foundation.URL
    let hostName: String
    let port: Int

    private static let defaultHostName = "localhost"
    private static let defaultPort = 8080
}

extension Environment {
    init(arguments: [String]) {
        print("args: \(arguments)")
        let parser = ArgumentParser(usage: "<options>", overview: "Homepage Server")
        let hostNameArgument = parser.add(option: "--hostName", shortName: "-n", kind: String.self, usage: "The server's host name, defaults to '\(Environment.defaultHostName)'.")
        let portArgument = parser.add(option: "--port", shortName: "-p", kind: Int.self, usage: "The server's port, defaults to \(Environment.defaultPort).")
        let logLevelArgument = parser.add(option: "--logLevel", shortName: "-l", kind: Logger.Level.self, usage: "The level of logging information, 'debug', 'info', or 'error', defaults to 'debug'.")
        let contentPathArgument = parser.add(option: "--contentPath", shortName: "-c", kind: String.self, usage: "The path to the Content folder.")
        guard let parsedArguments = try? parser.parse(arguments) else {
            print("Argument parsing failed.")
            fatalError()
        }
        var logger = Logger(label: "homepage.main")
        logger.logLevel = parsedArguments.get(logLevelArgument) ?? .debug
        self.logger = logger

        if let hostName = parsedArguments.get(hostNameArgument) {
            self.hostName = hostName
            logger.info("using hostname from argument: \(hostName)")
        } else {
            self.hostName = Environment.defaultHostName
            logger.info("using default host name '\(Environment.defaultHostName)'")
        }
        
        if let port = parsedArguments.get(portArgument) {
            self.port = port
            logger.info("using port from argument: \(port)")
        } else {
            self.port = Environment.defaultPort
            logger.info("using default port \(Environment.defaultPort)")
        }

        if let contentPath = parsedArguments.get(contentPathArgument) {
            self.contentsUrl = URL(fileURLWithPath: contentPath, isDirectory: true)
            logger.info("using content path from argument: \(self.contentsUrl.absoluteString)")
        } else {
            let url = FileManager.default.homeDirectoryForCurrentUser
            #if DEBUG
            self.contentsUrl = url.appendingPathComponent("Projects/homepage/Sources/homepage/Contents")
            #else
            self.contentsUrl = url.appendingPathComponent("Contents")
            #endif
            logger.info("using fallback content path: \(self.contentsUrl.absoluteString)")
        }
    }
}

extension Logger.Level: ArgumentKind {
    public init(argument: String) throws {
        switch argument {
        case "debug": self = .debug
        case "info": self = .info
        case "error": self = .error
        default: throw ArgumentConversionError.unknown(value: argument)
        }
    }

    public static var completion: ShellCompletion = .none
}

