import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../services/sms_service.dart';
import '../utils/toast.dart';
import 'tenant_detail.dart';
import 'tenants_list.dart';
import 'payment_report_screen.dart';
import 'package:uuid/uuid.dart';

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthService>(context, listen: false);
      final sync = Provider.of<SyncService>(context, listen: false);
      if (auth.currentUserUid != null) {
        sync.syncAll(auth.currentUserUid!).catchError((e) => debugPrint("Sync error: $e"));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final uid = auth.currentUserUid ?? 'unknown';

    final List<Widget> pages = <Widget>[
      RoomsDashboard(ownerId: uid),
      PaymentsDashboard(ownerId: uid),
      ProfilePage(ownerId: uid),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        elevation: 0,
        backgroundColor: const Color(0xFFFFF5F2),
        selectedItemColor: const Color(0xFF8B6E5C),
        unselectedItemColor: Colors.black45,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Rooms'),
          BottomNavigationBarItem(icon: Icon(Icons.payments_outlined), activeIcon: Icon(Icons.payments), label: 'Payments'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class RoomsDashboard extends StatefulWidget {
  final String ownerId;
  const RoomsDashboard({super.key, required this.ownerId});

  @override
  State<RoomsDashboard> createState() => _RoomsDashboardState();
}

class _RoomsDashboardState extends State<RoomsDashboard> {
  String _searchQuery = '';
  bool _isSortAscending = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF5F2),
        title: const Text('Rooms'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isSortAscending ? Icons.sort : Icons.sort_outlined, color: const Color(0xFF8B6E5C)),
            onPressed: () => setState(() => _isSortAscending = !_isSortAscending),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline, color: Color(0xFF8B6E5C)), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TenantsListScreen(uid: widget.ownerId)))
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Search rooms...', 
                prefixIcon: Icon(Icons.search, color: Color(0xFF8B6E5C)),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DBService.getRoomsStream(widget.ownerId),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final allRooms = snap.data ?? [];
                
                final filteredRooms = allRooms.where((r) {
                  final name = r['name']?.toString() ?? '';
                  return name.toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();

                filteredRooms.sort((a, b) {
                  final String s1 = a['name']?.toString().toLowerCase() ?? '';
                  final String s2 = b['name']?.toString().toLowerCase() ?? '';
                  int result = s1.compareTo(s2);
                  return _isSortAscending ? result : -result;
                });

                if (filteredRooms.isEmpty) {
                  return const Center(child: Text('No rooms found.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: filteredRooms.length,
                  itemBuilder: (context, index) {
                    final room = filteredRooms[index];
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoomTenantsScreen(roomName: room['name'], ownerId: widget.ownerId))),
                        title: Text(room['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Occupancy: ${room['currentOccupancy'] ?? 0} / ${room['capacity'] ?? 0}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteRoom(room['id']),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRoom,
        backgroundColor: const Color(0xFF8B6E5C),
        label: const Text('Room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _addRoom() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddRoomDialog(ownerId: widget.ownerId),
    );
  }

  void _deleteRoom(String roomId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFFFFF5F2),
        title: const Text('Delete Room'),
        content: const Text('Delete this room?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await DBService.deleteRoom(roomId);
    }
  }
}

class _AddRoomDialog extends StatefulWidget {
  final String ownerId;
  const _AddRoomDialog({required this.ownerId});

  @override
  State<_AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<_AddRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _capacityCtl = TextEditingController();
  final _uuid = const Uuid();
  bool _isProcessing = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _capacityCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Add New Room', style: TextStyle(fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtl,
                maxLength: 15,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Room Name', isDense: true, counterText: ""),
                enabled: !_isProcessing,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityCtl,
                decoration: const InputDecoration(labelText: 'Capacity', isDense: true, hintText: '1-10'),
                enabled: !_isProcessing,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final cap = int.tryParse(v) ?? 0;
                  if (cap < 1 || cap > 10) return 'Enter 1-10';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isProcessing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isProcessing ? null : () async {
            if (!_formKey.currentState!.validate()) return;
            final screenContext = context;
            setState(() => _isProcessing = true);
            try {
              if (await DBService.roomExists(_nameCtl.text, widget.ownerId)) {
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  AppToast.show(screenContext, 'Room already exists!', isError: true);
                }
                setState(() => _isProcessing = false);
                return;
              }
              await DBService.insertRoom({
                'id': _uuid.v4(),
                'ownerId': widget.ownerId,
                'name': _nameCtl.text.trim(),
                'capacity': int.parse(_capacityCtl.text),
                'currentOccupancy': 0,
                'category': 'Dorm',
              });
              if (screenContext.mounted) Navigator.pop(screenContext, true);
            } catch (e) {
              setState(() => _isProcessing = false);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class RoomTenantsScreen extends StatefulWidget {
  final String roomName;
  final String ownerId;
  const RoomTenantsScreen({super.key, required this.roomName, required this.ownerId});

  @override
  State<RoomTenantsScreen> createState() => _RoomTenantsScreenState();
}

class _RoomTenantsScreenState extends State<RoomTenantsScreen> {
  StreamSubscription? _dbSub;

  @override
  void initState() {
    super.initState();
    _dbSub = DBService.updates.listen((table) {
      if (table == 'tenants' || table == 'payments') setState(() {});
    });
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      appBar: AppBar(backgroundColor: const Color(0xFFFFF5F2), title: Text('Room: ${widget.roomName}')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DBService.getTenantsByRoomWithStatus(widget.roomName, widget.ownerId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final tenants = snap.data ?? [];
          if (tenants.isEmpty) return const Center(child: Text('Empty Room'));
          return ListView.builder(
            itemCount: tenants.length,
            itemBuilder: (context, index) {
              final t = tenants[index];
              final rawEndo = t['endoDate'] as String?;
              final endoDisplay = rawEndo != null && rawEndo.isNotEmpty
                  ? (() {
                      final dt = DateTime.tryParse(rawEndo);
                      return dt != null ? DateFormat('MMM dd, yyyy').format(dt) : rawEndo;
                    })()
                  : 'N/A';

              return Card(
                color: Colors.white,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TenantDetailScreen(tenantId: t['id']))),
                  title: Text(t['name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF8B6E5C)),
                          const SizedBox(width: 6),
                          Flexible(child: Text(t['phone'] ?? 'N/A',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
                              overflow: TextOverflow.ellipsis)),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.event_outlined, size: 14, color: Color(0xFF8B6E5C)),
                          const SizedBox(width: 6),
                          Text('Contract ends $endoDisplay',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF444444))),
                        ]),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF8B6E5C)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PaymentsDashboard extends StatefulWidget {
  final String ownerId;
  const PaymentsDashboard({super.key, required this.ownerId});

  @override
  State<PaymentsDashboard> createState() => _PaymentsDashboardState();
}

class _PaymentsDashboardState extends State<PaymentsDashboard> {
  String _searchQuery = '';
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

  void _showTenantPaymentHistory(String tenantId, String tenantName, String? phone) async {
    final payments = await DBService.getPaymentsForTenant(tenantId);
    bool recentReminder = false;
    try {
      recentReminder = await DBService.wasReminderSent(tenantId, 'due_soon');
    } catch (_) {}
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Indicator for Automatic Reminders
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: Colors.green),
                  const SizedBox(width: 8),
                  const Flexible(child: Text("Automatic 7-3-0 day reminders active",
                       style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                       overflow: TextOverflow.ellipsis)),
                  if (recentReminder) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                      child: const Text("SENT", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF8B6E5C).withValues(alpha: 0.1),
                  child: Text(tenantName[0].toUpperCase(), style: const TextStyle(color: Color(0xFF8B6E5C), fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tenantName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                      if (phone != null) Text(phone, style: const TextStyle(color: Colors.grey, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Payment History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (payments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No payment history found.'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: payments.length,
                itemBuilder: (context, idx) {
                  final p = payments[idx];
                  final isAdvance = p['category'] == 'Advance Deposit';
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(isAdvance ? Icons.stars : Icons.check_circle, color: isAdvance ? Colors.orange : Colors.green, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAdvance ? 'Advance Deposit' : "${DateFormat('MMMM').format(DateTime(0, p['month'] ?? 1))} ${p['year'] ?? ''}",
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (isAdvance) Text('Initial Payment', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                ],
                              )),
                            ],
                          ),
                        ),
                        Text(
                          _currencyFormat.format(p['amount'] ?? 0),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.send_outlined, size: 20, color: Color(0xFF8B6E5C)),
                          tooltip: 'Send Receipt',
                          onPressed: () async {
                            final toastContext = context;
                            if (phone == null || phone.isEmpty) {
                              if (toastContext.mounted) {
                                AppToast.show(toastContext, 'No phone number available for this tenant.');
                              }
                              return;
                            }
                            final month = isAdvance ? 'Advance Deposit' : DateFormat('MMMM').format(DateTime(0, p['month'] ?? 1));
                            final amount = _currencyFormat.format(p['amount'] ?? 0);
                            final message = 'Dear $tenantName, this is an official payment confirmation from Neithans. We have received your payment of $amount for $month. Thank you for settling promptly. For any concerns, please coordinate directly with your landlord. We appreciate your continued trust in Neithans.';

                            final success = await SmsService.sendSms(to: phone, message: message);
                            if (toastContext.mounted) {
                              AppToast.show(toastContext,
                                success ? 'Receipt sent successfully!' : 'Failed to send receipt.',
                                isError: !success);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF5F2),
                  foregroundColor: const Color(0xFF8B6E5C),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TenantDetailScreen(tenantId: tenantId)));
                },
                child: const Text('View Full Profile', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF5F2), 
        title: const Text('Payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Color(0xFF8B6E5C)),
            tooltip: 'Monthly Report',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentReportScreen(ownerId: widget.ownerId))),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search tenant name...',
                prefixIcon: Icon(Icons.search, color: Color(0xFF8B6E5C)),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DBService.getAllPaymentsStream(widget.ownerId),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final allPayments = snap.data ?? [];

                // Group by tenant — one card per tenant, sorted by latest payment
                final Map<String, Map<String, dynamic>> tenantMap = {};
                for (final p in allPayments) {
                  final tid = p['tenantId'] as String? ?? '';
                  final name = (p['tenantName'] ?? 'Unknown') as String;
                  if (!name.toLowerCase().contains(_searchQuery.toLowerCase())) continue;
                  if (!tenantMap.containsKey(tid)) {
                    tenantMap[tid] = {
                      'tenantId': tid,
                      'tenantName': name,
                      'tenantUnit': p['tenantUnit'],
                      'phone': p['phone'],
                      'paymentCount': 1,
                      'latestPaidAt': p['paidAt'],
                      'latestAmount': p['amount'],
                      'latestCategory': p['category'],
                    };
                  } else {
                    tenantMap[tid]!['paymentCount'] = (tenantMap[tid]!['paymentCount'] as int) + 1;
                  }
                }
                final tenants = tenantMap.values.toList();

                if (tenants.isEmpty) return const Center(child: Text('No records.'));

                return ListView.builder(
                  itemCount: tenants.length,
                  itemBuilder: (context, index) {
                    final t = tenants[index];
                    final count = t['paymentCount'] as int;
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        onTap: () => _showTenantPaymentHistory(
                          t['tenantId'], t['tenantName'] ?? 'Unknown', t['phone']),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFEADFD4),
                          child: Text(
                            ((t['tenantName'] as String?)?.isNotEmpty == true
                                ? (t['tenantName'] as String)[0]
                                : '?').toUpperCase(),
                            style: const TextStyle(color: Color(0xFF8B6E5C), fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(t['tenantName'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          'Unit: ${t['tenantUnit'] ?? "N/A"} • $count payment${count == 1 ? "" : "s"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8B6E5C)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  final String ownerId;
  const ProfilePage({super.key, required this.ownerId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _name = 'Owner';
  String _phone = 'Not Set';
  String _email = 'Not Set';
  String? _photoPath;
  final _picker = ImagePicker();
  StreamSubscription? _dbSub;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _dbSub = DBService.updates.listen((table) {
      if (table == 'owner_profile') _loadProfile();
    });
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await DBService.getProfile(widget.ownerId);
    if (profile != null) {
      if (mounted) {
        setState(() {
          _name = profile['name'] ?? 'Owner';
          _phone = profile['phone'] ?? 'Not Set';
          _email = profile['email'] ?? 'Not Set';
          _photoPath = profile['photoPath'];
        });
      }
    }
  }

  Future<void> _pickAndCropImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: const Color(0xFF8B6E5C),
            toolbarWidgetColor: Colors.white,
            statusBarLight: false,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
        ],
      );
      if (croppedFile != null) {
        setState(() => _photoPath = croppedFile.path);
        await DBService.saveProfile({
          'id': widget.ownerId,
          'ownerId': widget.ownerId,
          'name': _name,
          'phone': _phone,
          'email': _email,
          'photoPath': _photoPath,
        });
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'Failed to update photo. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF5F2),
        title: const Text('My profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Stack(
              children: [
                CircleAvatar(
                  radius: 60, 
                  backgroundColor: const Color(0xFF8B6E5C).withValues(alpha: 0.1),
                  backgroundImage: _photoPath != null ? FileImage(File(_photoPath!)) : null, 
                  child: _photoPath == null ? const Icon(Icons.person, size: 60, color: Colors.blueGrey) : null
                ),
                Positioned(
                  bottom: 0, right: 0, 
                  child: GestureDetector(
                    onTap: _pickAndCropImage, 
                    child: const CircleAvatar(
                      radius: 18, backgroundColor: Color(0xFF8B6E5C), 
                      child: Icon(Icons.edit, color: Colors.white, size: 18)
                    )
                  )
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(_name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(_phone, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 32),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red), 
                    title: const Text('Sign Out', style: TextStyle(color: Colors.red)), 
                    onTap: () async => await Provider.of<AuthService>(context, listen: false).signOut(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
