import 'models.dart';

/// Comprehensive local database of major international and regional airports
/// to instantly resolve origin and destination coordinates for real-time tracking.
class AirportDatabase {
  static const Map<String, (double, double, String, String, String)> _data = {
    // Pakistan
    'ISB': (33.5497, 72.8277, 'Islamabad International Airport', 'Islamabad', 'Pakistan'),
    'KHI': (24.9065, 67.1608, 'Jinnah International Airport', 'Karachi', 'Pakistan'),
    'LHE': (31.5216, 74.4036, 'Allama Iqbal International Airport', 'Lahore', 'Pakistan'),
    'PEW': (33.9939, 71.5146, 'Bacha Khan International Airport', 'Peshawar', 'Pakistan'),
    'MUX': (30.2032, 71.4192, 'Multan International Airport', 'Multan', 'Pakistan'),
    'SKT': (32.5357, 74.3639, 'Sialkot International Airport', 'Sialkot', 'Pakistan'),
    'UET': (30.2514, 66.9381, 'Quetta International Airport', 'Quetta', 'Pakistan'),
    'FSD': (31.3653, 72.9947, 'Faisalabad International Airport', 'Faisalabad', 'Pakistan'),
    'RYK': (28.3842, 70.2797, 'Shaikh Zayed International Airport', 'Rahim Yar Khan', 'Pakistan'),
    'GWD': (25.2333, 62.3278, 'Gwadar International Airport', 'Gwadar', 'Pakistan'),
    'SKZ': (27.7222, 68.7906, 'Sukkur Airport', 'Sukkur', 'Pakistan'),
    'KDU': (35.3347, 75.5361, 'Skardu Airport', 'Skardu', 'Pakistan'),
    'GIL': (35.9189, 74.3333, 'Gilgit Airport', 'Gilgit', 'Pakistan'),

    // Middle East
    'DXB': (25.2532, 55.3657, 'Dubai International Airport', 'Dubai', 'UAE'),
    'DWC': (24.8960, 55.1614, 'Al Maktoum International Airport', 'Dubai', 'UAE'),
    'SHJ': (25.3286, 55.5172, 'Sharjah International Airport', 'Sharjah', 'UAE'),
    'AUH': (24.4330, 54.6511, 'Zayed International Airport', 'Abu Dhabi', 'UAE'),
    'DOH': (25.2731, 51.6081, 'Hamad International Airport', 'Doha', 'Qatar'),
    'JED': (21.6796, 39.1565, 'King Abdulaziz International Airport', 'Jeddah', 'Saudi Arabia'),
    'RUH': (24.9576, 46.6988, 'King Khalid International Airport', 'Riyadh', 'Saudi Arabia'),
    'DMM': (26.4712, 49.7979, 'King Fahd International Airport', 'Dammam', 'Saudi Arabia'),
    'MED': (24.5534, 39.7051, 'Prince Mohammad Bin Abdulaziz Airport', 'Medina', 'Saudi Arabia'),
    'MCT': (23.5933, 58.2844, 'Muscat International Airport', 'Muscat', 'Oman'),
    'KWI': (29.2266, 47.9689, 'Kuwait International Airport', 'Kuwait City', 'Kuwait'),
    'BAH': (26.2708, 50.6336, 'Bahrain International Airport', 'Manama', 'Bahrain'),
    'AMM': (31.7226, 35.9932, 'Queen Alia International Airport', 'Amman', 'Jordan'),
    'BEY': (33.8209, 35.4884, 'Beirut–Rafic Hariri International Airport', 'Beirut', 'Lebanon'),
    'IST': (41.2753, 28.7519, 'Istanbul Airport', 'Istanbul', 'Turkey'),
    'SAW': (40.8986, 29.3092, 'Sabiha Gokcen Airport', 'Istanbul', 'Turkey'),

    // Europe
    'LHR': (51.4700, -0.4543, 'Heathrow Airport', 'London', 'United Kingdom'),
    'LGW': (51.1537, -0.1821, 'Gatwick Airport', 'London', 'United Kingdom'),
    'MAN': (53.3537, -2.2750, 'Manchester Airport', 'Manchester', 'United Kingdom'),
    'CDG': (49.0097, 2.5479, 'Charles de Gaulle Airport', 'Paris', 'France'),
    'FRA': (50.0379, 8.5622, 'Frankfurt Airport', 'Frankfurt', 'Germany'),
    'MUC': (48.3537, 11.7860, 'Munich Airport', 'Munich', 'Germany'),
    'AMS': (52.3105, 4.7683, 'Amsterdam Airport Schiphol', 'Amsterdam', 'Netherlands'),
    'BCN': (41.2974, 2.0833, 'Josep Tarradellas Barcelona-El Prat', 'Barcelona', 'Spain'),
    'MAD': (40.4839, -3.5680, 'Adolfo Suarez Madrid–Barajas Airport', 'Madrid', 'Spain'),
    'FCO': (41.8003, 12.2389, 'Leonardo da Vinci–Fiumicino Airport', 'Rome', 'Italy'),
    'ZRH': (47.4582, 8.5555, 'Zurich Airport', 'Zurich', 'Switzerland'),
    'VIE': (48.1103, 16.5697, 'Vienna International Airport', 'Vienna', 'Austria'),

    // Asia & Americas
    'BOM': (19.0896, 72.8656, 'Chhatrapati Shivaji Maharaj Airport', 'Mumbai', 'India'),
    'DEL': (28.5562, 77.1000, 'Indira Gandhi International Airport', 'New Delhi', 'India'),
    'BKK': (13.6900, 100.7501, 'Suvarnabhumi Airport', 'Bangkok', 'Thailand'),
    'KTM': (27.6966, 85.3591, 'Tribhuvan International Airport', 'Kathmandu', 'Nepal'),
    'KUL': (2.7456, 101.7072, 'Kuala Lumpur International Airport', 'Kuala Lumpur', 'Malaysia'),
    'SIN': (1.3644, 103.9915, 'Singapore Changi Airport', 'Singapore', 'Singapore'),
    'HKG': (22.3080, 113.9185, 'Hong Kong International Airport', 'Hong Kong', 'Hong Kong'),
    'JFK': (40.6413, -73.7781, 'John F. Kennedy International Airport', 'New York', 'USA'),
    'ORD': (41.9742, -87.9073, 'O\'Hare International Airport', 'Chicago', 'USA'),
    'YYZ': (43.6777, -79.6248, 'Toronto Pearson International Airport', 'Toronto', 'Canada'),
  };

  static Airport? getByIata(String iata) {
    final code = iata.toUpperCase().trim();
    final d = _data[code];
    if (d == null) return null;
    return Airport(
      iata: code,
      icao: '',
      lat: d.$1,
      lon: d.$2,
      name: d.$3,
      city: d.$4,
      country: d.$5,
    );
  }
}
