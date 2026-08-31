import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trusted_contact.dart';

/// Service for managing trusted contacts and initiating emergency phone calls.
///
/// Contacts are stored locally using SharedPreferences (JSON-encoded list).
/// Phone calls use Android's native dialer via url_launcher with `tel:` URI.
class ContactService extends ChangeNotifier {
  static const String _storageKey = 'resq_trusted_contacts';
  static const String _testPhoneNumber = '+919999999999';

  List<TrustedContact> _contacts = [];
  bool _isLoading = false;

  static const int maxContacts = 5;

  List<TrustedContact> get contacts => List.unmodifiable(_contacts);
  bool get isLoading => _isLoading;
  bool get hasContacts => _contacts.isNotEmpty;

  /// Get the PRIMARY trusted contact (exactly one should be marked).
  /// Falls back to the first non-test contact if none is explicitly primary.
  TrustedContact? get primaryContact {
    // First, look for explicitly marked primary
    final primary = _contacts.where((c) => c.isPrimary && c.isValid).toList();
    if (primary.isNotEmpty) return primary.first;
    // Fallback: first valid non-test contact
    final nonTest = _contacts.where((c) => c.isValid && !c.isTestContact).toList();
    if (nonTest.isNotEmpty) return nonTest.first;
    // Last resort: first valid contact
    final valid = _contacts.where((c) => c.isValid).toList();
    return valid.isNotEmpty ? valid.first : null;
  }

  /// Load contacts from local storage
  Future<void> loadContacts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _contacts = jsonList
            .map((item) => TrustedContact.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('ContactService: Error loading contacts: $e');
      _contacts = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Save contacts to local storage
  Future<void> _saveContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _contacts.map((c) => c.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('ContactService: Error saving contacts: $e');
    }
  }

  /// Add a trusted contact
  Future<void> addContact(TrustedContact contact) async {
    if (!contact.isValid) return;
    if (_contacts.length >= maxContacts) return;
    // If this is the first contact, make it primary by default
    if (_contacts.isEmpty) {
      _contacts.add(contact.copyWith(isPrimary: true));
    } else {
      _contacts.add(contact);
    }
    await _saveContacts();
    notifyListeners();
  }

  /// Set a contact as PRIMARY (all others become non-primary)
  Future<void> setPrimary(int index) async {
    if (index < 0 || index >= _contacts.length) return;
    _contacts = _contacts.asMap().entries.map((entry) {
      return entry.value.copyWith(isPrimary: entry.key == index);
    }).toList();
    await _saveContacts();
    notifyListeners();
  }

  /// Remove a trusted contact by index
  Future<void> removeContact(int index) async {
    if (index < 0 || index >= _contacts.length) return;
    _contacts.removeAt(index);
    await _saveContacts();
    notifyListeners();
  }

  /// Get the primary contact's phone number for emergency calling.
  /// Returns null if no contacts are configured.
  String? getEmergencyPhoneNumber() {
    return primaryContact?.phoneNumber;
  }

  /// Initiate a phone call to the given phone number.
  /// Uses Android's native dialer via url_launcher.
  /// Returns true if the call was initiated, false otherwise.
  Future<bool> callContact(String phoneNumber) async {
    if (phoneNumber.isEmpty) return false;

    final Uri uri = Uri.parse('tel:$phoneNumber');

    try {
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          debugPrint('ContactService: launchUrl returned false for $uri');
        }
        return launched;
      } else {
        debugPrint('ContactService: canLaunchUrl returned false for $uri');
        return false;
      }
    } catch (e) {
      debugPrint('ContactService: Error launching phone call: $e');
      return false;
    }
  }

  /// Call the PRIMARY trusted contact.
  /// This is called when an emergency is confirmed.
  /// Returns true if the call was initiated.
  Future<bool> callEmergencyContact() async {
    final phone = getEmergencyPhoneNumber();
    if (phone == null) {
      debugPrint('ContactService: No primary trusted contact configured');
      return false;
    }
    debugPrint('ContactService: Calling primary contact at $phone');
    return await callContact(phone);
  }

  /// Get the test phone number used during development.
  static String get testPhoneNumber => _testPhoneNumber;
}
