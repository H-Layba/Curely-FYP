// lib/utils/cloudinary_cleanup.dart
//
// Shared helper for removing Cloudinary images tied to a specific user's
// data. Used wherever the app deletes/replaces an image: deleting a single
// report, deleting a whole folder, replacing/removing a profile picture,
// and deleting an account.
//
// Cloudinary only allows deletion through a *signed* API call that needs
// the account's API secret. That secret must never live inside the app —
// anyone could decompile the app and get delete access to every image in
// the account, not just their own. So this only ever sends the specific
// public_ids the caller already knows belong to the current user, to a
// backend endpoint that performs the actual signed delete server-side.
// See delete-images-endpoint.js for the matching backend route.

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Same backend already used for report text extraction
/// (lib/reports/report.dart's BASE_URL).
const String kCloudinaryDeleteBackendUrl = "https://backend-g8y6.onrender.com";

/// Pulls the Cloudinary public_id out of a secure_url, e.g.
/// https://res.cloudinary.com/<cloud>/image/upload/v169.../abc123.jpg
/// → "abc123". Returns null for anything that isn't a Cloudinary upload
/// URL (e.g. a Google account photo URL, or no image at all).
String? extractCloudinaryPublicId(String? url) {
  if (url == null || url.isEmpty) return null;
  try {
    final segments = Uri.parse(url).pathSegments;
    final uploadIndex = segments.indexOf('upload');
    if (uploadIndex == -1 || uploadIndex == segments.length - 1) {
      return null;
    }

    var rest = segments.sublist(uploadIndex + 1);
    // Drop a leading version segment like "v1700000000".
    if (rest.isNotEmpty && RegExp(r'^v\d+$').hasMatch(rest.first)) {
      rest = rest.sublist(1);
    }
    if (rest.isEmpty) return null;

    final joined = rest.join('/');
    final dot = joined.lastIndexOf('.');
    return dot == -1 ? joined : joined.substring(0, dot);
  } catch (_) {
    return null;
  }
}

/// Asks the backend to delete the given Cloudinary public_ids.
/// Best-effort: any failure (network blip, backend asleep on Render's
/// free tier, etc.) is swallowed so it never blocks whatever the caller
/// was actually trying to do — deleting a report shouldn't fail just
/// because image cleanup couldn't reach the backend.
Future<void> deleteCloudinaryImages(Iterable<String?> urlsOrIds) async {
  // Accepts either raw secure_urls or already-extracted public_ids.
  final ids = urlsOrIds
      .map((u) => (u != null && u.contains('res.cloudinary.com'))
          ? extractCloudinaryPublicId(u)
          : u)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  if (ids.isEmpty) return;

  try {
    await http.post(
      Uri.parse("$kCloudinaryDeleteBackendUrl/delete-images"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"publicIds": ids}),
    );
  } catch (_) {
    // Best-effort — see doc comment above.
  }
}