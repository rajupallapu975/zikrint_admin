import 'dart:async';
import '../models/order_model.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HistoryService extends ChangeNotifier {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _orderSubscription;
  final List<OrderModel> _history = [];
  List<OrderModel> get history => _history;
  
  // Track active orders to detect when they are removed (delivered)
  final Map<String, OrderModel> _activeTracker = {};

  Future<void> init() async {
    // No-op: handled in startListening
  }

  void startListening(String shopId) {
    _orderSubscription?.cancel();
    _orderSubscription = _firestore
        .collection('shops')
        .doc(shopId)
        .collection('history')
        .snapshots()
        .listen((snapshot) {
      _history.clear();
      for (var doc in snapshot.docs) {
        _history.add(OrderModel.fromFirestore(doc));
      }
      // Sort in-memory by collectedAt descending to prevent index requirement failures
      _history.sort((a, b) {
        try {
          final aDoc = snapshot.docs.firstWhere((d) => d.id == a.id);
          final bDoc = snapshot.docs.firstWhere((d) => d.id == b.id);
          final aTime = aDoc.data()['collectedAt'] as Timestamp?;
          final bTime = bDoc.data()['collectedAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        } catch (_) {
          return 0;
        }
      });
      notifyListeners();
    }, onError: (e) {
      debugPrint("Error listening to database history: $e");
    });
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  Future<void> clearHistory(String shopId) async {
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('history')
          .get();
      
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint("Error clearing database history: $e");
    }
  }
}
