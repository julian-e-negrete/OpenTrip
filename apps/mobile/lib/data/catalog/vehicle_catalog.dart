import '../models/vehicle.dart';

/// A curated starting catalog — not exhaustive. The point of structuring
/// vehicle creation as brand -> model (instead of free text) is that a
/// model can carry a known [VehicleBleConnector], so picking "Kawasaki" +
/// "Z500 ABS" auto-wires the same connector this app already ships
/// (packages/kawasaki_rideology_ble). Adding a new connector later (see
/// docs/VEHICLE_CONNECTORS.md — CFMoto/Voge/etc. share a different
/// protocol) means adding entries here, not touching the vehicle-creation
/// UI at all.
class CatalogModel {
  final String name;
  final VehicleBleConnector connector;
  const CatalogModel(this.name, {this.connector = VehicleBleConnector.none});
}

class CatalogBrand {
  final String name;
  final List<CatalogModel> models;
  const CatalogBrand(this.name, this.models);
}

/// Shown at the end of every brand list. Picking it reveals free-text
/// brand/model fields instead of the dropdowns, so an unlisted vehicle
/// never blocks adding one — it just doesn't get a connector auto-wired.
const otherBrandName = 'Other / not listed';

// Deliberately spans more than sport/naked bikes — commuters, scooters,
// cruisers, adventure/dual-sport, touring, and a couple of electrics are
// what most riders (and most trips this app would ever record) actually
// ride, not just the sporty models that happen to dominate a first pass
// at a catalog like this. BLE connectivity stays limited to the Z500/
// Ninja 500 family regardless of how many models are listed here — see
// the connector comment below; adding a model here never implies BLE
// support unless it's explicitly wired to one.
const motorcycleBrands = <CatalogBrand>[
  CatalogBrand('Kawasaki', [
    // Only these four are wired to the Rideology BLE connector — the
    // packages/kawasaki_rideology_ble protocol was ported and verified
    // against the Z500/ER-500F platform specifically
    // (configs/z500_er500f.dart). Other Kawasaki models likely use a
    // different Rideology hardware/firmware generation with a different
    // frame format; claiming BLE support for them without verifying
    // that first would mean silently wrong telemetry, not just a
    // missing feature — see docs/VEHICLE_CONNECTORS.md.
    CatalogModel('Z500', connector: VehicleBleConnector.kawasakiRideology),
    CatalogModel('Z500 ABS', connector: VehicleBleConnector.kawasakiRideology),
    CatalogModel('Z500 SE', connector: VehicleBleConnector.kawasakiRideology),
    CatalogModel('Ninja 500', connector: VehicleBleConnector.kawasakiRideology),
    CatalogModel('Z650'),
    CatalogModel('Ninja 650'),
    CatalogModel('Versys 650'),
    CatalogModel('Versys-X 300'),
    CatalogModel('Z900'),
    CatalogModel('Z900RS'),
    CatalogModel('Ninja 1000SX'),
    CatalogModel('Vulcan S'),
    CatalogModel('Eliminator'),
    CatalogModel('W800'),
    CatalogModel('KLR650'),
    CatalogModel('KLX230'),
  ]),
  CatalogBrand('Honda', [
    CatalogModel('CB500F'),
    CatalogModel('CB500X'),
    CatalogModel('CBR500R'),
    CatalogModel('CB650R'),
    CatalogModel('CBR650R'),
    CatalogModel('NC750X'),
    CatalogModel('Rebel 500'),
    CatalogModel('Shadow Aero'),
    CatalogModel('Africa Twin'),
    CatalogModel('Gold Wing'),
    CatalogModel('CRF300L'),
    CatalogModel('Grom'),
    CatalogModel('PCX160'),
    CatalogModel('ADV160'),
  ]),
  CatalogBrand('Yamaha', [
    CatalogModel('MT-03'),
    CatalogModel('MT-07'),
    CatalogModel('MT-09'),
    CatalogModel('XSR900'),
    CatalogModel('YZF-R3'),
    CatalogModel('YZF-R7'),
    CatalogModel('Tenere 700'),
    CatalogModel('Tracer 9'),
    CatalogModel('Bolt'),
    CatalogModel('WR250R'),
    CatalogModel('NMAX 155'),
  ]),
  CatalogBrand('Suzuki', [
    CatalogModel('GSX-8S'),
    CatalogModel('GSX-8R'),
    CatalogModel('GSX-S750'),
    CatalogModel('SV650'),
    CatalogModel('V-Strom 650'),
    CatalogModel('DR650S'),
    CatalogModel('Boulevard C50'),
    CatalogModel('Burgman 400'),
    CatalogModel('Hayabusa'),
  ]),
  CatalogBrand('Ducati', [
    CatalogModel('Monster'),
    CatalogModel('Panigale V2'),
    CatalogModel('Panigale V4'),
    CatalogModel('Multistrada V4'),
    CatalogModel('DesertX'),
    CatalogModel('Diavel'),
    CatalogModel('Scrambler Icon'),
    CatalogModel('Scrambler Desert Sled'),
  ]),
  CatalogBrand('BMW Motorrad', [
    CatalogModel('F 900 R'),
    CatalogModel('F 900 XR'),
    CatalogModel('R 1250 GS'),
    CatalogModel('F 850 GS'),
    CatalogModel('R nineT'),
    CatalogModel('S 1000 RR'),
    CatalogModel('G 310 R'),
    CatalogModel('K 1600 GTL'),
    CatalogModel('C 400 GT'),
  ]),
  CatalogBrand('Triumph', [
    CatalogModel('Trident 660'),
    CatalogModel('Street Triple'),
    CatalogModel('Speed Twin 900'),
    CatalogModel('Scrambler 400 X'),
    CatalogModel('Tiger 900'),
    CatalogModel('Bonneville T120'),
    CatalogModel('Rocket 3'),
  ]),
  CatalogBrand('KTM', [
    CatalogModel('390 Duke'),
    CatalogModel('890 Duke'),
    CatalogModel('390 Adventure'),
    CatalogModel('790 Adventure'),
    CatalogModel('1290 Super Adventure'),
    CatalogModel('300 EXC'),
  ]),
  CatalogBrand('Harley-Davidson', [
    CatalogModel('Iron 883'),
    CatalogModel('Nightster'),
    CatalogModel('Street Bob'),
    CatalogModel('Road King'),
    CatalogModel('Fat Boy'),
    CatalogModel('Pan America 1250'),
    CatalogModel('LiveWire ONE'),
  ]),
  CatalogBrand('CFMoto', [
    CatalogModel('300SR'),
    CatalogModel('450SR'),
    CatalogModel('450MT'),
    CatalogModel('650MT'),
    CatalogModel('700CL-X'),
    CatalogModel('800NK'),
    CatalogModel('Papio'),
  ]),
  CatalogBrand('Royal Enfield', [
    CatalogModel('Hunter 350'),
    CatalogModel('Classic 350'),
    CatalogModel('Meteor 350'),
    CatalogModel('Himalayan'),
    CatalogModel('Interceptor 650'),
    CatalogModel('Continental GT 650'),
  ]),
  CatalogBrand('Indian Motorcycle', [
    CatalogModel('Scout'),
    CatalogModel('Chief'),
    CatalogModel('Chieftain'),
    CatalogModel('FTR'),
  ]),
  CatalogBrand('Vespa', [
    CatalogModel('Primavera 150'),
    CatalogModel('Sprint 150'),
    CatalogModel('GTS 300'),
  ]),
  CatalogBrand('Aprilia', [
    CatalogModel('RS 660'),
    CatalogModel('Tuono 660'),
    CatalogModel('SR GT'),
  ]),
  CatalogBrand('Moto Guzzi', [
    CatalogModel('V7'),
    CatalogModel('V85 TT'),
  ]),
  CatalogBrand('Zero Motorcycles', [
    CatalogModel('SR/F'),
    CatalogModel('DSR/X'),
    CatalogModel('S'),
  ]),
  CatalogBrand(otherBrandName, []),
];

