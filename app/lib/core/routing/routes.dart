/// Route paths. Flat list — no auth, no deep links; this is a demo.
class Routes {
  const Routes._();

  static const welcome = '/';
  static const home = '/home';
  static const generating = '/generating';
  static const preview = '/preview';
  static const walk = '/walk';
  static const summary = '/summary';

  /// Dev-only: live voice call against the Gemini relay backend.
  static const voiceTest = '/voice-test';

  /// `/keepsake/:id` — a saved walk's summary.
  static const keepsake = '/keepsake/:id';
  static String keepsakePath(String id) => '/keepsake/$id';
}
