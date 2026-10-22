import CoreGraphics

/// A box on a page whose text sits outside the linear flow.
struct PageBox: Equatable, Sendable {
    let pageIndex: Int
    let rect: CGRect
}

/// A picture on a page, saved as `name` in the item's images folder.
struct Figure: Equatable, Sendable {
    let pageIndex: Int
    let rect: CGRect
    let name: String
}
