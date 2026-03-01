import Foundation
import GreystonesCaddyCore

public struct CourseDataImporter {
    public struct Row {
        public var hole: Int
        public var teeBlueLat: Double?
        public var teeBlueLng: Double?
        public var teeGreenLat: Double?
        public var teeGreenLng: Double?
        public var teeRedLat: Double?
        public var teeRedLng: Double?
        public var greenFrontLat: Double?
        public var greenFrontLng: Double?
        public var greenCenterLat: Double?
        public var greenCenterLng: Double?
        public var greenBackLat: Double?
        public var greenBackLng: Double?
    }

    public static func importCSV(_ csvContent: String) throws {
        let lines = csvContent.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }
        
        // Skip header
        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ",")
            if cols.count < 13 { continue }
            
            let holeStr = cols[0].trimmingCharacters(in: .whitespaces)
            guard let holeNum = Int(holeStr) else { continue }
            
            func d(_ index: Int) -> Double? {
                guard index < cols.count else { return nil }
                let s = cols[index].trimmingCharacters(in: .whitespaces)
                return Double(s)
            }
            
            // CSV columns mapping (based on Sun 22:29 GMT file):
            // 0: Hole Number
            // 1: Blue Tees Lat
            // 2: Blue Tee Long
            // 3: Blue Tee Altitude (m)
            // 4: Green Tee Lat
            // 5: Green Tee Long
            // 6: Green Tee Altitude (m)
            // 7: Green Front Lat
            // 8: Green Front Long
            // 9: Green Front Altitude (m)
            // 10: Green Centre Lat
            // 11: Green Centre Long
            // 12: Green Centre Altitude
            // 13: Green Back Lat
            // 14: Green Back Long
            // 15: Green Back Altitude
            
            // Upsert Green Locations (Center is required for the entry)
            if let cLat = d(10), let cLng = d(11) {
                var altitude = d(12)
                // Manual correction for Hole 15 altitude if it matches the erroneous latitude value
                if holeNum == 15 && altitude == 53.1332821 {
                    altitude = 21.3514823
                }

                try GCDB.shared.upsertGreenCenter(
                    holeNumber: holeNum,
                    centerLat: cLat,
                    centerLng: cLng,
                    centerAlt: altitude,
                    frontLat: d(7),
                    frontLng: d(8),
                    frontAlt: d(9),
                    backLat: d(13),
                    backLng: d(14),
                    backAlt: d(15)
                )
            }
            
            // Upsert Tee Locations
            // Blue
            if let lat = d(1), let lng = d(2) {
                try GCDB.shared.upsertTeeLocation(holeNumber: holeNum, tee: .blue, lat: lat, lng: lng, alt: d(3))
            }
            // Green (Tee)
            if let lat = d(4), let lng = d(5) {
                try GCDB.shared.upsertTeeLocation(holeNumber: holeNum, tee: .green, lat: lat, lng: lng, alt: d(6))
            }
        }
    }
}
