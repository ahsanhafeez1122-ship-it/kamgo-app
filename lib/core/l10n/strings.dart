import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_providers.dart';

/// App language (English default, Urdu optional). Persisted on the device.
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class LocaleNotifier extends Notifier<Locale> {
  static const _key = 'app_locale';

  @override
  Locale build() => Locale(ref.read(sharedPrefsProvider).getString(_key) ?? 'en');

  void set(String code) {
    ref.read(sharedPrefsProvider).setString(_key, code);
    state = Locale(code);
  }
}

extension Tr on BuildContext {
  /// Looks up [key] for the current locale, falling back to English, then
  /// to the key itself. `{x}` placeholders are filled from [args].
  String tr(String key, [Map<String, Object?> args = const {}]) {
    final lang = Localizations.maybeLocaleOf(this)?.languageCode ?? 'en';
    var s = (lang == 'ur' ? _ur[key] : null) ?? _en[key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

const _en = <String, String>{
  'nav.home': 'Home',
  'nav.rides': 'My Rides',
  'nav.alerts': 'Alerts',
  'nav.profile': 'Profile',
  'nav.dashboard': 'Dashboard',
  'nav.earnings': 'Earnings',
  'home.where': 'Where are you going?',
  'home.pickup': 'Pickup Location',
  'home.destination': 'Destination',
  'home.passengers': 'Passengers',
  'home.offer': 'Your Offer',
  'home.find': 'Find a Ride',
  'home.recent': 'Recent Destinations',
  'home.online': 'Online Drivers',
  'home.popular': 'Popular Route',
  'home.in_adda': 'in {city} adda',
  'home.active_ride': 'You have a ride in progress',
  'home.active_request': 'Your request is live',
  'home.open': 'Open',
  'home.rate_last': 'How was your last ride?',
  'finding.title': 'Finding drivers near you',
  'finding.subtitle': 'Sending your offer to drivers of this ride type',
  'finding.cancel': 'Cancel Request',
  'finding.sent': 'Request sent',
  'offers.responded': '{n} drivers responded',
  'offers.one_responded': '1 driver responded',
  'offers.accepted': 'Accepted your offer',
  'offers.counter': 'Counter Offer',
  'offers.select': 'Select',
  'offers.waiting': 'Waiting for more drivers',
  'ride.confirmed': 'Ride confirmed',
  'ride.arriving': 'Driver is on the way',
  'ride.started': 'Ride in progress',
  'ride.completed': 'Ride completed',
  'ride.call': 'Call',
  'ride.share': 'Share Trip',
  'ride.cancel': 'Cancel',
  'ride.help': 'Help',
  'ride.start': 'Start Ride',
  'ride.on_way': "I'm on my way",
  'ride.complete': 'Complete Ride',
  'ride.rate': 'Rate your driver',
  'ride.rate_passenger': 'Rate your passenger',
  'ride.submit': 'Submit',
  'ride.done': 'Done',
  'driver.online': 'You are online',
  'driver.offline': 'You are offline',
  'driver.go_online': 'Go online to receive ride requests',
  'driver.adda': '{city} adda',
  'driver.requests': 'Ride requests',
  'driver.return': 'Return ride opportunities',
  'driver.no_requests': 'No requests right now',
  'driver.accept': 'Accept {fare}',
  'driver.counter': 'Counter Offer',
  'driver.reject': 'Reject',
  'driver.commission_due': 'Commission due',
  'common.retry': 'Retry',
  'common.no_internet': 'No Internet Connection',
  'common.connection_lost': 'Connection lost — showing saved data',
  'profile.language': 'Language',
  'profile.help': 'Help & Support',
};

const _ur = <String, String>{
  'nav.home': 'ہوم',
  'nav.rides': 'میری رائیڈز',
  'nav.alerts': 'اطلاعات',
  'nav.profile': 'پروفائل',
  'nav.dashboard': 'ڈیش بورڈ',
  'nav.earnings': 'کمائی',
  'home.where': 'آپ کہاں جا رہے ہیں؟',
  'home.pickup': 'پک اپ',
  'home.destination': 'منزل',
  'home.passengers': 'مسافر',
  'home.offer': 'آپ کا کرایہ',
  'home.find': 'رائیڈ تلاش کریں',
  'home.recent': 'حالیہ منزلیں',
  'home.online': 'آن لائن ڈرائیور',
  'home.popular': 'مقبول روٹ',
  'home.in_adda': '{city} اڈا میں',
  'home.active_ride': 'آپ کی رائیڈ جاری ہے',
  'home.active_request': 'آپ کی درخواست جاری ہے',
  'home.open': 'کھولیں',
  'home.rate_last': 'آپ کی پچھلی رائیڈ کیسی رہی؟',
  'finding.title': 'قریبی ڈرائیور تلاش کیے جا رہے ہیں',
  'finding.subtitle': '{city} اڈا میں آپ کی پیشکش بھیجی جا رہی ہے',
  'finding.cancel': 'درخواست منسوخ کریں',
  'finding.sent': 'درخواست بھیج دی گئی',
  'offers.responded': '{n} ڈرائیوروں نے جواب دیا',
  'offers.one_responded': '1 ڈرائیور نے جواب دیا',
  'offers.accepted': 'آپ کا کرایہ قبول',
  'offers.counter': 'جوابی پیشکش',
  'offers.select': 'منتخب کریں',
  'offers.waiting': 'مزید ڈرائیوروں کا انتظار',
  'ride.confirmed': 'رائیڈ کنفرم',
  'ride.arriving': 'ڈرائیور آ رہا ہے',
  'ride.started': 'رائیڈ جاری ہے',
  'ride.completed': 'رائیڈ مکمل',
  'ride.call': 'کال',
  'ride.share': 'سفر شیئر کریں',
  'ride.cancel': 'منسوخ',
  'ride.help': 'مدد',
  'ride.start': 'رائیڈ شروع کریں',
  'ride.on_way': 'میں آ رہا ہوں',
  'ride.complete': 'رائیڈ مکمل کریں',
  'ride.rate': 'ڈرائیور کو ریٹ کریں',
  'ride.rate_passenger': 'مسافر کو ریٹ کریں',
  'ride.submit': 'جمع کریں',
  'ride.done': 'ٹھیک ہے',
  'driver.online': 'آپ آن لائن ہیں',
  'driver.offline': 'آپ آف لائن ہیں',
  'driver.go_online': 'رائیڈ کی درخواستیں لینے کے لیے آن لائن ہوں',
  'driver.adda': '{city} اڈا',
  'driver.requests': 'رائیڈ کی درخواستیں',
  'driver.return': 'واپسی کی سواریاں',
  'driver.no_requests': 'ابھی کوئی درخواست نہیں',
  'driver.accept': '{fare} قبول',
  'driver.counter': 'جوابی پیشکش',
  'driver.reject': 'رد کریں',
  'driver.commission_due': 'واجب کمیشن',
  'common.retry': 'دوبارہ کوشش',
  'common.no_internet': 'انٹرنیٹ دستیاب نہیں',
  'common.connection_lost': 'کنکشن منقطع — محفوظ ڈیٹا دکھایا جا رہا ہے',
  'profile.language': 'زبان',
  'profile.help': 'مدد اور سپورٹ',
};
