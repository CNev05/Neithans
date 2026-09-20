import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/db_service.dart';
import '../services/sms_service.dart';
import '../utils/toast.dart';

class TenantDetailScreen extends StatefulWidget {
  final String tenantId;
  const TenantDetailScreen({super.key, required this.tenantId});

  @override
  State<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends State<TenantDetailScreen> {
  final _uuid = const Uuid();
  Map<String, dynamic>? _tenant;
  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: '₱', decimalDigits: 0);
  bool _isSendingSms = false;
  Future<List<Map<String, dynamic>>>? _paymentsFuture;

  Future<void> _load() async {
    final tenant = await DBService.getTenantById(widget.tenantId);
    if (tenant != null) {
      final payments = await DBService.getPaymentsForTenant(widget.tenantId);
      final lastMonthlyPayment = payments.firstWhere(
        (p) => p['category'] == 'Monthly Rent',
        orElse: () => {},
      );

      setState(() {
        _tenant = Map<String, dynamic>.from(tenant);
        if (lastMonthlyPayment.isNotEmpty) {
          _tenant!['lastPaymentStatus'] = lastMonthlyPayment['status'];
          _tenant!['lastPaymentMonth'] = lastMonthlyPayment['month'];
          _tenant!['lastPaymentYear'] = lastMonthlyPayment['year'];
        } else {
          _tenant!['lastPaymentStatus'] = 'Unpaid';
        }
        _paymentsFuture = DBService.getPaymentsForTenant(widget.tenantId);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showCustomToast(String message, {bool isError = true}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  String _formatDateTime(String? dateStr, {String defaultValue = "N/A"}) {
    if (dateStr == null || dateStr.isEmpty) return defaultValue;
    final trimmed = dateStr.trim();
    final dt = DateTime.tryParse(trimmed);
    if (dt != null) {
      return DateFormat('MMM dd, yyyy').format(dt);
    }
    return dateStr;
  }

  bool _isOverdue(Map<String, dynamic>? t) {
    if (t == null || t['addedAt'] == null) return false;
    try {
      final addedAt = DateTime.parse(t['addedAt']);
      final now = DateTime.now();
      final dueDay = addedAt.day;

      final lastMonth = t['lastPaymentMonth'] as int?;
      final lastYear = t['lastPaymentYear'] as int?;
      final lastStatus = t['lastPaymentStatus'] as String?;

      if (lastStatus == 'Paid' &&
          lastMonth == now.month &&
          lastYear == now.year) {
        return false;
      }

      if (now.day > dueDay) return true;
    } catch (e) {
      debugPrint("Error checking overdue: $e");
    }
    return false;
  }

  void _sendReminder() async {
    if (_tenant == null || _isSendingSms) return;
    final name = _tenant!['name'];
    final phone = _tenant!['phone'].toString();
    final month = DateFormat('MMMM').format(DateTime.now());
    final defaultMsg =
        "Dear $name, this is a formal notice from Neithans. Our records indicate that your rent payment for $month remains outstanding. Kindly settle your balance directly with your landlord at your earliest convenience. Important: Neithans does not collect payments online. If anyone requests online payment on our behalf, please treat it as a scam. Please disregard this message if payment has already been made. Thank you.";

    final msg = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              _SendReminderScreen(name: name, defaultMessage: defaultMsg)),
    );
    if (msg == null || !mounted) return;

    setState(() => _isSendingSms = true);
    final success = await SmsService.sendSms(to: phone, message: msg);
    if (mounted) {
      setState(() => _isSendingSms = false);
      if (success) {
        _showCustomToast('Reminder sent to $name', isError: false);
        await DBService.markReminderSent(widget.tenantId, 'due_soon');
      } else {
        _showCustomToast('Opening local SMS app...');
        final smsUri = Uri(
            scheme: 'sms',
            path: phone.replaceAll(' ', ''),
            queryParameters: <String, String>{'body': msg});
        if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
      }
    }
  }

  void _addPayment() async {
    final monthlyRent = (_tenant?['monthlyRent'] as num?)?.toDouble() ?? 0;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (_) => _RecordPaymentScreen(
                monthlyRent: monthlyRent,
                tenantId: widget.tenantId,
                currencyFormat: _currencyFormat,
              )),
    );
    if (result == null) return;

    try {
      final tenantCheck = await DBService.getTenantById(widget.tenantId);
      if (tenantCheck == null) {
        _showCustomToast(
            'Tenant no longer exists. Please go back and refresh.');
        return;
      }

      final selectedMonth = result['month'] as int;
      final selectedYear = result['year'] as int;

      String? newDueDate;
      final nextDueDateStr = _tenant?['nextDueDate'] as String?;
      if (nextDueDateStr != null && nextDueDateStr != 'Not set') {
        try {
          final dueDate = DateFormat('yyyy-MM-dd').parse(nextDueDateStr);
          if (dueDate.month == selectedMonth && dueDate.year == selectedYear) {
            newDueDate = DateFormat('yyyy-MM-dd')
                .format(DateTime(dueDate.year, dueDate.month + 1, dueDate.day));
          }
        } catch (_) {}
      }

      await DBService.insertPaymentAndAdvanceDueDate(
        payment: {
          'id': _uuid.v4(),
          'tenantId': widget.tenantId,
          'ownerId': _tenant?['ownerId'],
          'month': selectedMonth,
          'year': selectedYear,
          'amount': result['amount'] as double,
          'status': 'Paid',
          'category': 'Monthly Rent',
          'paidAt': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'synced': 0,
        },
        tenantId: widget.tenantId,
        newDueDate: newDueDate,
      );
      _showCustomToast('Payment recorded successfully.', isError: false);
      _load();
    } catch (e) {
      _showCustomToast('Failed: $e');
    }
  }

  void _manageAdvanceDeposit() async {
    final currentDeposit =
        (_tenant?['advanceDeposit'] as num?)?.toDouble() ?? 0;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
          builder: (_) => _ManageDepositScreen(
                currentDeposit: currentDeposit,
                currencyFormat: _currencyFormat,
              )),
    );
    if (result == null) return;

