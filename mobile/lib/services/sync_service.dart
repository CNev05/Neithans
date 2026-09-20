import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'db_service.dart';

class SyncService {
  final _fire = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  
  final ValueNotifier<bool> isSyncing = ValueNotifier(false);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  StreamSubscription? _paymentsSub;
  StreamSubscription? _roomsSub;
  StreamSubscription? _tenantsSub;
  StreamSubscription? _profileSub;
  StreamSubscription? _adminSub;

  Future<void> _mutate(String collection, Map<String, dynamic> values,
      {String? id}) async {
    await _functions.httpsCallable('mutateRecord').call({
      'collection': collection,
      'id': id,
      'values': values,
    });
  }

  void stopAllListeners() {
    _paymentsSub?.cancel();
    _roomsSub?.cancel();
    _tenantsSub?.cancel();
    _profileSub?.cancel();
    _adminSub?.cancel();
  }

  void startRealtimeSync(String ownerId) {
    stopAllListeners();

    // 0. Admin Listener
    _startAdminListener(ownerId);

    // 1. Real-time Profile
    _profileSub = _fire.collection('owners')
      .doc(ownerId)
      .snapshots()
      .listen((doc) async {
        final data = doc.data();
        if (data != null) {
          await DBService.saveProfile({
            'id': ownerId,
            'ownerId': ownerId,
            'name': data['name'],
            'phone': data['phone'],
            'email': data['email'],
            'photoPath': data['photoPath'],
          });
        }
      });

    // 2. Real-time Payments
    _paymentsSub = _fire.collection('payments')
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .listen((snap) async {
        for (var change in snap.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;
          if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
            await DBService.insertPayment({
              'id': change.doc.id,
              'tenantId': data['tenantId'],
              'ownerId': data['ownerId'],
              'month': data['month'],
              'year': data['year'],
              'amount': data['amount'],
              'status': data['status'],
              'category': data['category'],
              'paidAt': data['paidAt'],
              'synced': 1,
            });
          } else if (change.type == DocumentChangeType.removed) {
            await (await DBService.db).delete('payments', where: 'id = ?', whereArgs: [change.doc.id]);
            DBService.notify('payments');
          }
        }
      });

