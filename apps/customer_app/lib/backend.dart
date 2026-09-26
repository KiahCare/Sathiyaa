import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'mock_data.dart';
import 'broadcasts.dart';
import 'service_area.dart';
import 'api/api_backend.dart';

/// Everything the screens are allowed to ask of a backend.
///
/// Two implementations exist: [MockBackend], which keeps everything in memory
/// so the app is fully usable with no server, and [ApiBackend], which talks to
/// the real Express + MySQL API. The screens only ever touch [Backend.instance],
/// so switching between them at runtime changes nothing above this line.
abstract class SathiyaaBackend {
  // ---- Session ------------------------------------------------------------

  /// Turns a server-relative reference like `/uploads/photo/abc.jpg` into a
  /// URL that can actually be fetched. Returns null for anything that is not
  /// a server path -- a local file, or demo mode, where there is no server.
  String? absoluteUrl(String? ref);

  Customer? get currentCustomer;
  set currentCustomer(Customer? c);

  /// Registration returns the OTP only in dev/demo mode, where the backend
  /// echoes it back instead of sending an SMS. Null means "a real SMS went out".
  Future<String?> registerCustomer({required String name, required String mobile});
  Future<String?> loginRequestOtp(String mobile);
  Future<void> verifyOtp(String mobile, String otp);
  Future<void> acceptTerms();
  Future<void> signOut();

  // ---- Profile ------------------------------------------------------------
  Future<void> updateBasicDetails({
    required String name,
    String? email,
    String? photoPath,
    DateTime? dob,
    String? gender,
    String? bloodGroup,
    List<String>? languages,
    double? heightCm,
    double? weightKg,
  });
  Future<void> saveAddresses({required Address primary, Address? secondary});
  Address? primaryAddress();
  Future<void> setContactPreference({required Set<ContactMode> modes, String? timeframe});
  /// Checks the code against the real partner list and returns that
  /// partner's name. Throws, with the server's own wording, if it is not one
  /// of ours.
  Future<String> applyReferenceCode(String code);
  Future<void> clearReferenceCode();
  Future<void> payRegistrationFee();

  // ---- Where Sathiyaa works -----------------------------------------------


  // ---- Messages from Sathiyaa ---------------------------------------------

  /// Everything an admin has broadcast to this account, newest first.
  Future<List<Broadcast>> loadBroadcasts();

  /// Marks every unread one as read. Read state is the server's, so it is the
  /// same on a reinstall and the console's delivery figure means something.
  Future<void> markBroadcastsRead();

  // ---- Where Sathiyaa works -----------------------------------------------

  /// The launch city, read from the server so it can change without an APK.
  Future<ServiceArea> loadServiceArea();

  /// Reports where this account registered from. Returns the server's
  /// verdict: true if Sathiyaa covers it.
  Future<bool> reportSignupPlace(SignupPlace place);

  /// Pulls the whole profile down again. On the mock this is a no-op; against
  /// the API it refreshes [currentCustomer] and all its sections.
  Future<void> refreshProfile();

  // ---- Health sections ----------------------------------------------------
  Future<void> addVital(VitalRecord v);
  Future<void> updateVital(VitalRecord v);
  Future<void> deleteVital(String id);
  List<VitalRecord> vitalsWithin(int days, {VitalType? type});

  Future<void> addMedication(MedicationRecord m);
  Future<void> updateMedication(MedicationRecord m);
  Future<void> deleteMedication(String id);

  Future<void> addSurgery(SurgeryRecord s);
  Future<void> updateSurgery(SurgeryRecord s);
  Future<void> deleteSurgery(String id);

  Future<void> addAllergy(AllergyRecord a);
  Future<void> updateAllergy(AllergyRecord a);
  Future<void> deleteAllergy(String id);

  Future<void> addInsurance(InsuranceRecord i);
  Future<void> updateInsurance(InsuranceRecord i);
  Future<void> deleteInsurance(String id);

  Future<void> addFamilyMember(FamilyMember f);
  Future<void> updateFamilyMember(FamilyMember f);
  Future<void> removeFamilyMember(String id);

