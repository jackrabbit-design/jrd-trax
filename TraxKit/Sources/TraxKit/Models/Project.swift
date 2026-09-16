import Foundation
import SwiftData

@Model
public final class Project {
    @Attribute(.unique) public var id: String
    public var name: String
    public var colorHex: String
    public var workspaceURL: URL

    public init(id: String, name: String, colorHex: String, workspaceURL: URL) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.workspaceURL = workspaceURL
    }
}
