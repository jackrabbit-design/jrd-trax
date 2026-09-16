import Foundation
import SwiftData

@Model
public final class TaskStatus {
    @Attribute(.unique) public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