  // ---- Providers ----------------------------------------------------------
  Future<List<Provider>> search({
    required ServiceType type,
    String? gender,
    String? language,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? timeFrom,
    String? timeTo,
    double? lat,
    double? lng,
    double? radiusKm,
  });
  /// Async lookup; also fills the cache below.
  Future<Provider> providerById(String id);

  /// Synchronous read of an already-loaded provider, for list rows that are
  /// building right now. Null means "not fetched yet" — callers fall back to
  /// whatever name the booking itself carries.
  Provider? cachedProvider(String id);
  Future<void> linkProvider(String providerId);
  Future<void> unlinkProvider(String providerId);
  Future<List<Provider>> linkedProviders();

  // ---- Messages -----------------------------------------------------------
  /// The conversation on a booking. Reading it marks the carer's messages read.
  ///
  /// Only open on a confirmed, running or finished booking — there is nobody
  /// to talk to before somebody has accepted.
  Future<List<BookingMessage>> bookingMessages(String bookingId);

  /// Say something to the carer on this booking.
  Future<BookingMessage> sendBookingMessage(String bookingId, String body);

  // ---- Emergency ----------------------------------------------------------
  /// Raises an emergency alert: records it, and notifies the family on the
  /// account plus the carer on any visit in progress.
  ///
  /// The alert is recorded whether or not a message can be sent, and the
  /// result says which happened. Never throws for a missing location — an
  /// emergency is the worst moment to refuse a request over a blank field.
  Future<SosResult> raiseSos({
    double? lat,
    double? lng,
    String? addressText,
    String? note,
  });

  // ---- Bookings -----------------------------------------------------------
  /// Every booking for the signed-in customer, newest first.
  Future<List<Booking>> allBookings();
  /// Ask one or more carers for a visit.
  ///
  /// [providerIds] is the shortlist. The request goes to all of them and the
  /// first to accept takes it — which is what the server has always done, it
  /// just used to decide the list itself while the app showed one name. One id
  /// is the ordinary case: opening somebody's profile and asking them.
  Future<Booking> createBooking({
    required List<String> providerIds,
    required ServiceType type,
    required DateTime start,
    required DateTime end,
    required String timeFrom,
    required String timeTo,
    /// Null means the booking is for the account holder.
    FamilyMember? forMember,
  });
  Future<Booking> refreshBooking(String bookingId);
  Future<void> payBookingCharge(String bookingId);
  CancellationQuote quoteCancellation(Booking b);
  Future<CancellationQuote> cancelBooking(String bookingId);
  Future<void> rateProvider(String bookingId, double rating, String comment);

  /// Demo-only shortcuts that stand in for the provider app's side of the
  /// flow. Against the real API these are unavailable — the provider app does
  /// these for real — so they throw with an explanatory message.
  Future<void> startServiceSimulation(String bookingId);
  Future<void> completeService(String bookingId);
  bool get supportsSimulation;
}

/// Which backend the app is talking to.
enum BackendMode { mock, live }

/// Runtime switch between the in-memory demo data and a live server, plus the
/// persisted server URL. Kept deliberately small: `Backend.instance` is the
/// only thing the screens know about.
class Backend {
  static const _kMode = 'backend_mode';
  static const _kBaseUrl = 'backend_base_url';
  static const _kToken = 'auth_token';

  /// Who is signed in on demo data.
  ///
  /// A live session is a token; a demo session is just a mobile number, since
  /// there is no server to have issued anything. It is kept for the same
  /// reason the token is: a fresh install should open on Welcome, and the
  /// eleventh launch should not.
  static const _kDemoMobile = 'demo_signed_in_mobile';

  /// The server address compiled into this build, if it was given one.
  ///
  /// Empty in an ordinary build, which is what keeps `flutter run` and every
  /// APK built by rebuild-apks.ps1 pointing at a laptop. _builds/
  /// build-for-cloud.ps1 passes it, so an APK built for the cloud arrives on a
  /// phone already knowing where the server is.
  ///
  /// Without this the "cloud" APK was a cloud build in name only: the access
  /// key was compiled in and the address was not, so it opened against
  /// 10.0.2.2 — the emulator's name for the host machine, and nothing at all on
  /// a real phone — and every person handed one had to find the Server screen
  /// and type an address off a piece of paper.
  static const _compiledBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// A build that was handed a server address is a build meant for that
  /// server, so it opens against it rather than on demo data. An ordinary build
  /// still starts in demo mode, which is what somebody handed an APK to look
  /// at should see.
  static BackendMode _mode =
      _compiledBaseUrl.isNotEmpty ? BackendMode.live : BackendMode.mock;
  static String _baseUrl =
      _compiledBaseUrl.isNotEmpty ? _compiledBaseUrl : 'http://10.0.2.2:4000/api/v1';
  static ApiBackend? _api;

