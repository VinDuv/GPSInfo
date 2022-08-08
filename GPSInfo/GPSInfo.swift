// Copyright 2018-2022 Vincent Duvert.
// Distributed under the terms of the MIT License.

import UIKit
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

struct GPSInfos: Sequence {
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

    func makeIterator() -> AnyIterator<(String, String)> {
        let mapped = Self.infoAttributes.map {($0.name, $0.get(from: self))}
        return AnyIterator(mapped.makeIterator())
    }
}

class GPSInfoDisplay: NSObject, UITableViewDataSource {
    var infos = GPSInfos()
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        precondition(section == 0)

        return GPSInfos.infoAttributes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = indexPath.section
        precondition(section == 0)
        
        let cellIdentifier = "GPSInfoCell"
        
        let cell: UITableViewCell
        if let reusableCell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) {
            cell = reusableCell
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: cellIdentifier)
            
            let descriptor = cell.detailTextLabel!.font.fontDescriptor
            let settings = [[UIFontDescriptor.FeatureKey.featureIdentifier: kNumberSpacingType, UIFontDescriptor.FeatureKey.typeIdentifier: kMonospacedNumbersSelector]]
            let attributes = [UIFontDescriptor.AttributeName.featureSettings: settings]
            let newDescriptor = descriptor.addingAttributes(attributes)
            cell.detailTextLabel!.font = UIFont(descriptor: newDescriptor, size: 0)
        }
        
        let infoAttr = GPSInfos.infoAttributes[indexPath.row]
        cell.textLabel?.text = infoAttr.name
        cell.detailTextLabel?.text = infoAttr.get(from: infos)
        
        return cell
    }
    
    private func getMapTableCell(for tableView: UITableView) -> UITableViewCell  {
        let cellIdentifier = "GPSMapCell"
        
        let cell: UITableViewCell
        if let reusableCell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) {
            cell = reusableCell
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: cellIdentifier)
        }
        
        cell.textLabel?.text = "View Map"
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 0 {
            return nil
        }
        
        return indexPath
    }
}

class LocationUpdater: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    var updateCallback: ((CLLocation) -> ())?
    var citiesLoadedCallback: (([(CLLocation, String)]) -> ())?
    
    struct StoredCity: Decodable {
        var city: String
        var lat: Double
        var long: Double
    }
    
    func start() {
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
                citiesLoadedCallback?(locations)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach { updateCallback?($0) }
    }
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var viewController: UIViewController!
    let locationUpdater = LocationUpdater()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        
        self.viewController = UIViewController(nibName: nil, bundle: nil)
        window.rootViewController = self.viewController
        
        let parentView = self.viewController.view!
        parentView.backgroundColor = UIColor.groupTableViewBackground
        
        let infoList = GPSInfoDisplay()
        
        let tableView = UITableView(frame: .null, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.allowsSelection = false
        tableView.dataSource = infoList
        
        parentView.addSubview(tableView)
        
        tableView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.bottomAnchor).isActive = true
        tableView.leftAnchor.constraint(equalTo: parentView.leftAnchor).isActive = true
        tableView.rightAnchor.constraint(equalTo: parentView.rightAnchor).isActive = true
        
        parentView.addSubview(tableView)
        
        locationUpdater.updateCallback = {
            infoList.infos.updateFrom($0)
            tableView.reloadData()
        }
        locationUpdater.citiesLoadedCallback = {
            infoList.infos.cityLocations = $0
        }
        locationUpdater.start()

        window.makeKeyAndVisible()
        
        return true
    }
}

