import 'package:flutter_test/flutter_test.dart';
import 'package:okebori_pos/services/coordinates.dart';

void main() {
  test('reads coordinates from Google Maps links and plain text', () {
    expect(parseCoordinates('https://www.google.com/maps/place/Kitengela/@-1.4762,36.9614,15z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d-1.4741!4d36.9622'),
        (lat: -1.4741, lon: 36.9622)); // prefers the pin over the map centre
    expect(parseCoordinates('https://www.google.com/maps/@-1.2864,36.8172,17z'), (lat: -1.2864, lon: 36.8172));
    expect(parseCoordinates('https://maps.google.com/?q=-0.3031,36.0800'), (lat: -0.3031, lon: 36.08));
    expect(parseCoordinates(' -1.2864, 36.8172 '), (lat: -1.2864, lon: 36.8172));
    expect(parseCoordinates('https://maps.app.goo.gl/AbCdEf'), isNull); // short links hide the numbers
    expect(parseCoordinates('0,0'), isNull);
  });
}
