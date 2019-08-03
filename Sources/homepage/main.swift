import Foundation

let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
let environment = Environment(arguments: arguments)

environment.logger.info("Homepage is starting.")

let server = Server()
do {
    try server.start()
} catch let error {
    environment.logger.error("Error: \(error.localizedDescription)")
    server.stop()
}
