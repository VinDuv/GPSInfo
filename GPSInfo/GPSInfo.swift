// Copyright 2018-2022 Vincent Duvert.
// Distributed under the terms of the MIT License.

import UIKit
import CoreLocation
import Dispatch

enum DisplayedInfo: String {
    case latitude = "Latitude"
    case longitude = "Longitude"
    case posAccuracy = "Position Accuracy"
    case altitude = "Altitude"
    case altAccurracy = "Altitude Accuracy"
    case speed = "Speed"
    case closestCity = "Closest City"
}

extension DisplayedInfo {
    static var allCases : [DisplayedInfo] = [.latitude, .longitude, posAccuracy, .altitude, .altAccurracy, .speed, .closestCity]
}

typealias InfoDict = [DisplayedInfo: String]

class GPSInfoDisplay: NSObject, UITableViewDataSource {
    var infoDict: InfoDict = [:]
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        precondition(section == 0)

        return DisplayedInfo.allCases.count
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
        
        let info = DisplayedInfo.allCases[indexPath.row]
        
        cell.textLabel?.text = info.rawValue
        
        cell.detailTextLabel?.text = infoDict[info] ?? "—"
        
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
    var updateCallback: ((InfoDict) -> ())?
    var lastCityUpdateLocation: CLLocation?
    var lastCityFound: String?
    var cityLocations: [(CLLocation, String)] = []
    
    struct StoredCity: Decodable {
        var city: String
        var lat: Double
        var long: Double
    }

    
    func start() {
        if CLLocationManager.authorizationStatus() == .notDetermined {
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
            
            let tempLocations = decoded.map { (CLLocation(latitude: $0.lat, longitude: $0.long), $0.city)}
            
            DispatchQueue.main.sync {
                self.cityLocations = tempLocations
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach { self.processLocation($0) }
    }
    
    func processLocation(_ location: CLLocation) {
        var infoDict: InfoDict = [:]
        
        if location.horizontalAccuracy >= 0 {
            let coordinates = location.coordinate
            infoDict[.latitude] = String(format:"%.6f N", coordinates.latitude)
            infoDict[.longitude] = String(format:"%.6f E", coordinates.longitude)
            infoDict[.posAccuracy] = String(format:"± %.2f m", location.horizontalAccuracy)
            
            if let prevLocation = lastCityUpdateLocation, lastCityFound != nil && prevLocation.distance(from: location) < 1000 {
                // No need to update the city
            } else {
                lastCityUpdateLocation = location
                updateClosestCity()
            }
            
            infoDict[.closestCity] = lastCityFound
        }
        
        if location.verticalAccuracy >= 0 {
            infoDict[.altitude] = String(format:"%.2f m", location.altitude)
            infoDict[.altAccurracy] = String(format:"± %.2f m", location.verticalAccuracy)
        }
        
        let msSpeed = location.speed
        if msSpeed >= 0 {
            let kmSpeed = msSpeed * 3600 / 1000
            infoDict[.speed] = String(format:"%.2f m/s (%.2f km/h)", msSpeed, kmSpeed)
        }
        
        updateCallback?(infoDict)
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
        
        lastCityFound = closestCity
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
        
        locationUpdater.updateCallback = { infoDict in
            infoList.infoDict = infoDict
            tableView.reloadData()
        }
        locationUpdater.start()
        
        window.makeKeyAndVisible()
        
        return true
    }
}

