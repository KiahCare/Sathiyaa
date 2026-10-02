import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'broadcasts.dart';
import 'service_area.dart';
import 'mock_data.dart';
import 'api/api_backend.dart';

/// Everything the provider screens are allowed to ask of a backend.
///
/// [MockBackend] keeps it all in memory so the app is usable with no server;
/// [ApiBackend] talks to the real Express + MySQL API. Screens only ever touch
/// `Backend.instance`, so switching between them changes nothing above here.
abstract class SathiyaaProviderBackend {
  ProviderProfile? get currentProvider;
  set currentProvider(ProviderProfile? p);

  /// Bookings belonging to the signed-in provider. Kept synchronous because
  /// nearly every screen reads it while building; [refresh] is what actually
  /// goes and fetches.
  List<ProviderBooking> get myBookings;
  List<CalendarBlock> get calendarBlocks;
  List<TimeBankEntry> get timeBank;

  /// Pulls profile, bookings, calendar blocks and Time Bank down again.
  Future<void> refresh();

  /// Turns a server-relative reference like `/uploads/photo/abc.jpg` into a
  /// URL that can actually be fetched. Returns null for anything that is not
  /// a server path -- a local file, or demo mode, where there is no server.
  String? absoluteUrl(String? ref);

  /// Uploads one supporting document and returns the URL the server stored it
  /// at. `category` must be one the server knows: aadhar, police-verification,
  /// work-certificate, medical-certificate, org-registration, photo, selfie.
  /// The list is `CATEGORIES` in the API's uploadController.js, and a category
  /// missing from it is a 400 -- which is how organisation registration
  /// certificates went unstored for as long as they did.
  Future<String> uploadDocument(String filePath, {String category});


  // ---- Auth ---------------------------------------------------------------
  Future<void> registerStart({required String name, required String mobile});
  Future<ProviderProfile> completeRegistration(ProviderProfile draft);
  Future<void> loginWithPin(String mobile, String pin);
  Future<void> signOut();

  // ---- Messages -----------------------------------------------------------
  /// The conversation on a job. Reading it marks the family's messages read.
  Future<List<BookingMessage>> bookingMessages(String bookingId);

  /// Say something to the family on this job.
  Future<BookingMessage> sendBookingMessage(String bookingId, String body);

  /// Correct the languages this carer speaks.
  ///
  /// The one field on the profile that is editable, because it is the one a
  /// carer can get wrong in a way that quietly costs them work: a family
  /// filters on it, and a carer listed as English-only never appears in a
  /// search for Gujarati.
  Future<void> setLanguages(List<String> languages);

  // ---- Availability -------------------------------------------------------
  Future<void> setLocationOn(bool on);
  Future<void> pingLocation(double lat, double lng);

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

  // ---- Requests & service delivery ---------------------------------------
  Future<void> acceptBooking(String id);
  Future<void> rejectBooking(String id);
  Future<void> transferBooking(String id, String toEmployeeId);
  Future<void> sendRunningLate(String id, String eta);
  /// Runs the arrival checks. [selfiePath] is a photo just taken on this
  /// phone; it is uploaded and stored against the booking so an admin can see
  /// who actually turned up, whether or not automated face matching is
  /// switched on.
  Future<FaceCheckResult> verifyFaceAndGeofence(String id, {String? selfiePath});
  Future<String> startService(String id);
  Future<void> confirmOtpAndStart(String id, String enteredOtp);
  Future<void> endService(String id);
  Future<void> recordPayment(String id, double amount, {required bool full});
  Future<void> sendPaymentReminder(String id);
  Future<void> rateCustomer(String id, double rating, String comment);
  Future<void> orgCancel(String id);

  // ---- Calendar -----------------------------------------------------------
  bool isBlocked(DateTime day);
  List<ProviderBooking> bookingsOn(DateTime day);
  bool worksOn(DateTime day);
  double freeHoursOn(DateTime day);
  Future<CalendarBlock> blockCalendar({required DateTime from, required DateTime to, String reason});
  Future<void> unblockCalendar(String id);

  // ---- Dashboard & organization ------------------------------------------
  DashboardStats statsFor(String period, {String? employeeId});
  Map<String, dynamic> utilizationFor(String employeeId);
  Future<void> addEmployee(Employee e);
  Future<void> updateEmployee(Employee e);
  Future<void> setEmployeeStatus(String id, EmployeeStatus status);
  Future<void> toggleAllocateViaOrg(bool value);
}

enum BackendMode { mock, live }

/// Runtime switch between the in-memory demo data and a live server, plus the
/// persisted server URL.
class Backend {
  static const _kMode = 'backend_mode';
  static const _kBaseUrl = 'backend_base_url';
  static const _kDeviceId = 'device_id';
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
  static String _deviceId = 'sathiyaa-provider-device';
  static ApiBackend? _api;

  static BackendMode get mode => _mode;
  static String get baseUrl => _baseUrl;
  static String get deviceId => _deviceId;
  static bool get isLive => _mode == BackendMode.live;

  static SathiyaaProviderBackend get instance =>
      _mode == BackendMode.live ? (_api ??= _newApi()) : MockBackend.instance;

  /// A live client wired to persist its own session.
  static ApiBackend _newApi() => ApiBackend(_baseUrl, deviceId: _deviceId, onToken: _persistToken);

  static Future<void> _persistToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

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

    // The backend binds an account to one device, so this id has to survive
    // restarts or every launch would look like a login from a new phone.
    var id = prefs.getString(_kDeviceId);
    if (id == null) {
      id = 'sathiyaa-provider-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_kDeviceId, id);
    }
    _deviceId = id;

    if (_mode != BackendMode.live) {
      // Demo data no longer opens already signed in — a first run has to show
      // the welcome screen and the sign-in, or nobody ever sees them. This is
      // what stops that costing a sign-in on every launch afterwards.
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
      // Prove the token still works before trusting it; a server that is off
      // must not hold the splash screen open.
      await api.refresh().timeout(const Duration(seconds: 8));
    } catch (_) {
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
  /// a scheme or the /api/v1 suffix.
  static String _normalise(String input) {
    var url = input;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!url.endsWith('/api/v1')) url = '$url/api/v1';
    return url;
  }

  static String normaliseForDisplay(String input) => _normalise(input);
}
