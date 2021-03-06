# GPSInfo

GPSInfo is a small iOS app that displays information from the device’s GPS.

It displays:
 - Latitude and longitude (with horizontal accuracy)
 - Altitude (with vertical accuracy)
 - Estimated speed, in m/s and km/h
 - Closest (large) city

It does not require an Internet connectivity so it may be used in Airplane
mode, as long as the GPS is able to calibrate itself. This may require
launching the app and waiting for it to find the current location before
enabling Airplane mode.

The code is contained in a single Swift file, and does not use a nib or
storyboard file to create the interface.

## Build

In order to build, the project requires a `cities.plist` be present. This
property list contains a list of cities with their associated latitude and
longitude. It may be generated by running the Python script `update_cities.py`.

Once that is done, opening `GPSInfo.xcodeproj` should allow GPSInfo to be
built.
