import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBService {
  static Database? _db;
  static final _updateController = StreamController<String>.broadcast();

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Stream<String> get updates => _updateController.stream;

  static void notify(String table) {
    _updateController.add(table);
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'dormmate.db');
    return openDatabase(path, version: 20, onCreate: (db, v) async {
      await db.execute('''
          CREATE TABLE rooms (
            id TEXT PRIMARY KEY,
            ownerId TEXT,
            name TEXT,
            capacity INTEGER,
            currentOccupancy INTEGER,
            category TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');
      await db.execute('''
          CREATE TABLE tenants (
            id TEXT PRIMARY KEY,
            ownerId TEXT,
            name TEXT,
            phone TEXT,
            unit TEXT,
            addedAt TEXT,
            endoDate TEXT,
            nextDueDate TEXT,
            monthlyRent REAL DEFAULT 0.0,
            advanceDeposit REAL DEFAULT 0.0,
            synced INTEGER DEFAULT 0
          )
        ''');
      await db.execute('''
          CREATE TABLE payments (
            id TEXT PRIMARY KEY,
            tenantId TEXT,
            ownerId TEXT,
            month INTEGER,
            year INTEGER,
            amount REAL,
            status TEXT,
            category TEXT,
            paidAt TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');
      await db.execute('''
          CREATE TABLE sms_queue (
            id TEXT PRIMARY KEY,
            ownerId TEXT,
            tenantId TEXT,
            body TEXT,
            scheduledAt INTEGER,
            status TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');
      await db.execute('''
          CREATE TABLE owner_profile (
            id TEXT PRIMARY KEY,
            ownerId TEXT,
            name TEXT,
            phone TEXT,
            email TEXT,
            photoPath TEXT
          )
        ''');
      await db.execute('''
          CREATE TABLE sent_reminders (
            id TEXT PRIMARY KEY,
            tenantId TEXT,
            type TEXT,
            sentAt TEXT
          )
        ''');
      await db.execute('''
          CREATE TABLE pending_auth (
            id TEXT PRIMARY KEY,
            phone TEXT,
            otp TEXT,
            verificationId TEXT,
            step TEXT,
            updatedAt INTEGER
          )
        ''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 12) {
        await _addColumnIfNotExists(db, 'rooms', 'category', 'TEXT');
        await _addColumnIfNotExists(db, 'rooms', 'synced', 'INTEGER DEFAULT 0');
        await _addColumnIfNotExists(db, 'tenants', 'endoDate', 'TEXT');
        await _addColumnIfNotExists(db, 'tenants', 'addedAt', 'TEXT');
        await _addColumnIfNotExists(
            db, 'tenants', 'synced', 'INTEGER DEFAULT 0');
        await _addColumnIfNotExists(db, 'payments', 'ownerId', 'TEXT');
        await _addColumnIfNotExists(db, 'payments', 'paidAt', 'TEXT');
        await _addColumnIfNotExists(
            db, 'payments', 'synced', 'INTEGER DEFAULT 0');
        await _addColumnIfNotExists(db, 'owner_profile', 'phone', 'TEXT');
        await _addColumnIfNotExists(db, 'owner_profile', 'email', 'TEXT');
      }
      if (oldVersion < 15) {
        await db.execute(
            'CREATE TABLE IF NOT EXISTS sent_reminders (id TEXT PRIMARY KEY, tenantId TEXT, type TEXT, sentAt TEXT)');
      }
      if (oldVersion < 16) {
        await _addColumnIfNotExists(
            db, 'tenants', 'advanceDeposit', 'REAL DEFAULT 0.0');
      }
      if (oldVersion < 17) {
        await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_auth (
              id TEXT PRIMARY KEY,
              phone TEXT,
              otp TEXT,
              verificationId TEXT,
              step TEXT,
              updatedAt INTEGER
            )
          ''');
      }
      if (oldVersion < 18) {
        await _addColumnIfNotExists(db, 'tenants', 'nextDueDate', 'TEXT');
      }
      if (oldVersion < 19) {
        await _addColumnIfNotExists(
            db, 'tenants', 'monthlyRent', 'REAL DEFAULT 0.0');
        await _addColumnIfNotExists(db, 'payments', 'category', 'TEXT');
      }
      if (oldVersion < 20) {
        await db.execute(
            "UPDATE tenants SET addedAt = substr(addedAt, 1, 10) WHERE addedAt IS NOT NULL");
        await db.execute(
            "UPDATE payments SET paidAt = substr(paidAt, 1, 10) WHERE paidAt IS NOT NULL");
        await db.execute(
            "UPDATE sent_reminders SET sentAt = substr(sentAt, 1, 10) WHERE sentAt IS NOT NULL");
      }
    });
  }

  static Future<void> _addColumnIfNotExists(
      Database db, String table, String column, String type) async {
    try {
      final List<Map<String, dynamic>> columns =
          await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((c) => c['name'] == column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      }
    } catch (e) {
      debugPrint("Migration error: $e");
    }
  }

  static Future<void> savePendingAuth(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
        'pending_auth',
        {
          ...data,
          'id': 'current_session',
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getPendingAuth() async {
    final database = await db;
    final rows = await database
        .query('pending_auth', where: 'id = ?', whereArgs: ['current_session']);
    if (rows.isEmpty) return null;

    final data = rows.first;
    final updatedAt = data['updatedAt'] as int;
    if (DateTime.now().millisecondsSinceEpoch - updatedAt > 30 * 60 * 1000) {
      await clearPendingAuth();
      return null;
    }
    return data;
  }

  static Future<void> clearPendingAuth() async {
    final database = await db;
    await database.delete('pending_auth',
        where: 'id = ?', whereArgs: ['current_session']);
  }

  static Future<Map<String, dynamic>?> getProfileByPhone(String phone) async {
    final database = await db;
    final rows = await database.query('owner_profile',
        where: 'phone = ?', whereArgs: [phone], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<bool> wasReminderSent(String tenantId, String type) async {
    final database = await db;
    final rows = await database.query('sent_reminders',
        where: 'tenantId = ? AND type = ?', whereArgs: [tenantId, type]);
    return rows.isNotEmpty;
  }

  static Future<void> markReminderSent(String tenantId, String type) async {
    final database = await db;
    await database.insert(
        'sent_reminders',
        {
          'id': '${tenantId}_$type',
          'tenantId': tenantId,
          'type': type,
          'sentAt': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<bool> roomExists(String name, String ownerId) async {
    final database = await db;
    final rows = await database.query('rooms',
        where: 'LOWER(TRIM(name)) = ? AND ownerId = ?',
        whereArgs: [name.toLowerCase().trim(), ownerId]);
    return rows.isNotEmpty;
  }

  static Future<bool> tenantNameExists(String name, String ownerId) async {
    final database = await db;
    final rows = await database.query('tenants',
        where: 'LOWER(TRIM(name)) = ? AND ownerId = ?',
        whereArgs: [name.toLowerCase().trim(), ownerId]);
    return rows.isNotEmpty;
  }

  static Future<bool> checkEmailExists(String email) async {
    final database = await db;
    final res = await database.query('owner_profile',
        where: 'LOWER(TRIM(email)) = ?',
        whereArgs: [email.toLowerCase().trim()]);
    return res.isNotEmpty;
  }

  static Future<bool> checkUsernameExists(String name) async {
    final database = await db;
    final res = await database.query('owner_profile',
        where: 'LOWER(TRIM(name)) = ?', whereArgs: [name.toLowerCase().trim()]);
    return res.isNotEmpty;
  }

  static Future<double?> getEstablishedRoomRent(
      String roomName, String ownerId) async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT p.amount 
      FROM payments p
      JOIN tenants t ON p.tenantId = t.id
      WHERE LOWER(TRIM(t.unit)) = LOWER(TRIM(?)) AND t.ownerId = ?
      ORDER BY p.paidAt DESC LIMIT 1
    ''', [roomName, ownerId]);

    if (rows.isNotEmpty) {
      return (rows.first['amount'] as num?)?.toDouble();
    }
    return null;
  }

  static Future<void> addTenantTransaction({
    required Map<String, dynamic> tenant,
    required Map<String, dynamic> payment,
    required String roomId,
    required int newOccupancy,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      final roomRows = await txn.query('rooms',
          where: 'id = ?', whereArgs: [roomId], limit: 1);
      if (roomRows.isEmpty) throw 'Room not found.';

      final room = roomRows.first;
      final int capacity = room['capacity'] as int;
      final int current = room['currentOccupancy'] as int;

      if (current >= capacity) {
        throw 'Room Full: This room has reached its maximum capacity of $capacity.';
      }

      await txn.insert('tenants', tenant,
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('payments', payment,
          conflictAlgorithm: ConflictAlgorithm.replace);

      final actualCountRows = await txn.rawQuery(
          'SELECT COUNT(*) as cnt FROM tenants WHERE LOWER(TRIM(unit)) = LOWER(TRIM(?)) AND ownerId = ?',
          [tenant['unit'], tenant['ownerId']]);
      int actualCount = Sqflite.firstIntValue(actualCountRows) ?? 0;

      await txn.update('rooms', {'currentOccupancy': actualCount, 'synced': 0},
          where: 'id = ?', whereArgs: [roomId]);
    });

    notify('tenants');
    notify('payments');
    notify('rooms');
  }

  static Future<void> syncAllRoomOccupancies(String ownerId) async {
    final database = await db;
    await database.execute('''
      UPDATE rooms 
      SET currentOccupancy = (
        SELECT COUNT(*) FROM tenants 
        WHERE LOWER(TRIM(tenants.unit)) = LOWER(TRIM(rooms.name)) AND tenants.ownerId = rooms.ownerId
      ),
      synced = 0
      WHERE ownerId = ?
    ''', [ownerId]);
  }

  static Future<void> saveProfile(Map<String, dynamic> profile) async {
    final database = await db;
    await database.insert('owner_profile', profile,
        conflictAlgorithm: ConflictAlgorithm.replace);
    notify('owner_profile');
  }

  static Future<Map<String, dynamic>?> getProfile(String ownerId) async {
    final database = await db;
    final rows = await database.query('owner_profile',
        where: 'ownerId = ?', whereArgs: [ownerId], limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<void> insertRoom(Map<String, dynamic> room) async {
    final database = await db;
    final Map<String, dynamic> trimmedRoom = Map.from(room);
    if (trimmedRoom.containsKey('name') && trimmedRoom['name'] is String) {
      trimmedRoom['name'] = (trimmedRoom['name'] as String).trim();
    }
    await database.insert('rooms', trimmedRoom,
        conflictAlgorithm: ConflictAlgorithm.replace);
    notify('rooms');
  }

  static Future<List<Map<String, dynamic>>> getRooms(String ownerId) async {
    final database = await db;
    return database.query('rooms',
        where: 'ownerId = ?', whereArgs: [ownerId], orderBy: 'name ASC');
  }

  static Stream<List<Map<String, dynamic>>> getRoomsStream(String ownerId) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    void fetchData() async {
      try {
        await syncAllRoomOccupancies(ownerId);
        final data = await getRooms(ownerId);
        if (!controller.isClosed) controller.add(data);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    fetchData();
    final sub = updates.listen((table) {
      if (table == 'rooms' || table == 'tenants') fetchData();
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  static Future<void> deleteRoom(String id) async {
    final database = await db;
    await database.delete('rooms', where: 'id = ?', whereArgs: [id]);
    notify('rooms');
  }

  static Future<void> updateOccupancy(String id, int occupancy) async {
    final database = await db;
    await database.update('rooms', {'currentOccupancy': occupancy, 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
    notify('rooms');
  }

  static Future<void> markRoomSynced(String id) async {
    final database = await db;
    await database.update('rooms', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> insertTenant(Map<String, dynamic> tenant) async {
    final database = await db;
    await database.insert('tenants', tenant,
        conflictAlgorithm: ConflictAlgorithm.replace);
    notify('tenants');
  }

  static Future<List<Map<String, dynamic>>> getTenants(String ownerId) async {
    final database = await db;
    return database.query('tenants',
        where: 'ownerId = ?', whereArgs: [ownerId], orderBy: 'addedAt ASC');
  }

  static Future<List<Map<String, dynamic>>> getTenantsWithStatus(String ownerId,
      {String search = ''}) async {
    final database = await db;
    final args =
        search.isEmpty ? [ownerId] : [ownerId, '%${search.toLowerCase()}%'];
    final searchClause = search.isEmpty ? '' : "AND LOWER(t.name) LIKE ?";
    return database.rawQuery('''
      SELECT t.*, p.status as lastPaymentStatus, p.month as lastPaymentMonth, p.year as lastPaymentYear,
             r.capacity, r.currentOccupancy
      FROM tenants t
      LEFT JOIN payments p ON t.id = p.tenantId AND p.id = (
        SELECT id FROM payments
        WHERE tenantId = t.id AND category = 'Monthly Rent'
        ORDER BY year DESC, month DESC, paidAt DESC LIMIT 1
      )
      LEFT JOIN rooms r ON LOWER(TRIM(t.unit)) = LOWER(TRIM(r.name)) AND t.ownerId = r.ownerId
      WHERE t.ownerId = ? $searchClause
      ORDER BY t.addedAt ASC
      LIMIT 300
    ''', args);
  }

  static Stream<List<Map<String, dynamic>>> getTenantsWithStatusStream(
      String ownerId,
      {String search = ''}) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    void fetchData() async {
      try {
        await syncAllRoomOccupancies(ownerId);
        final data = await getTenantsWithStatus(ownerId, search: search);
        if (!controller.isClosed) controller.add(data);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    fetchData();
    final sub = updates.listen((table) {
      if (table == 'tenants' || table == 'payments' || table == 'rooms')
        fetchData();
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  static Future<List<Map<String, dynamic>>> getTenantsByRoomWithStatus(
      String roomName, String ownerId) async {
    final database = await db;
    return database.rawQuery('''
      SELECT t.*, p.status as lastPaymentStatus, p.month as lastPaymentMonth, p.year as lastPaymentYear
      FROM tenants t
      LEFT JOIN payments p ON t.id = p.tenantId AND p.id = (
        SELECT id FROM payments 
        WHERE tenantId = t.id AND category = 'Monthly Rent' 
        ORDER BY year DESC, month DESC, paidAt DESC LIMIT 1
      )
      WHERE LOWER(TRIM(t.unit)) = LOWER(TRIM(?)) AND t.ownerId = ?
      ORDER BY t.addedAt ASC
    ''', [roomName, ownerId]);
  }

  static Future<Map<String, dynamic>?> getTenantById(String id) async {
    final database = await db;
    final rows =
        await database.query('tenants', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  static Future<void> deleteTenant(String id) async {
    final database = await db;
    await database.delete('tenants', where: 'id = ?', whereArgs: [id]);
    notify('tenants');
  }

  static Future<void> markTenantSynced(String id) async {
    final database = await db;
    await database.update('tenants', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updateTenantRoom(
      String tenantId, String newRoomName) async {
    final database = await db;
    final tenant = await getTenantById(tenantId);
    if (tenant == null) throw 'Tenant not found';
    final ownerId = tenant['ownerId'];

    await database.transaction((txn) async {
      final roomRows = await txn.query('rooms',
          where: 'LOWER(TRIM(name)) = LOWER(TRIM(?)) AND ownerId = ?',
          whereArgs: [newRoomName.trim(), ownerId]);

      if (roomRows.isNotEmpty) {
        final room = roomRows.first;
        final int capacity = room['capacity'] as int? ?? 0;
        final int current = room['currentOccupancy'] as int? ?? 0;
        if (current >= capacity) {
          throw 'Room Full: This room has reached its maximum capacity of $capacity.';
        }
      }

      await txn.update('tenants', {'unit': newRoomName.trim(), 'synced': 0},
          where: 'id = ?', whereArgs: [tenantId]);
    });

    if (ownerId != null) {
      await syncAllRoomOccupancies(ownerId);
    }

    notify('tenants');
    notify('rooms');
  }

  static Future<void> updateAdvanceDeposit(
      String tenantId, double newAmount) async {
    final database = await db;
    await database.update('tenants', {'advanceDeposit': newAmount},
        where: 'id = ?', whereArgs: [tenantId]);
    notify('tenants');
  }

  static Future<void> updateAdvanceDepositTransaction({
    required String tenantId,
    required double updatedDeposit,
    required Map<String, dynamic> paymentRecord,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.update(
          'tenants', {'advanceDeposit': updatedDeposit, 'synced': 0},
          where: 'id = ?', whereArgs: [tenantId]);
      await txn.insert('payments', paymentRecord,
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    notify('tenants');
    notify('payments');
  }

  static Future<void> updateNextDueDate(
      String tenantId, String nextDueDate) async {
    final database = await db;
    await database.update('tenants', {'nextDueDate': nextDueDate, 'synced': 0},
        where: 'id = ?', whereArgs: [tenantId]);
    notify('tenants');
  }

  static Future<bool> hasMonthlyPayment(
      String tenantId, int month, int year) async {
    final database = await db;
    final rows = await database.query(
      'payments',
      where: 'tenantId = ? AND month = ? AND year = ? AND category = ?',
      whereArgs: [tenantId, month, year, 'Monthly Rent'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> insertPayment(Map<String, dynamic> payment) async {
    final database = await db;
    await database.insert('payments', payment,
        conflictAlgorithm: ConflictAlgorithm.replace);
    notify('payments');
  }

  static Future<void> insertPaymentAndAdvanceDueDate({
    required Map<String, dynamic> payment,
    required String tenantId,
    required String? newDueDate,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.insert('payments', payment,
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (newDueDate != null) {
        await txn.update('tenants', {'nextDueDate': newDueDate, 'synced': 0},
            where: 'id = ?', whereArgs: [tenantId]);
      }
    });
    notify('payments');
    notify('tenants');
  }

  static Future<List<Map<String, dynamic>>> getPaymentsForTenant(
      String tenantId) async {
    final database = await db;
    // Modified to group Advance Deposits at the top while keeping chronological order within groups
    return database.query('payments',
        where: 'tenantId = ?',
        whereArgs: [tenantId],
        orderBy:
            "CASE WHEN category = 'Advance Deposit' THEN 0 ELSE 1 END, year DESC, month DESC, paidAt DESC");
  }

  static Future<List<Map<String, dynamic>>> getAllPayments(
      String ownerId) async {
    final database = await db;
    return database.rawQuery('''
      SELECT p.*, t.name as tenantName, t.unit as tenantUnit, t.phone as phone
      FROM payments p
      JOIN tenants t ON p.tenantId = t.id
      WHERE t.ownerId = ?
      ORDER BY p.paidAt DESC, p.year DESC, p.month DESC
    ''', [ownerId]);
  }

  static Stream<List<Map<String, dynamic>>> getAllPaymentsStream(
      String ownerId) {
    final controller = StreamController<List<Map<String, dynamic>>>();
    void fetchData() async {
      try {
        final data = await getAllPayments(ownerId);
        if (!controller.isClosed) controller.add(data);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    fetchData();
    final sub = updates.listen((table) {
      if (table == 'payments' || table == 'tenants') fetchData();
    });
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  static Future<void> deletePayment(String id) async {
    final database = await db;
    await database.delete('payments', where: 'id = ?', whereArgs: [id]);
    notify('payments');
  }

  static Future<void> deletePaymentsTransaction(List<String> ids) async {
    final database = await db;
    await database.transaction((txn) async {
      for (var id in ids) {
        await txn.delete('payments', where: 'id = ?', whereArgs: [id]);
      }
    });
    notify('payments');
  }

  static Future<void> markPaymentSynced(String id) async {
    await (await db)
        .update('payments', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Map<String, dynamic>>> getQueuedSms() async {
    final database = await db;
    return database.query('sms_queue',
        where: 'status = ? AND synced = ?', whereArgs: ['queued', 0]);
  }

  static Future<void> cleanupOldSmsQueue() async {
    final database = await db;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await database.delete('sms_queue',
        where: 'scheduledAt < ? OR synced = 1', whereArgs: [cutoff]);
  }

  static Future<void> markSmsSynced(String id) async {
    final database = await db;
    await database.update('sms_queue', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedTenants() async {
    final database = await db;
    return database.query('tenants', where: 'synced = ?', whereArgs: [0]);
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedPayments() async {
    final database = await db;
    return database.query('payments', where: 'synced = ?', whereArgs: [0]);
  }

  static Future<Map<String, dynamic>> getMonthlyReport(
      int month, int year, String ownerId) async {
    final database = await db;

    final collectedRes = await database.rawQuery('''
      SELECT SUM(amount) as total FROM payments 
      WHERE month = ? AND year = ? AND ownerId = ? AND status = 'Paid' AND category = 'Monthly Rent'
    ''', [month, year, ownerId]);
    final double collected =
        (collectedRes.first['total'] as num?)?.toDouble() ?? 0.0;

    final tenants = await database.rawQuery('''
      SELECT t.name, t.unit, t.monthlyRent,
             (SELECT status FROM payments WHERE tenantId = t.id AND month = ? AND year = ? AND category = 'Monthly Rent' LIMIT 1) as status,
             (SELECT SUM(amount) FROM payments WHERE tenantId = t.id AND month = ? AND year = ? AND category = 'Monthly Rent' AND status = 'Paid') as paidAmount
      FROM tenants t
      WHERE t.ownerId = ?
    ''', [month, year, month, year, ownerId]);

    double expected = 0.0;
    for (var t in tenants) {
      expected += (t['monthlyRent'] as num?)?.toDouble() ?? 0.0;
    }

    double unpaid = expected - collected;
    if (unpaid < 0) unpaid = 0;

    return {
      'collected': collected,
      'expected': expected,
      'unpaid': unpaid,
      'tenants': tenants,
    };
  }
}
