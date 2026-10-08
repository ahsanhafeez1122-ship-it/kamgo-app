import 'package:shared_preferences/shared_preferences.dart';

/// Which side of the app this device opens: Passenger mode or Driver mode.
/// Only drivers can be in Driver mode; everyone else is always a passenger.
const _passengerModeKey = 'passenger_mode';

bool isPassengerMode(SharedPreferences prefs) => prefs.getBool(_passengerModeKey) ?? false;

Future<void> setPassengerMode(SharedPreferences prefs, bool value) =>
    prefs.setBool(_passengerModeKey, value);
