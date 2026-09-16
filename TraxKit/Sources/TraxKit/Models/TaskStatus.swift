import Foundation
import SwiftData

@Model
public final class TaskStatus {
    @Attribute(.unique) public var id: String
    public var projectId: String
    public var name: String

    public init(id: String, projectId: String, name: String) {
        self.id = id
        self.projectId = projectId
        self.name = name
    }
}
