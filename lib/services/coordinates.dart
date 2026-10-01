/// Reads latitude/longitude from what people usually paste: a Google Maps
/// link (…/@-1.2864,36.8172,15z, …!3d-1.28!4d36.81, …?q=-1.28,36.81)
/// or plain "-1.2864, 36.8172". Returns null if nothing valid is found.
({double lat, double lon})? parseCoordinates(String input) {
  final text = Uri.decodeFull(input.trim());
  const number = r'(-?\d{1,3}(?:\.\d+)?)';
  final patterns = [
    RegExp('!3d$number!4d$number'), // exact place pin
    RegExp('@$number,\\s*$number'), // map centre
    RegExp('[?&](?:q|query|ll|destination)=$number,\\s*$number'),
    RegExp('^$number\\s*,\\s*$number\$'), // plain coordinates
  ];
  for (final pattern in patterns) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    final lat = double.parse(m.group(1)!), lon = double.parse(m.group(2)!);
    if (lat.abs() <= 90 && lon.abs() <= 180 && !(lat == 0 && lon == 0)) return (lat: lat, lon: lon);
  }
  return null;
}
