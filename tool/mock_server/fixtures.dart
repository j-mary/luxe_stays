// Fixture data for the LuxeStays mock back end.
//
// Everything the four "vendors" return is derived from this file, which means
// one edit changes the CRS, the CMS and the media library consistently - the
// same discipline a real integration environment needs.

class MockHotel {
  const MockHotel({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    required this.destinationId,
    required this.stars,
    required this.currency,
    required this.baseNightlyMinor,
    required this.latitude,
    required this.longitude,
    required this.headline,
    required this.body,
    required this.signature,
    required this.amenities,
    required this.highlights,
    required this.tags,
    required this.address,
  });

  final String id;
  final String name;
  final String city;
  final String country;
  final String destinationId;
  final int stars;
  final String currency;
  final int baseNightlyMinor;
  final double latitude;
  final double longitude;
  final String headline;
  final String body;
  final String signature;
  final List<String> amenities;
  final List<String> highlights;
  final List<String> tags;
  final String address;
}

const List<MockHotel> mockHotels = <MockHotel>[
  MockHotel(
    id: 'H-PAR-001',
    name: 'Maison Rivoli',
    city: 'Paris',
    country: 'FR',
    destinationId: 'PAR',
    stars: 5,
    currency: 'EUR',
    baseNightlyMinor: 78000,
    latitude: 48.8606,
    longitude: 2.3376,
    address: '14 Rue de Rivoli, 75001 Paris',
    headline: 'A courtyard hotel one street from the Tuileries',
    body:
        'Eighteen rooms behind a Haussmannian façade, each with parquet '
        'restored from the original 1867 build. The courtyard bar serves until '
        'one, and the concierge holds standing reservations at three of the '
        'four restaurants you were going to ask about.',
    signature:
        'Private after-hours viewing at the Musée de l\'Orangerie, '
        'arranged with 48 hours\' notice.',
    amenities: <String>['Spa', 'Bar', 'Concierge', 'Room service', 'Wi-Fi'],
    highlights: <String>[
      'Two minutes from the Tuileries',
      'Michelin-starred dining on site',
      'Rooms from 32 m²',
    ],
    tags: <String>['city', 'design', 'romantic'],
  ),
  MockHotel(
    id: 'H-PAR-002',
    name: 'Hôtel Sévigné',
    city: 'Paris',
    country: 'FR',
    destinationId: 'PAR',
    stars: 4,
    currency: 'EUR',
    baseNightlyMinor: 42000,
    latitude: 48.8566,
    longitude: 2.3622,
    address: '9 Rue de Sévigné, 75004 Paris',
    headline: 'Quiet Marais rooms above a courtyard garden',
    body:
        'A converted hôtel particulier on a street the tour groups have not '
        'found. Breakfast is served in the garden from April, and the top-floor '
        'suites look across the rooftops to Notre-Dame.',
    signature: 'Morning pastry run with the head chef to his own boulangerie.',
    amenities: <String>['Garden', 'Breakfast', 'Wi-Fi', 'Concierge'],
    highlights: <String>['Marais location', 'Garden breakfast', 'Family rooms'],
    tags: <String>['city', 'family'],
  ),
  MockHotel(
    id: 'H-KYO-001',
    name: 'Ryokan Sanjo',
    city: 'Kyoto',
    country: 'JP',
    destinationId: 'KYO',
    stars: 5,
    currency: 'USD',
    baseNightlyMinor: 96000,
    latitude: 35.0094,
    longitude: 135.7681,
    address: '3-chōme Sanjō, Nakagyō-ku, Kyoto',
    headline: 'Eleven tatami suites and a cedar bath fed by its own spring',
    body:
        'The family has run this house for four generations. Dinner is '
        'kaiseki, served in your room, and the garden is lit by hand each '
        'evening at dusk.',
    signature:
        'Dawn tea ceremony in the garden pavilion with the eleventh-'
        'generation host.',
    amenities: <String>['Onsen', 'Kaiseki dining', 'Garden', 'Wi-Fi'],
    highlights: <String>[
      'Private cedar bath in every suite',
      'Kaiseki dinner included',
      'Twelve minutes from Gion',
    ],
    tags: <String>['ryokan', 'wellness', 'culture'],
  ),
  MockHotel(
    id: 'H-NYC-001',
    name: 'The Gramercy Wing',
    city: 'New York',
    country: 'US',
    destinationId: 'NYC',
    stars: 5,
    currency: 'USD',
    baseNightlyMinor: 89000,
    latitude: 40.7376,
    longitude: -73.9860,
    address: '2 Lexington Ave, New York, NY 10010',
    headline: 'A residents-only park, and a bar that pretends not to exist',
    body:
        'Fifty-two rooms above Gramercy Park, with key access to the park '
        'itself - one of a handful of hotels that still has it. The library bar '
        'has no sign and no reservations.',
    signature: 'Key access to Gramercy Park, collected at the desk.',
    amenities: <String>['Bar', 'Gym', 'Concierge', 'Pet friendly', 'Wi-Fi'],
    highlights: <String>[
      'Gramercy Park key',
      'Library bar',
      'Suites from 45 m²',
    ],
    tags: <String>['city', 'design'],
  ),
  MockHotel(
    id: 'H-DXB-001',
    name: 'Al Bahr Residences',
    city: 'Dubai',
    country: 'AE',
    destinationId: 'DXB',
    stars: 5,
    currency: 'USD',
    baseNightlyMinor: 68000,
    latitude: 25.1412,
    longitude: 55.1853,
    address: 'Al Sufouh Road, Dubai',
    headline: 'A private beach, and shade engineered to work in August',
    body:
        'Low-rise villas along 400 metres of private beach, with a cooled '
        'colonnade connecting them to the three restaurants. The spa runs a '
        'hammam programme that is worth the trip on its own.',
    signature: 'Sunset dhow charter from the hotel\'s own jetty.',
    amenities: <String>['Private beach', 'Spa', 'Pool', 'Kids club', 'Wi-Fi'],
    highlights: <String>['400 m private beach', 'Three restaurants', 'Hammam'],
    tags: <String>['beach', 'family', 'wellness'],
  ),
  MockHotel(
    id: 'H-CPT-001',
    name: 'Bo-Kaap House',
    city: 'Cape Town',
    country: 'ZA',
    destinationId: 'CPT',
    stars: 4,
    currency: 'USD',
    baseNightlyMinor: 31000,
    latitude: -33.9199,
    longitude: 18.4166,
    address: 'Wale Street, Bo-Kaap, Cape Town',
    headline: 'Table Mountain from the pool, the harbour from the terrace',
    body:
        'Twenty-two rooms in three restored houses on the slope of Signal '
        'Hill. The kitchen leans Cape Malay, and the sommelier will happily '
        'spend an hour on Swartland wines you have never heard of.',
    signature: 'Guided walk of Bo-Kaap with a fourth-generation resident.',
    amenities: <String>['Pool', 'Restaurant', 'Terrace', 'Wi-Fi', 'Parking'],
    highlights: <String>[
      'Mountain views',
      'Cape Malay kitchen',
      'Rooftop pool',
    ],
    tags: <String>['city', 'view'],
  ),
  MockHotel(
    id: 'H-CPT-002',
    name: 'Camps Bay Retreat',
    city: 'Cape Town',
    country: 'ZA',
    destinationId: 'CPT',
    stars: 5,
    currency: 'USD',
    baseNightlyMinor: 52000,
    latitude: -33.9550,
    longitude: 18.3776,
    address: 'Camps Bay, Cape Town',
    headline: 'Twelve Apostles on one side, the Atlantic on the other',
    body:
        'A 1929 manor and four glass pavilions on a ravine above Camps Bay, '
        'connected by a suspension bridge over the gorge.',
    signature: 'Helicopter transfer from Cape Town International.',
    amenities: <String>['Pool', 'Spa', 'Restaurant', 'Wi-Fi'],
    highlights: <String>['Ocean views', 'Four pools', 'Suspension bridge'],
    tags: <String>['beach', 'view', 'romantic'],
  ),
];

