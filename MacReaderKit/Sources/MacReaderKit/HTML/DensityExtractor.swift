import Foundation

/// Finds the container of the article by composite text density (Sun, Song and Liao, SIGIR 2011): prose is long
/// text under few tags and few links, so the node whose children are densest as a group holds the article.
enum DensityExtractor {
    /// Containers with less text than this are not candidates.
    static let minimumCharacters = 250

    private struct Counts {
        var characters = 0
        var tags = 0
        var linkCharacters = 0
        var linkTags = 0
    }

    private struct Candidate {
        let node: HTMLNode
        let characters: Int
        let densitySum: Double
    }

    static func bestNode(in root: HTMLNode) -> HTMLNode? {
        let total = counts(of: root)
        let linkRatio = total.characters == 0 ? 0 : Double(total.linkCharacters) / Double(total.characters)
        var candidates: [Candidate] = []
        _ = visit(root, linkRatio: linkRatio, isRoot: true, into: &candidates)
        return candidates.filter { $0.characters >= minimumCharacters }.max { $0.densitySum < $1.densitySum }?.node
    }

    private static func counts(of node: HTMLNode) -> Counts {
        if node.isText { return Counts(characters: node.textLength) }
        var counts = node.children.reduce(into: Counts()) { total, child in
            let childCounts = counts(of: child)
            total.characters += childCounts.characters
            total.tags += childCounts.tags
            total.linkCharacters += childCounts.linkCharacters
            total.linkTags += childCounts.linkTags
        }
        counts.tags += 1
        if node.tag == "a" {
            counts.linkCharacters = counts.characters
            counts.linkTags = 1
        }
        return counts
    }

    /// Composite text density of a node.
    private static func density(_ counts: Counts, linkRatio: Double) -> Double {
        let characters = Double(max(counts.characters, 1))
        let tags = Double(max(counts.tags, 1))
        let linkCharacters = Double(max(counts.linkCharacters, 1))
        let linkTags = Double(max(counts.linkTags, 1))
        let plainCharacters = Double(max(counts.characters - counts.linkCharacters, 1))
        let base = log(characters * linkCharacters / plainCharacters + linkRatio * characters + M_E)
        return characters / tags * (log(characters * tags / (linkCharacters * linkTags)) / log(base))
    }

    private static func visit(_ node: HTMLNode, linkRatio: Double, isRoot: Bool, into candidates: inout [Candidate]) -> (counts: Counts, density: Double) {
        guard !node.isText else { return (Counts(characters: node.textLength), 0) }
        var childCounts = Counts()
        var densitySum = 0.0
        for child in node.children {
            let result = visit(child, linkRatio: linkRatio, isRoot: false, into: &candidates)
            childCounts.characters += result.counts.characters
            childCounts.tags += result.counts.tags
            childCounts.linkCharacters += result.counts.linkCharacters
            childCounts.linkTags += result.counts.linkTags
            if !child.isText { densitySum += result.density }
        }
        var own = childCounts
        own.tags += 1
        if node.tag == "a" {
            own.linkCharacters = own.characters
            own.linkTags = 1
        }
        if !isRoot, node.tag != "body", node.tag != "html" {
            candidates.append(Candidate(node: node, characters: own.characters, densitySum: densitySum))
        }
        return (own, density(own, linkRatio: linkRatio))
    }
}
