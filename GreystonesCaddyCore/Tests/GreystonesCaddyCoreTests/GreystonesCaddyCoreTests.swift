import XCTest
@testable import GreystonesCaddyCore

final class GreystonesCaddyCoreTests: XCTestCase {
  func testLoadCourseJSON() throws {
    let course = try CourseLoader.loadGreystonesCourse()
    XCTAssertEqual(course.course.id, "greystones_gc")
    XCTAssertEqual(course.holes.count, 18)
    XCTAssertEqual(course.holes.first?.number, 1)
  }
}