/// Rate plans offered at every property. The member plan is only returned when
/// the availability request carries a membership number.
class MockRatePlan {
  const MockRatePlan({
    required this.code,
    required this.name,
    required this.multiplier,
    required this.refundable,
    required this.mealPlanCode,
    required this.memberOnly,
    this.inclusions = const <String>[],
  });

  final String code;
  final String name;

  /// Applied to the property's base nightly rate.
  final double multiplier;
  final bool refundable;
  final String mealPlanCode;
  final bool memberOnly;
  final List<String> inclusions;
}

const List<MockRatePlan> mockRatePlans = <MockRatePlan>[
  MockRatePlan(
    code: 'BAR',
    name: 'Best available rate',
    multiplier: 1.0,
    refundable: true,
    mealPlanCode: 'RO',
    memberOnly: false,
  ),
  MockRatePlan(
    code: 'BARBB',
    name: 'Bed & breakfast',
    multiplier: 1.12,
    refundable: true,
    mealPlanCode: 'BB',
    memberOnly: false,
    inclusions: <String>['Breakfast for two'],
  ),
  MockRatePlan(
    code: 'ADV',
    name: 'Advance purchase',
    multiplier: 0.82,
    refundable: false,
    mealPlanCode: 'RO',
    memberOnly: false,
  ),
  MockRatePlan(
    code: 'MEMBER',
    name: 'Member rate',
    multiplier: 0.88,
    refundable: true,
    mealPlanCode: 'BB',
    memberOnly: true,
    inclusions: <String>['Breakfast for two', 'Room upgrade if available'],
  ),
];

