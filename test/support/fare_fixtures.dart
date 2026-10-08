import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/domain/fare_service.dart';

/// The launch values of the six ride types (the same rows the database is seeded with).
const miniFare = FareConfig(
  cityMileage: 14, highwayMileage: 17, cityMaint: 10, highwayMaint: 8, minFare: 450, waitingPerMin: 8,
  roundTripWaitPerHour: 250, hourProfit: 500, extraKmRate: 60, extraHourRate: 560,
  profitPoints: [[0, 200], [5, 500], [10, 500], [20, 1200], [40, 1200], [100, 2400]],
);
const comfortFare = FareConfig(
  cityMileage: 11, highwayMileage: 14, cityMaint: 14, highwayMaint: 12, minFare: 490, waitingPerMin: 10,
  roundTripWaitPerHour: 300, hourProfit: 600, extraKmRate: 70, extraHourRate: 670,
  profitPoints: [[0, 240], [5, 600], [10, 600], [20, 1440], [40, 1440], [100, 2880]],
);
const xlFare = FareConfig(
  cityMileage: 10, highwayMileage: 12, cityMaint: 15, highwayMaint: 13, minFare: 560, waitingPerMin: 12,
  roundTripWaitPerHour: 400, hourProfit: 700, extraKmRate: 80, extraHourRate: 780,
  profitPoints: [[0, 280], [5, 700], [10, 700], [20, 1680], [40, 1680], [100, 3360]],
);
const bikeFare = FareConfig(
  cityMileage: 45, highwayMileage: 45, cityMaint: 3, highwayMaint: 3, minFare: 100, waitingPerMin: 3, maxKm: 40,
  profitPoints: [[0, 40], [5, 90], [10, 90], [20, 300], [40, 300], [100, 600]],
);
const loaderFare = FareConfig(
  cityMileage: 25, highwayMileage: 25, cityMaint: 6, highwayMaint: 6, minFare: 230, waitingPerMin: 5, maxKm: 50,
  loadingCharge: 100,
  profitPoints: [[0, 60], [5, 100], [10, 100], [20, 450], [40, 450], [100, 900]],
);

const testPackages = [
  HourlyPackage(id: 'p2', hours: 2, includedKm: 20, profitMultiplier: 1.1, sortOrder: 1),
  HourlyPackage(id: 'p4', hours: 4, includedKm: 40, profitMultiplier: 1.0, sortOrder: 2),
  HourlyPackage(id: 'p8', hours: 8, includedKm: 80, profitMultiplier: 0.9, sortOrder: 3),
  HourlyPackage(id: 'p12', hours: 12, includedKm: 120, profitMultiplier: 0.8, sortOrder: 4),
];

const testCategories = [
  RideCategory(code: 'car_mini', name: 'Car Mini', maxPassengers: 4, sortOrder: 1, isCar: true, fare: miniFare),
  RideCategory(code: 'car_comfort', name: 'Car Comfort', maxPassengers: 4, sortOrder: 2, isCar: true, fare: comfortFare),
  RideCategory(code: 'car_xl', name: 'Car XL', maxPassengers: 7, sortOrder: 3, isCar: true, fare: xlFare),
  RideCategory(code: 'bike', name: 'Bike', maxPassengers: 1, sortOrder: 4, fare: bikeFare),
  RideCategory(code: 'loader', name: 'Loader', maxPassengers: 1, sortOrder: 6, fare: loaderFare),
];