import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Rate limit reset today")
struct RateLimitResetTodayTests {
    @Test("decodes live-shaped status payload")
    func decodesLiveShapedStatusPayload() throws {
        let json = """
        {
          "autoResetHours": 20,
          "automationSummary": {
            "checkedAt": 1784610899881,
            "confidence": 0.99,
            "tweetUrl": "https://x.com/thsottiaux/status/2079433708986319143",
            "verdict": "not_reset",
            "usage": {
              "inputTokens": 371,
              "outputTokens": 69,
              "reasoningTokens": 25,
              "totalTokens": 440
            },
            "latest": {
              "checkedAt": 1784610899881,
              "confidence": 0.99,
              "tweetUrl": "https://x.com/thsottiaux/status/2079433708986319143",
              "tweetText": "@Kappaemme1926 We are being very subtle.",
              "verdict": "not_reset",
              "usage": {
                "inputTokens": 371,
                "outputTokens": 69,
                "reasoningTokens": 25
              }
            },
            "lastReset": {
              "checkedAt": null,
              "verdict": null
            },
            "model": "gpt-5.4"
          },
          "configured": true,
          "noSubtitles": ["Back to your local model peasant", "But that's okay"],
          "yesSubtitles": ["Limits reset, go crazy", "You can just build things"],
          "resetAt": null,
          "state": "no",
          "updatedAt": 1784345380676
        }
        """.data(using: .utf8)!

        let snapshot = try RateLimitResetTodaySnapshot.decode(from: json, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(snapshot.state == .no)
        #expect(snapshot.resetAt == nil)
        #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 1_784_345_380.676))
        #expect(snapshot.autoResetHours == 20)
        #expect(snapshot.yesSubtitles.count == 2)
        #expect(snapshot.noSubtitles.count == 2)
        #expect(snapshot.confidence == 0.99)
        #expect(snapshot.tweetURL?.host == "x.com")
        #expect(snapshot.model == "gpt-5.4")
        #expect(snapshot.latestUsage?.inputTokens == 371)
        #expect(snapshot.latestUsage?.outputTokens == 69)
        #expect(snapshot.latestUsage?.reasoningTokens == 25)
        #expect(snapshot.latestVerdict == "not_reset")
        #expect(snapshot.tweetText == "@Kappaemme1926 We are being very subtle.")
        #expect(snapshot.displayTweetLine == "@Kappaemme1926 We are being very subtle.")
    }

    @Test("display tweet line collapses whitespace")
    func displayTweetLineCollapsesWhitespace() {
        let snapshot = RateLimitResetTodaySnapshot(
            state: .no,
            tweetText: "hello\nworld  ")
        #expect(snapshot.displayTweetLine == "hello world")
    }

    @Test("decodes yes state and millisecond resetAt")
    func decodesYesStateAndMillisecondResetAt() throws {
        let json = """
        {
          "state": "yes",
          "resetAt": 1784345380676,
          "updatedAt": 1784345380676,
          "yesSubtitles": ["Limits reset, go crazy"],
          "noSubtitles": []
        }
        """.data(using: .utf8)!

        let snapshot = try RateLimitResetTodaySnapshot.decode(from: json)

        #expect(snapshot.state == .yes)
        #expect(snapshot.resetAt == Date(timeIntervalSince1970: 1_784_345_380.676))
        #expect(snapshot.tweetText == nil)
    }

    @Test("unknown state and missing optional fields still decode")
    func unknownStateAndMissingOptionalFieldsStillDecode() throws {
        let json = """
        {
          "state": "maybe"
        }
        """.data(using: .utf8)!

        let snapshot = try RateLimitResetTodaySnapshot.decode(from: json)

        #expect(snapshot.state == .unknown)
        #expect(snapshot.yesSubtitles.isEmpty)
        #expect(snapshot.noSubtitles.isEmpty)
        #expect(snapshot.confidence == nil)
        #expect(snapshot.tweetURL == nil)
    }

    @Test("epoch helper accepts seconds and milliseconds")
    func epochHelperAcceptsSecondsAndMilliseconds() {
        #expect(RateLimitResetTodaySnapshot.date(fromEpoch: 1_700_000_000) == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(RateLimitResetTodaySnapshot.date(fromEpoch: 1_700_000_000_000) == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(RateLimitResetTodaySnapshot.date(fromEpoch: nil) == nil)
        #expect(RateLimitResetTodaySnapshot.date(fromEpoch: 0) == nil)
    }

    @Test("yes-countdown mock exposes a future next reset window")
    func yesCountdownMockExposesFutureNextResetWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = RateLimitResetTodaySnapshot.devMock(kind: .yesCountdown, now: now)
        #expect(snapshot.state == .yes)
        #expect(snapshot.nextResetRemaining(now: now) != nil)
        #expect((snapshot.nextResetRemaining(now: now) ?? 0) > 17 * 3_600)
    }

    @Test("plain yes mock has no active countdown")
    func plainYesMockHasNoActiveCountdown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = RateLimitResetTodaySnapshot.devMock(kind: .yes, now: now)
        #expect(snapshot.state == .yes)
        #expect(snapshot.nextResetRemaining(now: now) == nil)
    }
}
