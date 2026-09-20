import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/db_service.dart';
import '../services/auth_service.dart';
import '../services/sms_service.dart';
import '../utils/toast.dart';
import 'tenant_detail.dart';

class TenantsListScreen extends StatefulWidget {
  final String? uid;
  const TenantsListScreen({super.key, this.uid});

  @override
  State<TenantsListScreen> createState() => _TenantsListScreenState();
}

class _TenantsListScreenState extends State<TenantsListScreen> {
  final _uuid = const Uuid();
  bool _isProcessing = false;
  String _searchQuery = '';
  Timer? _debounce;
  late String _uid;

  @override
  void initState() {
    super.initState();
    _uid = widget.uid ??
        Provider.of<AuthService>(context, listen: false).currentUserUid ??
        '';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _showPopup(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }

  bool _isOverdue(Map<String, dynamic> tenant) {
    final now = DateTime.now();
    final int lastMonth = tenant['lastPaymentMonth'] as int? ?? 0;
    final int lastYear = tenant['lastPaymentYear'] as int? ?? 0;
    final String lastStatus = tenant['lastPaymentStatus'] ?? 'Unpaid';

    if (lastStatus == 'Paid' &&
        lastMonth == now.month &&
        lastYear == now.year) {
      return false;
    }

    final String? addedAtStr = tenant['addedAt'];
    if (addedAtStr == null) return false;

    try {
      final addedAt = DateTime.parse(addedAtStr);
      if (now.day > addedAt.day) {
        return true;
      }
    } catch (e) {
      debugPrint("Error checking overdue: $e");
    }
    return false;
  }

  void _sendQuickReminder(Map<String, dynamic> tenant) async {
    final screenContext = context;
    final name = tenant['name'] ?? 'Tenant';
    final phone = tenant['phone']?.toString() ?? '';
    if (phone.isEmpty) {
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'No phone number found for this tenant.');
      }
      return;
    }

    final month = DateFormat('MMMM').format(DateTime.now());
    final message =
        "Hi $name, this is a manual reminder from Neithans. Our records show your rent for $month is currently unpaid. Please ignore if payment was recently made.";

