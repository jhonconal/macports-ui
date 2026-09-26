import Testing
@testable import MacPortsUICore

/// Tests for the privileged-execution string builders (no real execution).
@Suite struct ShellEscapeTests {

    @Test func shellQuoteWrapsInSingleQuotes() {
        #expect(ShellEscape.shellQuote("curl") == "'curl'")
        #expect(ShellEscape.shellQuote("--all") == "'--all'")
    }

    @Test func shellQuoteEscapesEmbeddedSingleQuotes() {
        #expect(ShellEscape.shellQuote("a'b") == "'a'\\''b'")
        // Round-trip semantics: the quoted token is safe for /bin/sh.
        let q = ShellEscape.shellQuote("x'y")
        #expect(q == "'x'\\''y'")
    }

    @Test func innerShellCommandQuotesEveryToken() {
        let cmd = ShellEscape.innerShellCommand(path: "/opt/local/bin/port",
                                                args: ["install", "curl"])
        #expect(cmd == "'/opt/local/bin/port' 'install' 'curl'")
    }

    @Test func appleScriptStringEscapesBackslashAndQuote() {
        #expect(ShellEscape.appleScriptString("a\"b") == "a\\\"b")
        #expect(ShellEscape.appleScriptString("a\\b") == "a\\\\b")
    }

    @Test func osascriptStatementShape() {
        let stmt = ShellEscape.osascriptAdminStatement(path: "/opt/local/bin/port",
                                                       args: ["install", "curl"])
        // Must embed the shell command in an AppleScript string and request
        // admin privileges.
        #expect(stmt.hasPrefix("do shell script \""))
        #expect(stmt.hasSuffix("\" with administrator privileges"))
        #expect(stmt.contains("'/opt/local/bin/port' 'install' 'curl'"))
    }
}
