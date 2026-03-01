import Foundation

public class CourseLoader {
  public static var bundle: Bundle {
    #if DEBUG
    // In local development, Bundle.module is sometimes unreliable in nested projects.
    // Try to find the bundle via class lookup first for robustness.
    let bundleName = "GreystonesCaddyCore_GreystonesCaddyCore.bundle"
    if let path = Bundle.main.path(forResource: bundleName, ofType: nil) {
        return Bundle(path: path) ?? .module
    }
    #endif
    return .module
  }
  
  public static func loadGreystonesCourse() throws -> CourseBundle {
    let b = self.bundle
    guard let url = b.url(forResource: "greystones_course", withExtension: "json") else {
        throw NSError(domain: "GreystonesCaddyCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing greystones_course.json in bundle resources"])
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CourseBundle.self, from: data)
  }
}