class MockRoomType {
  const MockRoomType({
    required this.code,
    required this.name,
    required this.description,
    required this.maxOccupancy,
    required this.sizeSqm,
    required this.bedding,
    required this.priceFactor,
  });

  final String code;
  final String name;
  final String description;
  final int maxOccupancy;
  final int sizeSqm;
  final String bedding;
  final double priceFactor;
}

const List<MockRoomType> mockRoomTypes = <MockRoomType>[
  MockRoomType(
    code: 'DLX',
    name: 'Deluxe room',
    description: 'Courtyard or street view, walk-in shower, writing desk.',
    maxOccupancy: 2,
    sizeSqm: 32,
    bedding: 'King or twin',
    priceFactor: 1.0,
  ),
  MockRoomType(
    code: 'JRSTE',
    name: 'Junior suite',
    description: 'Separate sitting area and a bath with a view.',
    maxOccupancy: 3,
    sizeSqm: 46,
    bedding: 'King + sofa bed',
    priceFactor: 1.45,
  ),
  MockRoomType(
    code: 'STE',
    name: 'Signature suite',
    description: 'Two rooms, terrace, and the best view in the house.',
    maxOccupancy: 4,
    sizeSqm: 68,
    bedding: 'King + twin',
    priceFactor: 2.1,
  ),
];

/// Media categories generated for each property.
const List<String> mockMediaCategories = <String>[
  'Exterior',
  'Lobby',
  'Guest Room',
  'Suite',
  'Dining',
  'Spa',
  'Pool',
];

/// Loyalty members. `LS-100042` is the one the sign-in screen suggests.
class MockMember {
  const MockMember({
    required this.membershipNumber,
    required this.memberId,
    required this.firstName,
    required this.lastName,
    required this.tier,
    required this.points,
    required this.pending,
    required this.lifetime,
    required this.nights,
    required this.contactId,
    required this.email,
    required this.phone,
  });

  final String membershipNumber;
  final String memberId;
  final String firstName;
  final String lastName;
  final String tier;
  final int points;
  final int pending;
  final int lifetime;
  final int nights;
  final String contactId;
  final String email;
  final String phone;
}

const List<MockMember> mockMembers = <MockMember>[
  MockMember(
    membershipNumber: 'LS-100042',
    memberId: '0lM5j000000GoldAAA',
    firstName: 'Amara',
    lastName: 'Okonkwo',
    tier: 'Gold',
    points: 48250,
    pending: 3100,
    lifetime: 214500,
    nights: 31,
    contactId: '0035j00000ContactA',
    email: 'amara.okonkwo@example.com',
    phone: '+234 802 555 0142',
  ),
  MockMember(
    membershipNumber: 'LS-100077',
    memberId: '0lM5j000000PlatBBB',
    firstName: 'Tomás',
    lastName: 'Ferreira',
    tier: 'Platinum',
    points: 132900,
    pending: 0,
    lifetime: 890300,
    nights: 58,
    contactId: '0035j00000ContactB',
    email: 'tomas.ferreira@example.com',
    phone: '+351 912 555 088',
  ),
  MockMember(
    membershipNumber: 'LS-100901',
    memberId: '0lM5j000000SilvCCC',
    firstName: 'Rev',
    lastName: 'Mocheje',
    tier: 'Silver',
    points: 6400,
    pending: 850,
    lifetime: 21400,
    nights: 12,
    contactId: '0035j00000ContactC',
    email: 'r.mocheje@example.com',
    phone: '+234 803 555 0117',
  ),
];

/// CMS offers. Each carries a promotion code the app forwards to SynXis.
class MockOffer {
  const MockOffer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.promotionCode,
    required this.memberOnly,
    this.hotelIds = const <String>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final String promotionCode;
  final bool memberOnly;
  final List<String> hotelIds;
}

const List<MockOffer> mockOffers = <MockOffer>[
  MockOffer(
    id: 'offer-stay-longer',
    title: 'Stay longer, pay less',
    subtitle:
        'Fourth night complimentary at participating properties, '
        'booked direct.',
    promotionCode: 'STAY4',
    memberOnly: false,
  ),
  MockOffer(
    id: 'offer-suite-upgrade',
    title: 'Suite season',
    subtitle:
        'Guaranteed upgrade to a junior suite on stays of three nights '
        'or more.',
    promotionCode: 'SUITE25',
    memberOnly: false,
    hotelIds: <String>['H-PAR-001', 'H-NYC-001'],
  ),
  MockOffer(
    id: 'offer-members-kyoto',
    title: 'Members in Kyoto',
    subtitle:
        'A private tea ceremony and late check-out, for Rewards members '
        'only.',
    promotionCode: 'MEMKYO',
    memberOnly: true,
    hotelIds: <String>['H-KYO-001'],
  ),
];
