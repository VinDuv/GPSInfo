// Copyright 2018-2022 Vincent Duvert.
// Distributed under the terms of the MIT License.

import SwiftUI
import CoreLocation
import Dispatch

protocol GPSInfoAttribute {
    var name: String { get }
    func get(from infos: GPSInfos) -> String
}

struct KeyPathInfo<ValType>: GPSInfoAttribute {
    let name: String
    let ref: KeyPath<GPSInfos, ValType?>
    let fmt: (ValType) -> String

    init(_ name: String, _ ref: KeyPath<GPSInfos, ValType?>, _ fmt: @escaping (ValType) -> String) {
        self.name = name
        self.ref = ref
        self.fmt = fmt
    }

    init(_ name: String, _ ref: KeyPath<GPSInfos, ValType?>, _ fmt: String) {
        self.name = name
        self.ref = ref
        self.fmt = { String(format: fmt, $0 as! CVarArg) }
    }

    func get(from infos: GPSInfos) -> String {
        if let rawValue = infos[keyPath: ref] {
            return fmt(rawValue)
        }

        return "—"
    }
}

struct GPSInfos {
    var latitude: CLLocationDegrees?
    var longitude: CLLocationDegrees?
    var posAccuracy: CLLocationAccuracy?
    var altitude: CLLocationDistance?
    var altAccuracy: CLLocationAccuracy?
    var speed: CLLocationSpeed?
    var closestCity: String?

    var cityLocations: [(CLLocation, String)] = []
    var lastCityUpdateLocation: CLLocation?

    static let infoAttributes: [GPSInfoAttribute]  = [
        KeyPathInfo("Latitude", \.latitude, "%.6f N"),
        KeyPathInfo("Longitude", \.longitude, "%.6f E"),
        KeyPathInfo("Position Accuracy", \.posAccuracy, "± %.2f m"),
        KeyPathInfo("Altitude", \.altitude, "%.2f m"),
        KeyPathInfo("Altitude Accuracy", \.altAccuracy, "± %.2f m"),
        KeyPathInfo("Speed", \.speed, {
            let kmHSpeed = $0 * 3600 / 1000
            return String(format:"%.2f m/s (%.2f km/h)", $0, kmHSpeed)
        }),
        KeyPathInfo("Closest City", \.closestCity, { $0 })
    ]

    mutating func updateFrom(_ location: CLLocation) {
        if location.horizontalAccuracy >= 0 {
            let coordinates = location.coordinate
            self.latitude = coordinates.latitude
            self.longitude = coordinates.longitude
            self.posAccuracy = location.horizontalAccuracy

            if let prevLocation = lastCityUpdateLocation, closestCity != nil && prevLocation.distance(from: location) < 1000 {
                // No need to update the city
            } else {
                lastCityUpdateLocation = location
                updateClosestCity()
            }
        } else {
            self.latitude = nil
            self.longitude = nil
            self.posAccuracy = nil
            self.closestCity = nil
            self.lastCityUpdateLocation = nil
        }

        if location.verticalAccuracy >= 0 {
            self.altitude = location.altitude
            self.altAccuracy = location.verticalAccuracy
        }

        let msSpeed = location.speed
        if msSpeed >= 0 {
            self.speed = msSpeed
        } else {
            self.speed = nil
        }
    }

    private mutating func updateClosestCity() {
        guard let location = lastCityUpdateLocation else { return }
        guard !cityLocations.isEmpty else { return }

        var closestCity: String = "<More than 100 km away>"
        var closestCityDistance: Double = 100000.0

        for (candidateCityLocation, candidateCityName) in cityLocations {
            let distance = location.distance(from: candidateCityLocation)
            if distance < closestCityDistance {
                closestCity = candidateCityName
                closestCityDistance = distance
            }
        }

        self.closestCity = closestCity
    }

    func getFormatted() -> [(name: String, value: String)] {
        let mapped = Self.infoAttributes.map {(name: $0.name, value:$0.get(from: self))}
        return Array(mapped)
    }
}

class GPSInfoManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var formattedInfos: [(name: String, value: String)]
    var infos = GPSInfos()

    let locationManager = CLLocationManager()

    struct StoredCity: Decodable {
        var city: String
        var lat: Double
        var long: Double
    }
    
    override init() {
        formattedInfos = infos.getFormatted()
        super.init()

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        locationManager.activityType = .otherNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
        
        DispatchQueue.global(qos: .utility).async { [unowned self] in
            let url = Bundle.main.url(forResource: "cities", withExtension: "plist")!
            let data = try! Data(contentsOf: url)
            let decoded = try! PropertyListDecoder().decode([StoredCity].self, from: data)
            
            let locations = decoded.map { (CLLocation(latitude: $0.lat, longitude: $0.long), $0.city)}
            
            DispatchQueue.main.sync {
                infos.cityLocations = locations
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach { infos.updateFrom($0) }
        formattedInfos = infos.getFormatted()
    }
}


struct GPSInfoView: View {
    @EnvironmentObject var infoManager: GPSInfoManager

    var body: some View {
        List(infoManager.formattedInfos, id: \.name) { info in
            HStack {
                Text(info.name)
                Spacer()
                Text(info.value)
                    .foregroundColor(Color.gray)
                    .font(.system(size: 16).monospacedDigit())
            }
        }
    }
}

@main
struct GPSInfoApp: App {
    @StateObject private var infoManager = GPSInfoManager()

    var body: some Scene {
        WindowGroup {
            GPSInfoView().environmentObject(infoManager)
        }
    }
}
