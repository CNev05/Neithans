import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/db_service.dart';

class PaymentReportScreen extends StatefulWidget {
  final String ownerId;
  const PaymentReportScreen({super.key, required this.ownerId});

  @override
  State<PaymentReportScreen> createState() => _PaymentReportScreenState();
}

class _PaymentReportScreenState extends State<PaymentReportScreen> {
  DateTime _selectedDate = DateTime.now();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        title: const Text('Monthly Report'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_month, color: Color(0xFF8B6E5C)),
            label: Text(DateFormat('MMM yyyy').format(_selectedDate), style: const TextStyle(color: Color(0xFF8B6E5C))),
            onPressed: _selectMonthYear,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: DBService.getMonthlyReport(_selectedDate.month, _selectedDate.year, widget.ownerId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final report = snapshot.data!;
          final List tenants = report['tenants'];

          return Column(
            children: [
              _buildSummaryCard(report),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('Tenant Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tenants.length,
                  itemBuilder: (context, index) {
                    final t = tenants[index];
                    final bool isPaid = t['status'] == 'Paid';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(t['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Unit: ${t['unit'] ?? 'N/A'}', overflow: TextOverflow.ellipsis),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_currencyFormat.format(t['monthlyRent'] ?? 0),
                              style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isPaid ? Colors.green : Colors.red).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isPaid ? 'Paid' : 'Unpaid',
                                style: TextStyle(color: isPaid ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> report) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF8B6E5C),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryItem('Total Expected', report['expected'], Colors.white70),
              _buildSummaryItem('Collected', report['collected'], Colors.white),
            ],
          ),
          const Divider(color: Colors.white24, height: 32),
          _buildSummaryItem('Total Unpaid', report['unpaid'], Colors.orangeAccent, large: true),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, dynamic value, Color color, {bool large = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12)),
        Text(
          _currencyFormat.format(value ?? 0),
          style: TextStyle(color: color, fontSize: large ? 24 : 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Future<void> _selectMonthYear() async {
    int tempMonth = _selectedDate.month;
    int tempYear = _selectedDate.year;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Select Month & Year', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Year row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: tempYear > 2020 ? () => setDialogState(() => tempYear--) : null,
                  ),
                  Text('$tempYear', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: tempYear < DateTime.now().year ? () => setDialogState(() => tempYear++) : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Month grid
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2,
                children: List.generate(12, (i) {
                  final month = i + 1;
                  final isSelected = month == tempMonth;
                  return GestureDetector(
                    onTap: () => setDialogState(() => tempMonth = month),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF8B6E5C) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        DateFormat('MMM').format(DateTime(0, month)),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B6E5C), foregroundColor: Colors.white),
              onPressed: () {
                setState(() => _selectedDate = DateTime(tempYear, tempMonth));
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}
