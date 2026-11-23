import Foundation

/// App names as a row value: each name once, and a count past two, so a long
/// list is not cut off in the middle of a name.
enum AppNameList {
    static func summary(_ names: [String]) -> String {
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        switch unique.count {
        case 0:
            return "None"
        case 1, 2:
            return unique.joined(separator: ", ")
        default:
            return "\(unique.count) apps"
        }
    }
}
