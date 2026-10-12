import Foundation
import Testing
@testable import RastroCore

struct GitLogParserTests {
    let sample = """
    abc123\u{1F}Dev\u{1F}dev@exemplo.com\u{1F}2026-10-10T14:30:00-03:00\u{1F}feat: timeline\u{1E}
    def456\u{1F}Outra Pessoa\u{1F}outra@exemplo.com\u{1F}2026-10-09T09:00:00-03:00\u{1F}fix: assunto com \u{1F}? não\u{1E}
    999\u{1F}Dev\u{1F}DEV@exemplo.com\u{1F}2026-10-08T08:00:00+00:00\u{1F}chore: email maiúsculo\u{1E}
    """

    @Test func parsesCommits() throws {
        let commits = GitLogParser.parse(sample)
        // A segunda linha tem 6 campos (assunto com separador) e é descartada.
        #expect(commits.map(\.hash) == ["abc123", "999"])
        let first = try #require(commits.first)
        #expect(first.authorEmail == "dev@exemplo.com")
        #expect(first.subject == "feat: timeline")
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-10-10T17:30:00Z"))
    }

    @Test func ignoresGarbage() {
        #expect(GitLogParser.parse("").isEmpty)
        #expect(GitLogParser.parse("linha solta\u{1E}").isEmpty)
        #expect(GitLogParser.parse("a\u{1F}b\u{1F}c\u{1F}data-invalida\u{1F}s\u{1E}").isEmpty)
    }

    @Test func filtersByEmailCaseInsensitive() {
        let commits = GitLogParser.parse(sample)
        let mine = GitLogParser.filter(commits, authorEmails: [" Dev@Exemplo.com "])
        #expect(mine.map(\.hash) == ["abc123", "999"])
        #expect(GitLogParser.filter(commits, authorEmails: ["ninguem@x.com"]).isEmpty)
    }

    @Test func emptyEmailListKeepsEverything() {
        let commits = GitLogParser.parse(sample)
        #expect(GitLogParser.filter(commits, authorEmails: []).count == commits.count)
        #expect(GitLogParser.filter(commits, authorEmails: ["  "]).count == commits.count)
    }
}
