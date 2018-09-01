#!/usr/bin/env python3

import requests
import csv
import pathlib
import plistlib

URL = 'https://simplemaps.com/static/data/world-cities/basic/simplemaps-worldcities-basic.csv'
OUT_FILE = pathlib.Path(__file__).parent / "GPSInfo" / "cities.plist"

res = requests.get(URL)
res.raise_for_status()

reader = csv.reader(res.content.decode('utf-8').splitlines())
next(reader) # Ignore the header

cities = []

for row in reader:
    city, _, lat, long, _, _, _, _, _ = row
    
    cities.append({
        'city': city,
        'lat': float(lat),
        'long': float(long),
    })
    
with OUT_FILE.open('wb') as out_file:
    plistlib.dump(cities, out_file, fmt=plistlib.FMT_BINARY)