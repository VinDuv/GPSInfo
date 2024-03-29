// Copyright 2018-2022 Vincent Duvert.
// Distributed under the terms of the MIT License.

import SwiftUI
import CoreLocation
import Dispatch

class GPSInfos: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latitude: CLLocationDegrees?
    @Published var longitude: CLLocationDegrees?
    @Published var posAccuracy: CLLocationAccuracy?
    @Published var altitude: CLLocationDistance?
    @Published var altAccuracy: CLLocationAccuracy?
    @Published var speed: CLLocationSpeed?
    @Published var closestCity: String?

    @Published var markerLocation: CLLocationCoordinate2D?
    @Published var markerDistance: CLLocationDistance?
    @Published var markerAltDiff: CLLocationDistance?

    @Published var canSetMarker = false

    let locationManager = CLLocationManager()
    var cityLocations: [(CLLocation, String)] = []
    var lastCityUpdateLocation: CLLocation?
    private var markerAltitude: CLLocationDistance = 0

    override init() {
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
                cityLocations = locations
            }
        }
    }

    func setMarker() {
        guard let latitude = self.latitude, let longitude = self.longitude,
        let altitude = self.altitude else {
            return
        }

        self.markerLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.markerAltitude = altitude
        self.markerDistance = 0
        self.markerAltDiff = 0
    }



    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach { self.updateFrom($0) }
    }

    private func updateFrom(_ location: CLLocation) {
        if location.horizontalAccuracy >= 0 {
            let coordinates = location.coordinate
            self.latitude = coordinates.latitude
            self.longitude = coordinates.longitude
            self.posAccuracy = location.horizontalAccuracy
            self.canSetMarker = true

            if let prevLocation = lastCityUpdateLocation, closestCity != nil && prevLocation.distance(from: location) < 1000 {
                // No need to update the city
            } else {
                lastCityUpdateLocation = location
                updateClosestCity()
            }

            if let markerLocation = markerLocation {
                self.markerDistance = location.distance(from: CLLocation(latitude: markerLocation.latitude, longitude: markerLocation.longitude))
                self.markerAltDiff = location.altitude - markerAltitude
            }
        } else {
            self.latitude = nil
            self.longitude = nil
            self.posAccuracy = nil
            self.closestCity = nil
            self.lastCityUpdateLocation = nil

            self.canSetMarker = false
            self.markerDistance = nil
            self.markerAltDiff = nil
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

    private func updateClosestCity() {
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

    struct StoredCity: Decodable {
        var city: String
        var lat: Double
        var long: Double
    }
}


struct GPSInfoRow<ValType>: View {
    let title: String
    @Binding var value: ValType?
    let fmt: (ValType) -> String

    init(_ title: String, _ value: Binding<ValType?>, _ fmt: @escaping (ValType) -> String) {
        self.title = title
        self._value = value
        self.fmt = fmt
    }

    init(_ title: String, _ value: Binding<ValType?>, _ fmt: String) {
        self.init(title, value) { String(format: fmt, $0 as! CVarArg) }
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(formatValue(value))
                .foregroundColor(Color.gray)
                .font(.system(size: 16).monospacedDigit())
        }
    }

    func formatValue(_ value: ValType?) -> String {
        if let value = value {
            return fmt(value)
        }

        return "—"
    }
}

struct GPSInfoView: View {
    @EnvironmentObject var infos: GPSInfos

    var body: some View {
        List {
            Section(header: Text("Current location")) {
                GPSInfoRow("Latitude", $infos.latitude, "%.6f N")
                GPSInfoRow("Longitude", $infos.longitude, "%.6f E")
                GPSInfoRow("Position Accuracy", $infos.posAccuracy, "± %.2f m")
                GPSInfoRow("Altitude", $infos.altitude, "%.2f m")
                GPSInfoRow("Altitude Accuracy", $infos.altAccuracy, "± %.2f m")
                GPSInfoRow("Speed", $infos.speed, {
                    let kmHSpeed = $0 * 3600 / 1000
                    return String(format:"%.2f m/s (%.2f km/h)", $0, kmHSpeed)
                })
                GPSInfoRow("Closest City", $infos.closestCity, { $0 })
            }
            Section(header: Text("Marker")) {
                GPSInfoRow("Location", $infos.markerLocation) {
                    return String(format:"%.4f N %.4f E", $0.latitude, $0.longitude)
                }
                GPSInfoRow("Distance", $infos.markerDistance, "%.2f m")
                GPSInfoRow("Altitude difference", $infos.markerAltDiff, "%.2f m")

                Button("Set marker") {
                    infos.setMarker()
                }.disabled(!infos.canSetMarker)
            }
        }
    }
}

@main
struct GPSInfoApp: App {
    @StateObject private var infos = GPSInfos()

    var body: some Scene {
        WindowGroup {
            GPSInfoView().environmentObject(infos)
        }
    }
}
