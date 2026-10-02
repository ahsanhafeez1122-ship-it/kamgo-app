import 'package:supabase_flutter/supabase_flutter.dart';

enum ComplaintType {
  driver('DRIVER', 'Report a driver'),
  passenger('PASSENGER', 'Report a passenger'),
  ride('RIDE', 'Report a ride'),
  other('OTHER', 'Something else');

  const ComplaintType(this.code, this.label);
  final String code;
  final String label;
}

class SupportRepository {
  SupportRepository(this._client);
  final SupabaseClient _client;

  Future<void> submitComplaint(ComplaintType type, String description, {String? rideId}) =>
      _client.rpc('submit_complaint', params: {
        'p_type': type.code,
        'p_description': description,
        'p_ride_id': rideId,
      });
}
