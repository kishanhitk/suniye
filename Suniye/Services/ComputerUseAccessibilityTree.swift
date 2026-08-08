import Foundation

struct ComputerUseAXNode: Equatable, Sendable {
    let role: String
    let roleDescription: String?
    let subrole: String?
    let title: String?
    let description: String?
    let help: String?
    let identifier: String?
    let value: String?
    let isEnabled: Bool
    let isValueSettable: Bool
    let secondaryActions: [String]
    let children: [ComputerUseAXNode]
}

struct ComputerUseAXSnapshot: Equatable, Sendable {
    let roots: [ComputerUseAXNode]
}

struct ComputerUseAccessibilityElementReference: Equatable, Sendable {
    let rootIndex: Int
    let path: [Int]
    let role: String
    let identifier: String?
}

struct ComputerUseAccessibilityRevision: Equatable, Sendable {
    let id: UUID
    let text: String
    let elements: [Int: ComputerUseAccessibilityElementReference]
}

actor ComputerUseAccessibilityRevisionStore {
    private struct TargetState {
        let elements: [RenderedElement]
        let nextElementID: Int
    }

    private struct RenderedElement {
        let id: Int
        let reference: ComputerUseAccessibilityElementReference
        let matchKey: MatchKey
        let line: String
    }

    private enum MatchKey: Hashable {
        case identifier(role: String, identifier: String)
        case path(rootIndex: Int, path: [Int], role: String, subrole: String?)
    }

    private enum ChangeKind: Int {
        case removal
        case insertion
    }

    private struct Change {
        let reference: ComputerUseAccessibilityElementReference
        let kind: ChangeKind
        let line: String
    }

    private var states: [String: TargetState] = [:]

    func revision(
        targetKey: String,
        snapshot: ComputerUseAXSnapshot,
        disableDiff: Bool
    ) -> ComputerUseAccessibilityRevision {
        let previous = states[targetKey]
        let flattened = flatten(snapshot)
        var reusableIDs = reusableElementIDs(from: previous?.elements ?? [])
        var nextElementID = previous?.nextElementID ?? 0
        let rendered = flattened.map { flattenedElement in
            let id: Int
            if var candidates = reusableIDs[flattenedElement.matchKey],
               let inherited = candidates.first {
                id = inherited
                candidates.removeFirst()
                reusableIDs[flattenedElement.matchKey] = candidates
            } else {
                id = nextElementID
                nextElementID += 1
            }
            return RenderedElement(
                id: id,
                reference: flattenedElement.reference,
                matchKey: flattenedElement.matchKey,
                line: renderLine(
                    node: flattenedElement.node,
                    id: id,
                    depth: flattenedElement.reference.path.count
                )
            )
        }
        states[targetKey] = TargetState(elements: rendered, nextElementID: nextElementID)

        let fullText = rendered.map(\.line).joined(separator: "\n")
        let text: String
        if disableDiff || previous == nil {
            text = fullText
        } else {
            let diff = renderDiff(previous: previous?.elements ?? [], current: rendered)
            text = diff.isEmpty ? fullText : diff
        }
        return ComputerUseAccessibilityRevision(
            id: UUID(),
            text: text,
            elements: Dictionary(uniqueKeysWithValues: rendered.map { ($0.id, $0.reference) })
        )
    }

    private func reusableElementIDs(from elements: [RenderedElement]) -> [MatchKey: [Int]] {
        Dictionary(grouping: elements, by: \.matchKey).mapValues { $0.map(\.id) }
    }

    private func renderDiff(
        previous: [RenderedElement],
        current: [RenderedElement]
    ) -> String {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var changes: [Change] = []

        for element in previous where currentByID[element.id] == nil {
            changes.append(Change(reference: element.reference, kind: .removal, line: "- \(element.line)"))
        }
        for element in current {
            guard let oldElement = previousByID[element.id] else {
                changes.append(Change(reference: element.reference, kind: .insertion, line: "+ \(element.line)"))
                continue
            }
            if oldElement.line != element.line {
                changes.append(Change(reference: element.reference, kind: .removal, line: "- \(oldElement.line)"))
                changes.append(Change(reference: element.reference, kind: .insertion, line: "+ \(element.line)"))
            }
        }
        return changes.sorted(by: changeComesFirst).map(\.line).joined(separator: "\n")
    }

    private func changeComesFirst(_ lhs: Change, _ rhs: Change) -> Bool {
        let lhsPath = [lhs.reference.rootIndex] + lhs.reference.path
        let rhsPath = [rhs.reference.rootIndex] + rhs.reference.path
        if lhsPath == rhsPath {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhsPath.lexicographicallyPrecedes(rhsPath)
    }

    private struct FlattenedElement {
        let node: ComputerUseAXNode
        let reference: ComputerUseAccessibilityElementReference
        let matchKey: MatchKey
    }

    private func flatten(_ snapshot: ComputerUseAXSnapshot) -> [FlattenedElement] {
        snapshot.roots.enumerated().flatMap { rootIndex, root in
            flatten(node: root, rootIndex: rootIndex, path: [])
        }
    }

    private func flatten(
        node: ComputerUseAXNode,
        rootIndex: Int,
        path: [Int]
    ) -> [FlattenedElement] {
        let reference = ComputerUseAccessibilityElementReference(
            rootIndex: rootIndex,
            path: path,
            role: node.role,
            identifier: normalized(node.identifier)
        )
        let key: MatchKey
        if let identifier = reference.identifier {
            key = .identifier(role: node.role, identifier: identifier)
        } else {
            key = .path(
                rootIndex: rootIndex,
                path: path,
                role: node.role,
                subrole: normalized(node.subrole)
            )
        }
        let current = FlattenedElement(node: node, reference: reference, matchKey: key)
        let descendants = node.children.enumerated().flatMap { index, child in
            flatten(node: child, rootIndex: rootIndex, path: path + [index])
        }
        return [current] + descendants
    }

    private func renderLine(node: ComputerUseAXNode, id: Int, depth: Int) -> String {
        var components = ["\(id):", node.role]
        if let roleDescription = normalized(node.roleDescription) {
            components.append("(\(roleDescription))")
        }
        if let title = normalized(node.title) {
            components.append(quoted(title))
        }
        append(label: "Description", value: node.description, to: &components)
        append(label: "Help", value: node.help, to: &components)
        append(label: "ID", value: node.identifier, to: &components)
        if let value = normalized(node.value) {
            components.append("Value:")
            components.append(isSecure(node.role) ? "[redacted]" : quoted(value))
        }
        if node.isValueSettable {
            components.append("(value settable)")
        }
        if !node.isEnabled {
            components.append("(disabled)")
        }
        if !node.secondaryActions.isEmpty {
            components.append("Secondary Actions:")
            components.append(node.secondaryActions.joined(separator: ", "))
        }
        return String(repeating: "  ", count: depth) + components.joined(separator: " ")
    }

    private func append(label: String, value: String?, to components: inout [String]) {
        guard let value = normalized(value) else {
            return
        }
        components.append("\(label):")
        components.append(quoted(value))
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private func isSecure(_ role: String) -> Bool {
        role == "AXSecureTextField"
    }
}
