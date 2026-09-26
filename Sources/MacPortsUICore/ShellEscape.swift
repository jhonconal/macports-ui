import Foundation

/// Pure, testable helpers for building safely-quoted command strings for
/// privileged execution (system dialog / sudo).
public enum ShellEscape {

    /// Single-quote a token for `/bin/sh`. Embedded single quotes are escaped
    /// as `'\''`.
    public static func shellQuote(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Build the inner shell command line: `<path> a b c`, every token
    /// single-quoted so a value containing spaces/globbing stays literal.
    public static func innerShellCommand(path: String, args: [String]) -> String {
        ([path] + args).map(shellQuote).joined(separator: " ")
    }

    /// Escape a string for embedding inside an AppleScript double-quoted
    /// string literal: backslashes first, then double quotes.
    public static func appleScriptString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The full `osascript -e` statement that runs the port command as root
    /// via the system authorization dialog (Authorization Services):
    /// `do shell script "<inner>" with administrator privileges`
    public static func osascriptAdminStatement(path: String, args: [String]) -> String {
        let inner = innerShellCommand(path: path, args: args)
        return "do shell script \"\(appleScriptString(inner))\" with administrator privileges"
    }
}