  static BackendMode get mode => _mode;
  static String get baseUrl => _baseUrl;
  static bool get isLive => _mode == BackendMode.live;

  static SathiyaaBackend get instance =>
      _mode == BackendMode.live ? (_api ??= _newApi()) : MockBackend.instance;

  /// A live client wired to persist its own session.
  static ApiBackend _newApi() => ApiBackend(_baseUrl, onToken: _persistToken);

  static Future<void> _persistToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

  /// Reads the saved mode and URL at startup, and restores the previous
  /// sign-in if there was one. Falls back to mock mode if anything is
  /// missing, so a fresh install is always immediately usable.
  ///
  /// Restoring the session matters more than it sounds: without it every app
  /// restart in live mode would demand a fresh OTP, which over days of
  /// testing reads as a bug rather than as security.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? _baseUrl;
    // No saved choice falls back to what this build was compiled for, not to
    // demo. Otherwise a cloud APK would still open on demo data on its first
    // run, which is the one run that matters.
    final savedMode = prefs.getString(_kMode);
    _mode = (savedMode ?? (_compiledBaseUrl.isNotEmpty ? 'live' : 'mock')) == 'live'
        ? BackendMode.live
        : BackendMode.mock;

    if (_mode != BackendMode.live) {
      // Demo data no longer opens already signed in — a first run has to show
      // the welcome screen, the sign-up and the code, or nobody ever sees the
      // journey the app is actually for. This is what stops that costing a
      // sign-in on every launch afterwards.
      final demo = prefs.getString(_kDemoMobile);
      if (demo != null) MockBackend.instance.restoreSession(demo);
      return;
    }

    final api = _newApi();
    _api = api;

    final saved = prefs.getString(_kToken);
    if (saved == null) return;

    api.restoreToken(saved);
    try {
      // Prove the token still works before trusting it. A server that is off
      // or unreachable must not hold the splash screen open, hence the short
      // ceiling.
      await api.refreshProfile().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Expired, revoked, or the server is not there. Either way, start
      // signed out rather than showing a half-loaded profile.
      api.restoreToken(null);
      await clearSavedToken();
    }
  }

  static Future<void> clearSavedToken() => _persistToken(null);

  /// Called by [MockBackend] whenever somebody signs in or out of demo data.
  /// Null forgets the session.
  ///
  /// Best effort on purpose. Remembering the session is a convenience; being
  /// signed in is not. If the store cannot be reached — a plain Dart test with
  /// no plugins registered, a device where it fails — the sign-in must still
  /// go through and the next launch simply starts at Welcome.
  static Future<void> rememberDemoSession(String? mobile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mobile == null) {
        await prefs.remove(_kDemoMobile);
      } else {
        await prefs.setString(_kDemoMobile, mobile);
      }
    } catch (_) {
      // Nothing to do and nothing worth saying: the session is live either way.
    }
  }

  static Future<void> configure({required BackendMode mode, String? baseUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      _baseUrl = _normalise(baseUrl.trim());
      await prefs.setString(_kBaseUrl, _baseUrl);
    }
    _mode = mode;
    await prefs.setString(_kMode, mode == BackendMode.live ? 'live' : 'mock');
    // Switching backend or server drops the old session — the account it
    // belonged to does not exist on the other side.
    await prefs.remove(_kToken);
    await prefs.remove(_kDemoMobile);
    _api = mode == BackendMode.live ? _newApi() : null;
  }

  /// Accepts what people actually type — "192.168.1.5:4000", with or without
  /// a scheme or the /api/v1 suffix — and turns it into a usable base URL.
  static String _normalise(String input) {
    var url = input;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!url.endsWith('/api/v1')) url = '$url/api/v1';
    return url;
  }

  static String normaliseForDisplay(String input) => _normalise(input);
}
