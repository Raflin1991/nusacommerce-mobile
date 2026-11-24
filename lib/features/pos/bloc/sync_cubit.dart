import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/database/offline_database.dart';
import 'pos_cubit.dart';

class SyncState extends Equatable {
  final bool isOnline;
  final bool isSyncingOfflineQueue;
  final bool isInitialRestoring;
  final double initialRestoreProgress;
  final String? initialRestoreStep;
  final String activeNodeCode;
  final int offlinePendingCount;
  final List<Map<String, dynamic>> localSyncConflicts;
  final List<Map<String, dynamic>> deadLetterItems;

  const SyncState({
    this.isOnline = true,
    this.isSyncingOfflineQueue = false,
    this.isInitialRestoring = false,
    this.initialRestoreProgress = 0.0,
    this.initialRestoreStep,
    this.activeNodeCode = 'M01',
    this.offlinePendingCount = 0,
    this.localSyncConflicts = const [],
    this.deadLetterItems = const [],
  });

  factory SyncState.fromPosState(PosState s) {
    return SyncState(
      isOnline: s.isOnline,
      isSyncingOfflineQueue: s.isSyncingOfflineQueue,
      isInitialRestoring: s.isInitialRestoring,
      initialRestoreProgress: s.initialRestoreProgress,
      initialRestoreStep: s.initialRestoreStep,
      activeNodeCode: s.activeNodeCode,
      offlinePendingCount: s.offlinePendingCount,
      localSyncConflicts: s.localSyncConflicts,
      deadLetterItems: s.deadLetterItems,
    );
  }

  @override
  List<Object?> get props => [
        isOnline,
        isSyncingOfflineQueue,
        isInitialRestoring,
        initialRestoreProgress,
        initialRestoreStep,
        activeNodeCode,
        offlinePendingCount,
        localSyncConflicts,
        deadLetterItems,
      ];
}

/// Focused Domain Cubit for Offline-Online Sync Queue, Dead-Letter Queue (DLQ),
/// Conflict Resolution, and OXORA Edge / Cloud Connectivity Telemetry.
class SyncCubit extends Cubit<SyncState> {
  final PosCubit _posCubit;
  final OfflineDatabase _offlineDb;
  StreamSubscription<PosState>? _posSub;

  SyncCubit({
    required PosCubit posCubit,
    required OfflineDatabase offlineDb,
  })  : _posCubit = posCubit,
        _offlineDb = offlineDb,
        super(SyncState.fromPosState(posCubit.state)) {
    _posSub = _posCubit.stream.listen((next) {
      if (!isClosed) emit(SyncState.fromPosState(next));
    });
  }

  OfflineDatabase get offlineDb => _offlineDb;

  Future<void> syncWithCloud({bool force = true, bool preserveActiveCart = true}) {
    return _posCubit.syncWithCloud(force: force, preserveActiveCart: preserveActiveCart);
  }

  Future<int> flushOfflineQueue() => _posCubit.syncOfflineTransactions();

  void refreshPendingBadges() => _posCubit.refreshOfflinePendingState();

  Future<({bool success, String? errorMessage})> retryDeadLetter(
    String id, {
    Map<String, dynamic>? payloadOverrides,
  }) {
    return _posCubit.retryDeadLetterItem(id, payloadOverrides: payloadOverrides);
  }

  Future<void> discardDeadLetter(String id) => _posCubit.discardDeadLetterItem(id);

  Future<bool> retryConflict(String localUuid) => _posCubit.retryOfflineSyncConflict(localUuid);

  Future<bool> resolveStockConflict({required String localUuid, required bool approveOversell}) {
    return _posCubit.resolveOfflineStockConflict(
      localUuid: localUuid,
      approveOversell: approveOversell,
    );
  }

  @override
  Future<void> close() async {
    await _posSub?.cancel();
    return super.close();
  }
}
