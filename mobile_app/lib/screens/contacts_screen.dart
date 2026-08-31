import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/contact_service.dart';
import '../models/trusted_contact.dart';

/// Dedicated trusted contacts management screen.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ContactService>(
      builder: (context, contactService, _) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'TRUSTED CONTACTS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'SMS → All contacts  |  Call → PRIMARY only',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                const SizedBox(height: 24),

                // Contact count
                _buildInfoBar(contactService),
                const SizedBox(height: 16),

                // Contact list
                if (contactService.contacts.isEmpty)
                  _buildEmptyState()
                else
                  for (int i = 0; i < contactService.contacts.length; i++)
                    _buildContactTile(
                      context: context,
                      contact: contactService.contacts[i],
                      index: i,
                      contactService: contactService,
                    ),

                const SizedBox(height: 16),

                // Add button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: contactService.contacts.length >= ContactService.maxContacts
                        ? null
                        : () => _showAddContactDialog(context, contactService),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      contactService.contacts.length >= ContactService.maxContacts
                          ? 'Maximum contacts reached'
                          : 'Add Trusted Contact',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyan,
                      disabledForegroundColor: Colors.grey.shade600,
                      side: BorderSide(
                        color: contactService.contacts.length >= ContactService.maxContacts
                            ? Colors.grey.shade700
                            : Colors.cyan,
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Info section
                _buildInfoSection(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoBar(ContactService contactService) {
    final primary = contactService.primaryContact;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${contactService.contacts.length}/${ContactService.maxContacts} contacts configured',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
                if (primary != null)
                  Text(
                    'Emergency call → ${primary.name}',
                    style: TextStyle(color: Colors.cyan.shade300, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.person_off, size: 48, color: Colors.orange.shade300),
          const SizedBox(height: 12),
          Text(
            'No trusted contacts',
            style: TextStyle(color: Colors.orange.shade300, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Add trusted contacts so ResQ AI can\nalert them during an emergency.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile({
    required BuildContext context,
    required TrustedContact contact,
    required int index,
    required ContactService contactService,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: contact.isPrimary
              ? Colors.cyan.withOpacity(0.08)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: contact.isPrimary
                ? Colors.cyan.withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: contact.isPrimary
                  ? Colors.cyan.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.1),
              child: Icon(
                contact.isTestContact ? Icons.science : Icons.person,
                size: 18,
                color: contact.isTestContact ? Colors.orange : Colors.cyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        contact.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (contact.isPrimary) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PRIMARY',
                            style: TextStyle(
                              color: Colors.cyan,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.phoneNumber,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    contact.isPrimary ? 'Receives emergency call' : 'Receives SMS',
                    style: TextStyle(
                      color: contact.isPrimary
                          ? Colors.cyan.shade300
                          : Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                if (!contact.isPrimary)
                  IconButton(
                    onPressed: () => contactService.setPrimary(index),
                    icon: const Icon(Icons.star_border, size: 20),
                    color: Colors.amber,
                    tooltip: 'Set as Primary',
                  ),
                if (contact.isPrimary)
                  IconButton(
                    onPressed: null,
                    icon: const Icon(Icons.star, size: 20),
                    color: Colors.amber,
                    tooltip: 'Primary contact',
                  ),
                IconButton(
                  onPressed: () => _confirmRemove(context, contactService, index, contact.name),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade300,
                  tooltip: 'Remove',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(
      BuildContext context, ContactService contactService, int index, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Remove Contact', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove $name from trusted contacts?',
          style: TextStyle(color: Colors.grey.shade400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade400)),
          ),
          ElevatedButton(
            onPressed: () {
              contactService.removeContact(index);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showAddContactDialog(BuildContext context, ContactService contactService) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final testNumber = ContactService.testPhoneNumber;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Add Trusted Contact',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  hintText: 'e.g. Mom, Dad, Friend',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade700)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade700)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  hintText: '+91XXXXXXXXXX',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade700)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade700)),
                ),
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  phoneController.text = testNumber;
                  if (nameController.text.isEmpty) {
                    nameController.text = 'Test Contact';
                  }
                },
                child: Text('Use test number: $testNumber',
                    style: const TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey.shade400)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final phone = phoneController.text.trim();
                if (name.isEmpty || phone.isEmpty) return;
                final isTest = phone == testNumber;
                await contactService.addContact(TrustedContact(
                    name: name, phoneNumber: phone, isTestContact: isTest));
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOW IT WORKS',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.sms, 'SMS', 'All contacts receive emergency SMS with your GPS location'),
          const SizedBox(height: 6),
          _buildInfoRow(Icons.phone, 'Call', 'Only the PRIMARY contact receives an automatic phone call'),
          const SizedBox(height: 6),
          _buildInfoRow(Icons.star, 'Primary', 'Tap the star to set which contact receives the emergency call'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.cyan.shade300),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    color: Colors.cyan.shade300,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: description,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
