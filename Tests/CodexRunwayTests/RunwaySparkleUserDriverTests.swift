import Foundation
import Testing
@testable import CodexRunway

@Suite("Sparkle update errors")
@MainActor
struct RunwaySparkleUserDriverTests {
    @Test("network errors include proxy hint")
    func networkErrorsIncludeProxyHint() {
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        let sparkleError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Download failed",
                NSUnderlyingErrorKey: networkError,
            ])

        let message = RunwaySparkleUserDriver.errorMessage(for: sparkleError, proxyHint: "Proxy hint")

        #expect(message.contains("Download failed"))
        #expect(message.contains("Proxy hint"))
    }

    @Test("non-network errors keep original message")
    func nonNetworkErrorsKeepOriginalMessage() {
        let error = NSError(domain: "SUSparkleErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad feed"])

        #expect(RunwaySparkleUserDriver.errorMessage(for: error, proxyHint: "Proxy hint") == "Bad feed")
    }
}