const carBrands = <CatalogBrand>[
  CatalogBrand('Toyota', [
    CatalogModel('Corolla'),
    CatalogModel('Camry'),
    CatalogModel('RAV4'),
    CatalogModel('Yaris'),
    CatalogModel('Hilux'),
  ]),
  CatalogBrand('Honda', [
    CatalogModel('Civic'),
    CatalogModel('Accord'),
    CatalogModel('CR-V'),
    CatalogModel('Fit / Jazz'),
  ]),
  CatalogBrand('Ford', [
    CatalogModel('Fiesta'),
    CatalogModel('Focus'),
    CatalogModel('Mustang'),
    CatalogModel('F-150'),
    CatalogModel('Ranger'),
  ]),
  CatalogBrand('Chevrolet', [
    CatalogModel('Onix'),
    CatalogModel('Cruze'),
    CatalogModel('Camaro'),
    CatalogModel('Silverado'),
  ]),
  CatalogBrand('Volkswagen', [
    CatalogModel('Golf'),
    CatalogModel('Polo'),
    CatalogModel('Jetta'),
    CatalogModel('Tiguan'),
  ]),
  CatalogBrand('BMW', [
    CatalogModel('Series 1'),
    CatalogModel('Series 3'),
    CatalogModel('Series 5'),
    CatalogModel('X3'),
    CatalogModel('X5'),
  ]),
  CatalogBrand('Mercedes-Benz', [
    CatalogModel('A-Class'),
    CatalogModel('C-Class'),
    CatalogModel('E-Class'),
    CatalogModel('GLA'),
  ]),
  CatalogBrand('Audi', [
    CatalogModel('A3'),
    CatalogModel('A4'),
    CatalogModel('Q3'),
    CatalogModel('Q5'),
  ]),
  CatalogBrand('Nissan', [
    CatalogModel('Sentra'),
    CatalogModel('Versa'),
    CatalogModel('Altima'),
    CatalogModel('Kicks'),
  ]),
  CatalogBrand('Hyundai', [
    CatalogModel('Accent'),
    CatalogModel('Elantra'),
    CatalogModel('Tucson'),
    CatalogModel('Santa Fe'),
  ]),
  CatalogBrand('Kia', [
    CatalogModel('Rio'),
    CatalogModel('Forte'),
    CatalogModel('Sportage'),
    CatalogModel('Sorento'),
  ]),
  CatalogBrand('Tesla', [
    CatalogModel('Model 3'),
    CatalogModel('Model Y'),
    CatalogModel('Model S'),
    CatalogModel('Model X'),
  ]),
  CatalogBrand(otherBrandName, []),
];

/// Empty for bicycle/other — those types keep the old free-text name
/// field instead of a brand/model picker (see vehicles/add_vehicle_screen.dart).
List<CatalogBrand> brandsFor(VehicleType type) => switch (type) {
  VehicleType.motorcycle => motorcycleBrands,
  VehicleType.car => carBrands,
  VehicleType.bicycle || VehicleType.other => const [],
};