    // 3. Real-time Rooms
    _roomsSub = _fire.collection('rooms')
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .listen((snap) async {
        for (var change in snap.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;
          if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
            await DBService.insertRoom({
              'id': change.doc.id,
              'ownerId': data['ownerId'],
              'name': data['name'],
              'capacity': data['capacity'],
              'currentOccupancy': data['currentOccupancy'],
              'category': data['category'],
              'synced': 1,
            });
          } else if (change.type == DocumentChangeType.removed) {
            await (await DBService.db).delete('rooms', where: 'id = ?', whereArgs: [change.doc.id]);
            DBService.notify('rooms');
          }
        }
      });

    // 4. Real-time Tenants
    _tenantsSub = _fire.collection('tenants')
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .listen((snap) async {
        for (var change in snap.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;
          if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
            await DBService.insertTenant({
              'id': change.doc.id,
              'ownerId': data['ownerId'],
              'name': data['name'],
              'phone': data['phone'],
              'unit': data['unit'],
              'addedAt': data['addedAt'],
              'endoDate': data['endoDate'],
              'nextDueDate': data['nextDueDate'],
              'monthlyRent': data['monthlyRent'],
              'advanceDeposit': data['advanceDeposit'],
              'synced': 1,
            });
          } else if (change.type == DocumentChangeType.removed) {
            await (await DBService.db).delete('tenants', where: 'id = ?', whereArgs: [change.doc.id]);
            DBService.notify('tenants');
          }
        }
      });
  }

  void _startAdminListener(String userId) {
    _adminSub = _fire.collection('admins')
      .doc(userId)
      .snapshots()
      .listen((doc) {
        if (doc.exists) {
          final data = doc.data();
          if (kDebugMode && data?['role'] == 'super_admin') {
            debugPrint("Logged in as Super Admin");
          }
        }
      });
  }

  Future<void> syncProfile(String ownerId) async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) return;

    // First try to fetch from remote to local
    final remoteDoc = await _fire.collection('owners').doc(ownerId).get();
    if (remoteDoc.exists) {
      final data = remoteDoc.data()!;
      await DBService.saveProfile({
        'id': ownerId,
        'ownerId': ownerId,
        'name': data['name'],
        'phone': data['phone'],
        'email': data['email'],
        'photoPath': data['photoPath'],
      });
    } else {
      // If doesn't exist remotely, push local to remote
      final profile = await DBService.getProfile(ownerId);
      if (profile != null) {
        await _mutate('owners', {
          'ownerId': ownerId,
          'name': profile['name'],
          'phone': profile['phone'],
          'email': profile['email'],
          'photoPath': profile['photoPath'],
          'updatedAt': FieldValue.serverTimestamp(),
        }, id: ownerId);
      }
    }
  }

  Future<void> syncRooms(String ownerId) async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) return;

    final rooms = await DBService.getRooms(ownerId);
    for (final r in rooms) {
      if (r['synced'] == 0) {
        await _mutate('rooms', {
          'ownerId': r['ownerId'],
          'name': r['name'],
          'capacity': r['capacity'],
          'currentOccupancy': r['currentOccupancy'],
          'category': r['category'],
          'updatedAt': FieldValue.serverTimestamp(),
        }, id: r['id']);
        await DBService.markRoomSynced(r['id']);
      }
    }
  }

  Future<void> syncQueuedSms() async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) return;

    final queued = await DBService.getQueuedSms();
    for (final q in queued) {
      final doc = {
        'ownerId': q['ownerId'],
        'tenantId': q['tenantId'],
        'body': q['body'],
        'scheduledAt': Timestamp.fromMillisecondsSinceEpoch(q['scheduledAt']),
        'status': 'queued',
        'createdAt': Timestamp.now(),
      };
      await _mutate('sms_queue', doc, id: q['id']);
      await DBService.markSmsSynced(q['id']);
    }
  }

  Future<void> syncTenants(String ownerId) async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) return;

    final unsynced = await DBService.getUnsyncedTenants();
    for (final t in unsynced) {
      if (t['ownerId'] == ownerId) {
        await _mutate('tenants', {
          'ownerId': t['ownerId'],
          'name': t['name'],
          'phone': t['phone'],
          'unit': t['unit'],
          'addedAt': t['addedAt'],
          'endoDate': t['endoDate'],
          'nextDueDate': t['nextDueDate'],
          'monthlyRent': t['monthlyRent'],
          'advanceDeposit': t['advanceDeposit'],
          'updatedAt': FieldValue.serverTimestamp(),
        }, id: t['id']);
        await DBService.markTenantSynced(t['id']);
      }
    }
  }

  Future<void> syncPayments(String ownerId) async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) return;

    final unsynced = await DBService.getUnsyncedPayments();
    for (final p in unsynced) {
      await _mutate('payments', {
        'tenantId': p['tenantId'],
        'ownerId': p['ownerId'] ?? ownerId,
        'month': p['month'],
        'year': p['year'],
        'amount': p['amount'],
        'status': p['status'],
        'category': p['category'],
        'paidAt': p['paidAt'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, id: p['id']);
      await DBService.markPaymentSynced(p['id']);
    }
  }

  Future<void> syncAll(String ownerId) async {
    if (isSyncing.value) return;
    
    try {
      isSyncing.value = true;
      lastError.value = null;
      
      await syncProfile(ownerId);
      await syncRooms(ownerId);
      await syncTenants(ownerId);
      await syncPayments(ownerId);
      await syncQueuedSms();
      await DBService.cleanupOldSmsQueue();
      
      if (kDebugMode) debugPrint("Manual sync completed for $ownerId");
    } catch (e) {
      if (kDebugMode) debugPrint("Sync Error: $e");
      lastError.value = e.toString();
    } finally {
      isSyncing.value = false;
    }
  }
}