    final success = await SmsService.sendSms(to: phone, message: message);
    if (screenContext.mounted) {
      if (success) {
        AppToast.show(screenContext, 'Reminder sent to $name', isError: false);
        await DBService.markReminderSent(tenant['id'], 'manual_list');
      } else {
        AppToast.show(screenContext, 'Opening local SMS app...',
            isError: false);
        final Uri smsUri = Uri(
          scheme: 'sms',
          path: phone.replaceAll(' ', ''),
          queryParameters: <String, String>{'body': message},
        );
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
        }
      }
    }
  }

  void _showAddTenantModal(String uid) async {
    final rooms = await DBService.getRooms(uid);
    if (!mounted) return;

    if (rooms.isEmpty) {
      _showPopup('No Rooms', 'Please add a room first before adding tenants.');
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (_) => AddTenantScreen(rooms: rooms, uid: uid)),
    );

    if (result == null) return;
    if (_isProcessing) return;

    await _saveTenantToDatabase(uid, result);
  }

  void _showAddRoomDialog() async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddRoomStandaloneDialog(ownerId: _uid),
    );
    if (success == true && mounted) {
      AppToast.show(context, 'Room added successfully!', isError: false);
    }
  }

  Future<void> _saveTenantToDatabase(
      String uid, Map<String, dynamic> result) async {
    setState(() => _isProcessing = true);
    try {
      final roomName = result['roomName'];
      final roomId = result['roomId'];

      final tenantId = _uuid.v4();
      final now = DateTime.now();

      final tenant = {
        'id': tenantId,
        'ownerId': uid,
        'name': result['name'],
        'phone': result['phone'],
        'unit': roomName,
        'monthlyRent': result['monthlyRent'],
        'advanceDeposit': result['advanceDeposit'],
        'endoDate': (result['endoDate'] as DateTime).toIso8601String(),
        'addedAt': DateFormat('yyyy-MM-dd').format(now),
        'synced': 0,
      };

      final payment = {
        'id': _uuid.v4(),
        'tenantId': tenantId,
        'ownerId': uid,
        'amount': result['advanceDeposit'],
        'month': now.month,
        'year': now.year,
        'status': 'Paid',
        'category': 'Advance Deposit',
        'paidAt': DateFormat('yyyy-MM-dd').format(now),
        'synced': 0,
      };

      await DBService.addTenantTransaction(
        tenant: tenant,
        payment: payment,
        roomId: roomId,
        newOccupancy: (result['currentOccupancy'] as int) + 1,
      );

      final confirmationMessage =
          'Hi ${tenant['name']}, you have been successfully added to Room $roomName at Neithans today, ${DateFormat('MMMM d, yyyy').format(now)}. Welcome!';
      final smsSent = await SmsService.sendSms(
        to: tenant['phone'].toString(),
        message: confirmationMessage,
      );

      if (mounted) {
        AppToast.show(context, "Tenant ${result['name']} added successfully!",
            isError: false);
        if (!smsSent) {
          AppToast.show(
              context, 'Tenant added, but confirmation SMS could not be sent.');
        }
      }
    } catch (e) {
      debugPrint("Add Tenant Error: $e");
      if (mounted) {
        _showPopup(
            'Error',
            e.toString().contains('Full')
                ? e.toString()
                : 'Failed to add tenant. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('User not authenticated.')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text('Tenants',
            style: TextStyle(
                color: Color(0xFF2D2D2D), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Add Room',
            icon: const Icon(Icons.add_home_outlined, color: Color(0xFF8B6E5C)),
            onPressed: _showAddRoomDialog,
          ),
          IconButton(
            tooltip: 'Add Tenant',
            icon:
                const Icon(Icons.person_add_outlined, color: Color(0xFF8B6E5C)),
            onPressed: () => _showAddTenantModal(_uid),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_searchQuery),
              stream: DBService.getTenantsWithStatusStream(_uid,
                  search: _searchQuery),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF8B6E5C)));
                }

                final tenants = snapshot.data ?? [];

                if (tenants.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: tenants.length,
                  itemBuilder: (context, index) {
                    final tenant = tenants[index];
                    return _buildTenantCard(tenant);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.white,
      child: TextField(
        onChanged: (v) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), () {
            if (mounted) setState(() => _searchQuery = v);
          });
        },
        decoration: InputDecoration(
          hintText: 'Search tenants or rooms...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: const Color(0xFFF3F3F3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No tenants yet' : 'No tenants found',
            style: TextStyle(
                color: Colors.grey[600],
                fontSize: 18,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (_searchQuery.isEmpty)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _showAddRoomDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF8B6E5C),
                    side: const BorderSide(color: Color(0xFF8B6E5C)),
                  ),
                  child: const Text('Add Room'),
                ),
                ElevatedButton(
                  onPressed: () => _showAddTenantModal(_uid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B6E5C),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Add Tenant',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTenantCard(Map<String, dynamic> tenant) {
    final String name = tenant['name'] ?? 'Unknown';
    final String unit = tenant['unit'] ?? 'N/A';
    final String status = tenant['lastPaymentStatus'] ?? 'Unpaid';

    final now = DateTime.now();
    final int lastMonth = tenant['lastPaymentMonth'] as int? ?? 0;
    final int lastYear = tenant['lastPaymentYear'] as int? ?? 0;

    final bool isPaidThisCycle =
        status == 'Paid' && lastMonth == now.month && lastYear == now.year;
    final bool isOverdue = _isOverdue(tenant);

    final int capacity = tenant['capacity'] ?? 0;
    final int occupancy = tenant['currentOccupancy'] ?? 0;
    final bool isFull = capacity > 0 && occupancy >= capacity;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEADFD4),
          child: Text(name[0].toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFF8B6E5C), fontWeight: FontWeight.bold)),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.door_front_door_outlined,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(unit,
                        style: const TextStyle(color: Colors.grey),
                        overflow: TextOverflow.ellipsis)),
                if (capacity > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isFull ? Colors.red : Colors.green)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "$occupancy/$capacity",
                      style: TextStyle(
                        fontSize: 10,
                        color: isFull ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isPaidThisCycle)
              IconButton(
                icon: Icon(Icons.notifications_active_outlined,
                    color: isOverdue ? Colors.red : Colors.orange, size: 22),
                tooltip: 'Remind',
                onPressed: () => _sendQuickReminder(tenant),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isPaidThisCycle
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isPaidThisCycle ? 'Paid' : 'Unpaid',
                style: TextStyle(
                  color:
                      isPaidThisCycle ? Colors.green[700] : Colors.orange[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => TenantDetailScreen(tenantId: tenant['id'])),
        ),
      ),
    );
  }
}

class AddTenantScreen extends StatefulWidget {
  final List<Map<String, dynamic>> rooms;
  final String uid;
  const AddTenantScreen({super.key, required this.rooms, required this.uid});

  @override
  State<AddTenantScreen> createState() => _AddTenantScreenState();
}

