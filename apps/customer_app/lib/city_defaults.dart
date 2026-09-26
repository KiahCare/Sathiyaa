/// Where the app looks when nobody has told it where the user is.
///
/// This has to match the city the backend seeds its demo providers into, or
/// the two modes disagree in a way that looks like a broken app: offline the
/// search finds people, and against the live server the same search finds
/// nobody, because the map pin is nine hundred kilometres from every provider
/// in the database. Change this and `backend/src/db/seed.js` together.
/// Ahmedabad, because that is where Sathiyaa launched. See
/// service_area.dart for the gate that keeps registrations to it, and
/// migration 015 for the copy of these numbers the server decides with.
const kDefaultCity = 'Ahmedabad';
const kDefaultLat = 23.0225;
const kDefaultLng = 72.5714;
