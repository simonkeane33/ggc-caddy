import Foundation

public enum CourseLoader {
  public static func loadGreystonesCourse() throws -> CourseBundle {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "greystones_course", withExtension: "json") else {
      throw NSError(domain: "GreystonesCaddyCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing greystones_course.json in module resources"])
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CourseBundle.self, from: data)
  }
}
