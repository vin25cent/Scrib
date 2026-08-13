#if os(macOS)
import Foundation
import ScribApplication
import ScribDomain

@MainActor
public final class UserDefaultsTeacherAuthorizationStore: TeacherAuthorizationStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "scrib.authorized-teachers.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func teachers() -> [Teacher] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([Teacher].self, from: data) else {
            return []
        }
        return decoded.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func teacher(named name: String) -> Teacher? {
        let normalized = Teacher(name: name).normalizedName
        return teachers().first { $0.normalizedName == normalized }
    }

    public func save(_ teacher: Teacher) throws {
        var values = teachers()
        if let index = values.firstIndex(where: {
            $0.id == teacher.id || $0.normalizedName == teacher.normalizedName
        }) {
            values[index] = teacher
        } else {
            values.append(teacher)
        }
        defaults.set(try encoder.encode(values), forKey: key)
    }
}
#endif
