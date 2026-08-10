import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/review_schedule_models.dart';

class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime? createdAt;
  final String? relatedScheduleId;
  final String? relatedHelpRequestId;
  final String? relatedMessageId;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    this.createdAt,
    this.relatedScheduleId,
    this.relatedHelpRequestId,
    this.relatedMessageId,
  });

  factory AppNotification.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return AppNotification(
      id: document.id,
      userId: data['userId']?.toString() ?? '',
      type: data['type']?.toString() ?? 'general',
      title: data['title']?.toString() ?? 'Notification',
      message: data['message']?.toString() ?? '',
      isRead: data['isRead'] as bool? ?? false,
      createdAt: firestoreDate(data['createdAt']),
      relatedScheduleId: data['relatedScheduleId']?.toString(),
      relatedHelpRequestId: data['relatedHelpRequestId']?.toString(),
      relatedMessageId: data['relatedMessageId']?.toString(),
    );
  }
}

class NotificationService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  NotificationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get _currentUserId {
    final id = _auth.currentUser?.uid;
    if (id == null) throw StateError('User is not signed in.');
    return id;
  }

  Stream<List<AppNotification>> watchCurrentUserNotifications() {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: _currentUserId)
        .snapshots()
        .map((snapshot) {
      final rows = snapshot.docs
          .map(AppNotification.fromDocument)
          .toList(growable: false);
      rows.sort((a, b) {
        final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
      return rows;
    });
  }

  Future<void> markRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllRead(Iterable<AppNotification> notifications) async {
    final unread = notifications.where((item) => !item.isRead).toList();
    if (unread.isEmpty) return;
    final batch = _firestore.batch();
    for (final notification in unread) {
      batch.update(
        _firestore.collection('notifications').doc(notification.id),
        {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
  }
}
