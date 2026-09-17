import Testing
import Foundation
@testable import KantataAPI

@Suite("DTO decoding")
struct DTODecodingTests {
    @Test("WorkspaceDTO decodes")
    func workspace() throws {
        let json = #"{"id": "w1", "title": "Acme Redesign"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(WorkspaceDTO.self, from: json)
        #expect(dto.id == "w1")
        #expect(dto.title == "Acme Redesign")
    }

    @Test("TaskStatusDTO decodes")
    func taskStatus() throws {
        let json = #"{"id": "s1", "name": "In Progress"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TaskStatusDTO.self, from: json)
        #expect(dto.id == "s1")
        #expect(dto.name == "In Progress")
    }

    @Test("StatusSetDTO decodes with nested status ids and a workspace id")
    func statusSet() throws {
        let json = #"{"id": "set1", "name": "Default", "workspace_id": "w1", "status_ids": ["s1", "s2"]}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StatusSetDTO.self, from: json)
        #expect(dto.id == "set1")
        #expect(dto.workspaceId == "w1")
        #expect(dto.statusIds == ["s1", "s2"])
    }

    @Test("AssignmentDTO decodes")
    func assignment() throws {
        let json = #"{"id": "a1", "story_id": "st1", "workspace_id": "w1"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(AssignmentDTO.self, from: json)
        #expect(dto.storyId == "st1")
        #expect(dto.workspaceId == "w1")
    }

    @Test("DailyScheduledHourDTO decodes")
    func dailyScheduledHour() throws {
        let json = #"{"id": "d1", "story_id": "st1", "date": "2026-09-16", "hours": 1.5}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(DailyScheduledHourDTO.self, from: json)
        #expect(dto.date == "2026-09-16")
        #expect(dto.hours == 1.5)
    }

    @Test("StoryDTO decodes with optional fields")
    func story() throws {
        let json = #"{"id": "st1", "workspace_id": "w1", "title": "Design homepage", "priority": "high", "due_date": "2026-09-20", "status_id": "s1"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StoryDTO.self, from: json)
        #expect(dto.title == "Design homepage")
        #expect(dto.priority == "high")
        #expect(dto.dueDate == "2026-09-20")
    }

    @Test("StoryDTO decodes when optional fields are missing")
    func storyMinimal() throws {
        let json = #"{"id": "st2", "workspace_id": "w1", "title": "Untitled"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StoryDTO.self, from: json)
        #expect(dto.priority == nil)
        #expect(dto.dueDate == nil)
        #expect(dto.statusId == nil)
    }

    @Test("TimeEntryDTO decodes")
    func timeEntry() throws {
        let json = #"{"id": "te1", "story_id": "st1", "date": "2026-09-16", "hours": 0.75}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TimeEntryDTO.self, from: json)
        #expect(dto.hours == 0.75)
    }

    @Test("UserDTO decodes")
    func user() throws {
        let json = #"{"id": "u1", "full_name": "Chris K", "email": "ck@jumpingjackrabbit.com"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(UserDTO.self, from: json)
        #expect(dto.fullName == "Chris K")
        #expect(dto.email == "ck@jumpingjackrabbit.com")
    }

    @Test("StoryStateChangeDTO decodes")
    func storyStateChange() throws {
        let json = #"{"id": "c1", "story_id": "st1", "status_id": "s2"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(StoryStateChangeDTO.self, from: json)
        #expect(dto.storyId == "st1")
        #expect(dto.statusId == "s2")
    }
}