    try {
      final amount = result['amount'] as double;
      final isDeducting = result['isDeducting'] as bool;
      final freshTenant = await DBService.getTenantById(widget.tenantId);
      final fresh = (freshTenant?['advanceDeposit'] as num?)?.toDouble() ?? 0.0;
      if (isDeducting && amount > fresh) {
        _showCustomToast('Insufficient deposit balance.');
        return;
      }
      double updated = isDeducting ? (fresh - amount) : (fresh + amount);
      if (updated < 0) updated = 0;
      final now = DateTime.now();
      await DBService.updateAdvanceDepositTransaction(
        tenantId: widget.tenantId,
        updatedDeposit: updated,
        paymentRecord: {
          'id': _uuid.v4(),
          'tenantId': widget.tenantId,
          'ownerId': _tenant?['ownerId'],
          'amount': isDeducting ? -amount : amount,
          'month': now.month,
          'year': now.year,
          'status': 'Paid',
          'category': 'Advance Deposit',
          'paidAt': DateFormat('yyyy-MM-dd').format(now),
          'synced': 0,
        },
      );
      _load();
      _showCustomToast('Deposit updated.', isError: false);
    } catch (e) {
      _showCustomToast('Failed: $e');
    }
  }

  void _transferRoom() async {
    final uid = _tenant?['ownerId'];
    if (uid == null) return;
    final rooms = await DBService.getRooms(uid);
    final screenContext = context;

    // ignore: use_build_context_synchronously
    final newRoom = await Navigator.push<String>(
      screenContext,
      MaterialPageRoute(
          builder: (_) => _TransferRoomScreen(
                rooms: rooms,
                currentRoom: _tenant?['unit'] as String?,
              )),
    );
    if (newRoom == null || newRoom == _tenant?['unit'] || !mounted) return;

    try {
      await DBService.updateTenantRoom(widget.tenantId, newRoom);
      _showCustomToast('Transferred successfully.', isError: false);
      _load();
    } catch (e) {
      _showCustomToast('Failed to transfer.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tenant == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final isOverdue = _isOverdue(_tenant);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        title: Text(_tenant!['name'] ?? 'Tenant Details',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2D2D2D)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Remove Tenant',
            onPressed: () async {
              final dialogContext = context;
              final confirm = await showDialog<bool>(
                context: dialogContext,
                builder: (c) => AlertDialog(
                  title: const Text('Remove Tenant',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  content: Text(
                      'Are you sure you want to remove ${_tenant!['name']}? This will permanently delete all their payment records.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Remove',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (confirm == true && dialogContext.mounted) {
                await DBService.deleteTenant(widget.tenantId);
                if (Navigator.of(dialogContext).mounted) {
                  // ignore: use_build_context_synchronously
                  Navigator.pop(dialogContext);
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTenantHeader(isOverdue),
              const SizedBox(height: 24),
              _buildActionGrid(),
              const SizedBox(height: 24),
              const Text('Payment History',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D2D2D))),
              const SizedBox(height: 12),
              _buildPaymentHistory(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTenantHeader(bool isOverdue) {
    final status = _tenant!['lastPaymentStatus'] ?? 'Unpaid';
    final lastMonth = _tenant!['lastPaymentMonth'] as int? ?? 0;
    final lastYear = _tenant!['lastPaymentYear'] as int? ?? 0;
    final now = DateTime.now();
    final isPaidThisCycle =
        status == 'Paid' && lastMonth == now.month && lastYear == now.year;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                  radius: 35,
                  backgroundColor: const Color(0xFFEADFD4),
                  child: Text(
                      ((_tenant!['name'] as String?)?.isNotEmpty == true
                              ? _tenant!['name'][0]
                              : '?')
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8B6E5C)))),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_tenant!['name'],
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('Unit: ${_tenant!['unit'] ?? "N/A"}',
                          style:
                              TextStyle(fontSize: 16, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              _buildStatusBadge(isPaidThisCycle, isOverdue),
            ],
          ),
          const Divider(height: 32),
          _buildInfoRow(
              Icons.phone_outlined, 'Contact', _tenant!['phone'] ?? 'N/A'),
          _buildInfoRow(Icons.calendar_today_outlined, 'Added On',
              _formatDateTime(_tenant!['addedAt'])),
          _buildInfoRow(Icons.event_busy_outlined, 'Contract End',
              _formatDateTime(_tenant!['endoDate'])),
          _buildInfoRow(Icons.monetization_on_outlined, 'Monthly Rent',
              _currencyFormat.format(_tenant!['monthlyRent'] ?? 0)),
          _buildInfoRow(
              Icons.account_balance_wallet_outlined,
              'Advance Deposit',
              _currencyFormat.format(_tenant!['advanceDeposit'] ?? 0)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isPaid, bool isOverdue) {
    Color bgColor = isPaid
        ? Colors.green[50]!
        : (isOverdue ? Colors.red[50]! : Colors.orange[50]!);
    Color textColor = isPaid
        ? Colors.green[700]!
        : (isOverdue ? Colors.red[700]! : Colors.orange[700]!);
    String text = isPaid ? 'Paid' : (isOverdue ? 'Overdue' : 'Unpaid');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Text(text,
          style: TextStyle(
              color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8B6E5C)),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            flex: 6,
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF2D2D2D)),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: [
        _buildActionButton(Icons.add_card, 'Record Payment', _addPayment),
        _buildActionButton(
            Icons.notifications_outlined, 'Send Reminder', _sendReminder,
            isLoading: _isSendingSms),
        _buildActionButton(Icons.account_balance_wallet, 'Manage Deposit',
            _manageAdvanceDeposit),
        _buildActionButton(
            Icons.transfer_within_a_station, 'Transfer Room', _transferRoom),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap,
      {bool isLoading = false}) {
    return ElevatedButton(
      onPressed: isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF8B6E5C),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Colors.grey[200]!)),
          padding: const EdgeInsets.symmetric(horizontal: 12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (isLoading)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF8B6E5C)))
        else
          Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _buildPaymentHistory() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _paymentsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        // Deduplicate by payment id in case of sync artifacts
        final seen = <String>{};
        final payments = snapshot.data!
            .where((p) => seen.add(p['id'] as String? ?? ''))
            .toList();
        if (payments.isEmpty) {
          return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child:
                  const Center(child: Text('No payment history available.')));
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: payments.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final p = payments[index];
            final isMonthly = p['category'] == 'Monthly Rent';
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: isMonthly ? Colors.blue[50] : Colors.orange[50],
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(
                        isMonthly ? Icons.calendar_month : Icons.savings,
                        color: isMonthly ? Colors.blue : Colors.orange,
                        size: 20)),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          isMonthly
                              ? '${DateFormat('MMMM').format(DateTime(0, p['month']))} ${p['year']}'
                              : 'Advance Deposit',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                      Text(_formatDateTime(p['paidAt']),
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ])),
                Text(_currencyFormat.format(p['amount'] ?? 0),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
              ]),
            );
          },
        );
      },
    );
  }
}

