import 'dart:convert';

/// A trusted contact that will be called during an emergency.
/// Exactly one contact can be marked PRIMARY.
/// SMS goes to all contacts; automatic call goes to PRIMARY only.
class TrustedContact {
  final String name;
  final String phoneNumber;
  final bool isTestContact;
  final bool isPrimary;

  TrustedContact({
    required this.name,
    required this.phoneNumber,
    this.isTestContact = false,
    this.isPrimary = false,
  });

  /// Create a copy with optional overrides
  TrustedContact copyWith({
    String? name,
    String? phoneNumber,
    bool? isTestContact,
    bool? isPrimary,
  }) {
    return TrustedContact(
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isTestContact: isTestContact ?? this.isTestContact,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  /// Create from JSON map
  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      name: json['name'] as String? ?? '',
      phoneNumber: json['phone_number'] as String? ?? '',
      isTestContact: json['is_test_contact'] as bool? ?? false,
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
        'name': name,
        'phone_number': phoneNumber,
        'is_test_contact': isTestContact,
        'is_primary': isPrimary,
      };

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON string
  factory TrustedContact.fromJsonString(String jsonString) {
    return TrustedContact.fromJson(jsonDecode(jsonString));
  }

  /// Validate that the contact has required fields
  bool get isValid => name.isNotEmpty && phoneNumber.isNotEmpty;

  @override
  String toString() => 'TrustedContact(name: $name, phone: $phoneNumber)';
}