class _AddTenantScreenState extends State<AddTenantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _amountCtl = TextEditingController();
  final _monthlyCtl = TextEditingController();
  DateTime? _selectedEndoDate;
  String? _selectedRoomId;
  bool _isVerifyingRent = false;

  @override
  void initState() {
    super.initState();
    try {
      final available = widget.rooms.firstWhere(
          (r) => (r['currentOccupancy'] ?? 0) < (r['capacity'] ?? 0));
      _selectedRoomId = available['id'];
    } catch (_) {
      if (widget.rooms.isNotEmpty) _selectedRoomId = widget.rooms.first['id'];
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _amountCtl.dispose();
    _monthlyCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF2D2D2D)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add New Tenant',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    LengthLimitingTextInputFormatter(50),
                  ],
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : (v.trim().length < 3 ? 'Too short' : null),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Contact Number',
                    prefixText: '+63 ',
                    hintText: '9XXXXXXXXX',
                    prefixIcon: Icon(Icons.phone_android_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  onChanged: (value) {
                    if (value.startsWith('0')) {
                      _phoneCtl.text = value.substring(1);
                      _phoneCtl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _phoneCtl.text.length));
                    }
                  },
                  validator: AuthService.validatePhone,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedRoomId,
                  decoration: const InputDecoration(
                    labelText: 'Assign Room',
                    prefixIcon: Icon(Icons.door_front_door_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: widget.rooms.map((r) {
                    final int cap = r['capacity'] ?? 0;
                    final int occ = r['currentOccupancy'] ?? 0;
                    final bool isFull = occ >= cap;
                    return DropdownMenuItem<String>(
                      value: r['id'] as String,
                      enabled: !isFull,
                      child: Text(
                        "${r['name'] ?? 'Room'} ($occ/$cap)",
                        style: TextStyle(
                          color: isFull ? Colors.red : Colors.green,
                          fontWeight:
                              isFull ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedRoomId = val),
                  validator: (v) {
                    if (v == null) return 'Required';
                    final room = widget.rooms.firstWhere((r) => r['id'] == v);
                    if ((room['currentOccupancy'] ?? 0) >=
                        (room['capacity'] ?? 0)) return 'Room is full';
                    return null;
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 18, color: Color(0xFF8B6E5C)),
                      SizedBox(width: 8),
                      Text('Contract Details',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF8B6E5C))),
                      Expanded(child: Divider(indent: 12)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null)
                      setState(() => _selectedEndoDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Endo Date',
                      prefixIcon: Icon(Icons.event_outlined, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12))),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    child: Text(
                      _selectedEndoDate == null
                          ? 'Select Date'
                          : DateFormat('MMM dd, yyyy')
                              .format(_selectedEndoDate!),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _monthlyCtl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Monthly Rent',
                          prefixText: '₱ ',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12))),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6)
                        ],
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _amountCtl,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Advance Deposit',
                          prefixText: '₱ ',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12))),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6)
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final advance = double.tryParse(v) ?? 0;
                          final monthly =
                              double.tryParse(_monthlyCtl.text) ?? 0;
                          if (advance < monthly) return 'Min ₱$monthly';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B6E5C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _isVerifyingRent
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            if (_selectedEndoDate == null) {
                              AppToast.show(
                                  context, 'Please select an Endo Date');
                              return;
                            }
                            final room = widget.rooms.firstWhere(
                                (r) => r['id'] == _selectedRoomId,
                                orElse: () => {});
                            if (room.isEmpty) return;

                            final monthlyRent =
                                double.tryParse(_monthlyCtl.text) ?? 0.0;

                            setState(() => _isVerifyingRent = true);
                            final establishedRent =
                                await DBService.getEstablishedRoomRent(
                                    room['name'], widget.uid);
                            setState(() => _isVerifyingRent = false);

                            if (context.mounted &&
                                establishedRent != null &&
                                establishedRent != monthlyRent) {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Rent Inconsistency'),
                                  content: Text(
                                      'Other tenants in ${room['name']} pay ₱${establishedRent.toStringAsFixed(0)}. Are you sure you want to set a different rent for this tenant?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Edit Rent')),
                                    TextButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child:
                                            const Text('Confirm Difference')),
                                  ],
                                ),
                              );
                              if (confirm != true) return;
                            }

                            if (context.mounted) {
                              Navigator.pop(context, {
                                'name': _nameCtl.text.trim(),
                                'phone': '+63 ${_phoneCtl.text.trim()}',
                                'roomId': _selectedRoomId,
                                'roomName': room['name'],
                                'currentOccupancy': room['currentOccupancy'],
                                'capacity': room['capacity'],
                                'endoDate': _selectedEndoDate,
                                'monthlyRent': monthlyRent,
                                'advanceDeposit':
                                    double.tryParse(_amountCtl.text) ?? 0.0,
                              });
                            }
                          },
                    child: _isVerifyingRent
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Add Tenant',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddRoomStandaloneDialog extends StatefulWidget {
  final String ownerId;
  const _AddRoomStandaloneDialog({required this.ownerId});

  @override
  State<_AddRoomStandaloneDialog> createState() =>
      _AddRoomStandaloneDialogState();
}

class _AddRoomStandaloneDialogState extends State<_AddRoomStandaloneDialog> {
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
      title: const Text('Add New Room',
          style: TextStyle(fontWeight: FontWeight.bold)),
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
                decoration: const InputDecoration(
                    labelText: 'Room Name', isDense: true, counterText: ""),
                enabled: !_isProcessing,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityCtl,
                decoration: const InputDecoration(
                    labelText: 'Capacity', isDense: true, hintText: '1-10'),
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
        TextButton(
            onPressed: _isProcessing ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isProcessing
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  final screenContext = context;
                  setState(() => _isProcessing = true);
                  try {
                    if (await DBService.roomExists(
                        _nameCtl.text, widget.ownerId)) {
                      if (mounted) {
                        // ignore: use_build_context_synchronously
                        AppToast.show(screenContext, 'Room already exists!',
                            isError: true);
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
                    if (screenContext.mounted)
                      Navigator.pop(screenContext, true);
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