// ─── Send Reminder Screen ────────────────────────────────────────────────────

class _SendReminderScreen extends StatefulWidget {
  final String name;
  final String defaultMessage;
  const _SendReminderScreen({required this.name, required this.defaultMessage});

  @override
  State<_SendReminderScreen> createState() => _SendReminderScreenState();
}

class _SendReminderScreenState extends State<_SendReminderScreen> {
  late final TextEditingController _msgCtl;

  @override
  void initState() {
    super.initState();
    _msgCtl = TextEditingController(text: widget.defaultMessage);
  }

  @override
  void dispose() {
    _msgCtl.dispose();
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
        title: Text('Reminder for ${widget.name}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D)),
            overflow: TextOverflow.ellipsis),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Edit message before sending:',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: _msgCtl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B6E5C),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final msg = _msgCtl.text.trim();
                  if (msg.isNotEmpty) Navigator.pop(context, msg);
                },
                child: const Text('Send SMS',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Record Payment Screen ───────────────────────────────────────────────────

class _RecordPaymentScreen extends StatefulWidget {
  final double monthlyRent;
  final String tenantId;
  final NumberFormat currencyFormat;
  const _RecordPaymentScreen({
    required this.monthlyRent,
    required this.tenantId,
    required this.currencyFormat,
  });

  @override
  State<_RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<_RecordPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtl = TextEditingController();
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;

  @override
  void dispose() {
    _amountCtl.dispose();
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
        title: const Text('Record Payment',
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
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _month,
                      decoration: const InputDecoration(
                          labelText: 'Month',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white),
                      items: List.generate(12, (i) => i + 1)
                          .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(
                                  DateFormat('MMMM').format(DateTime(0, m)))))
                          .toList(),
                      onChanged: (v) => setState(() => _month = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _year,
                      decoration: const InputDecoration(
                          labelText: 'Year',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white),
                      items: [
                        DateTime.now().year - 1,
                        DateTime.now().year,
                        DateTime.now().year + 1
                      ]
                          .map((y) => DropdownMenuItem(
                              value: y, child: Text(y.toString())))
                          .toList(),
                      onChanged: (v) => setState(() => _year = v!),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtl,
                  decoration: InputDecoration(
                    labelText: 'Amount Paid',
                    prefixText: '₱',
                    helperText: widget.monthlyRent > 0
                        ? 'Minimum: ${widget.currencyFormat.format(widget.monthlyRent)}'
                        : null,
                    border: const OutlineInputBorder(),
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
                    final amount = double.tryParse(v) ?? 0;
                    if (amount <= 0) {
                      return 'Amount must be greater than ₱0';
                    }
                    if (widget.monthlyRent > 0 && amount < widget.monthlyRent) {
                      return 'Cannot be less than monthly rent (${widget.currencyFormat.format(widget.monthlyRent)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B6E5C),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    final screenContext = context;
                    final isDuplicate = await DBService.hasMonthlyPayment(
                        widget.tenantId, _month, _year);
                    if (isDuplicate && screenContext.mounted) {
                      final confirm = await showDialog<bool>(
                        context: screenContext,
                        builder: (c) => AlertDialog(
                          title: const Text('Duplicate Payment'),
                          content: Text(
                              'A Monthly Rent payment for ${DateFormat('MMMM yyyy').format(DateTime(_year, _month))} already exists. Record another one?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Record Anyway')),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                    }
                    if (screenContext.mounted) {
                      // ignore: use_build_context_synchronously
                      Navigator.pop(screenContext, {
                        'month': _month,
                        'year': _year,
                        'amount': double.parse(_amountCtl.text),
                      });
                    }
                  },
                  child: const Text('Confirm Payment',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Manage Deposit Screen ───────────────────────────────────────────────────

class _ManageDepositScreen extends StatefulWidget {
  final double currentDeposit;
  final NumberFormat currencyFormat;
  const _ManageDepositScreen(
      {required this.currentDeposit, required this.currencyFormat});

  @override
  State<_ManageDepositScreen> createState() => _ManageDepositScreenState();
}

class _ManageDepositScreenState extends State<_ManageDepositScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtl = TextEditingController();
  bool _isDeducting = false;

  @override
  void dispose() {
    _amountCtl.dispose();
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
        title: const Text('Manage Deposit',
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Current Deposit: ${widget.currencyFormat.format(widget.currentDeposit)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF8B6E5C)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                      child: ChoiceChip(
                    label: const Center(child: Text('Add')),
                    selected: !_isDeducting,
                    onSelected: (_) => setState(() => _isDeducting = false),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: ChoiceChip(
                    label: const Center(child: Text('Deduct')),
                    selected: _isDeducting,
                    onSelected: (_) => setState(() => _isDeducting = true),
                  )),
                ]),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtl,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₱',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7)
                  ],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final val = double.tryParse(v) ?? 0;
                    if (val <= 0) return 'Amount must be greater than ₱0';
                    if (val > 999999) return 'Amount cannot exceed ₱999,999';
                    if (_isDeducting && val > widget.currentDeposit)
                      return 'Insufficient balance';
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B6E5C),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      Navigator.pop(context, {
                        'amount': double.parse(_amountCtl.text),
                        'isDeducting': _isDeducting,
                      });
                    }
                  },
                  child: const Text('Save Changes',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Transfer Room Screen ────────────────────────────────────────────────────

class _TransferRoomScreen extends StatefulWidget {
  final List<Map<String, dynamic>> rooms;
  final String? currentRoom;
  const _TransferRoomScreen({required this.rooms, this.currentRoom});

  @override
  State<_TransferRoomScreen> createState() => _TransferRoomScreenState();
}

class _TransferRoomScreenState extends State<_TransferRoomScreen> {
  String? _selectedRoom;

  @override
  void initState() {
    super.initState();
    _selectedRoom = widget.currentRoom;
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
        title: const Text('Transfer Room',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Select a new unit for this tenant:',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: widget.rooms.any((r) => r['name'] == _selectedRoom)
                  ? _selectedRoom
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white),
              items: widget.rooms
                  .map((r) => DropdownMenuItem<String>(
                      value: r['name'], child: Text(r['name'] ?? 'Unknown')))
                  .toList(),
              onChanged: (val) => setState(() => _selectedRoom = val),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B6E5C),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _selectedRoom == null
                  ? null
                  : () => Navigator.pop(context, _selectedRoom),
              child: const Text('Confirm Transfer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
