import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/repositories/restaurant_table_repository.dart';

class RestaurantTableState extends Equatable {
  final bool isLoading;
  final String selectedSection;
  final String selectedKdsStation;
  final String selectedKdsStatus;
  final List<Map<String, dynamic>> tables;
  final List<Map<String, dynamic>> kdsTickets;
  final String? errorMessage;

  const RestaurantTableState({
    this.isLoading = false,
    this.selectedSection = 'Semua',
    this.selectedKdsStation = 'all',
    this.selectedKdsStatus = 'all',
    this.tables = const [],
    this.kdsTickets = const [],
    this.errorMessage,
  });

  List<String> get availableSections {
    final set = <String>{'Semua'};
    for (final t in tables) {
      final sec = (t['section'] ?? 'Indoor').toString().trim();
      if (sec.isNotEmpty) set.add(sec);
    }
    return set.toList();
  }

  List<Map<String, dynamic>> get filteredTables {
    if (selectedSection == 'Semua') return tables;
    return tables
        .where((t) => (t['section'] ?? 'Indoor').toString().trim() == selectedSection)
        .toList();
  }

  RestaurantTableState copyWith({
    bool? isLoading,
    String? selectedSection,
    String? selectedKdsStation,
    String? selectedKdsStatus,
    List<Map<String, dynamic>>? tables,
    List<Map<String, dynamic>>? kdsTickets,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RestaurantTableState(
      isLoading: isLoading ?? this.isLoading,
      selectedSection: selectedSection ?? this.selectedSection,
      selectedKdsStation: selectedKdsStation ?? this.selectedKdsStation,
      selectedKdsStatus: selectedKdsStatus ?? this.selectedKdsStatus,
      tables: tables ?? this.tables,
      kdsTickets: kdsTickets ?? this.kdsTickets,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        selectedSection,
        selectedKdsStation,
        selectedKdsStatus,
        tables,
        kdsTickets,
        errorMessage,
      ];
}

/// Focused Domain Cubit for Restaurant Floor Operations (Open, Transfer, Merge Tables)
/// and Kitchen Display System (KDS Station Filter & Ticket Progression).
class RestaurantTableCubit extends Cubit<RestaurantTableState> {
  final RestaurantTableRepository _repository;

  RestaurantTableCubit({required RestaurantTableRepository repository})
      : _repository = repository,
        super(const RestaurantTableState());

  Future<void> loadTables() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final list = await _repository.getTables();
      emit(state.copyWith(isLoading: false, tables: list, clearError: true));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: ApiClient.extractErrorMessage(e),
      ));
    }
  }

  void selectSection(String section) {
    emit(state.copyWith(selectedSection: section));
  }

  Future<({bool ok, String? errorMessage})> openTable(
    int tableId, {
    int pax = 2,
    String? customerName,
  }) async {
    try {
      await _repository.openTable(tableId, pax: pax, customerName: customerName);
      await loadTables();
      return (ok: true, errorMessage: null);
    } catch (e) {
      return (ok: false, errorMessage: ApiClient.extractErrorMessage(e));
    }
  }

  Future<({bool ok, String? errorMessage})> transferTable({
    required int sourceTableId,
    required int destinationTableId,
  }) async {
    try {
      await _repository.transferTable(sourceTableId, destinationTableId);
      await loadTables();
      return (ok: true, errorMessage: null);
    } catch (e) {
      return (ok: false, errorMessage: ApiClient.extractErrorMessage(e));
    }
  }

  Future<({bool ok, String? errorMessage})> mergeTables({
    required int targetTableId,
    required List<int> sourceTableIds,
  }) async {
    try {
      await _repository.mergeTables(
        targetTableId: targetTableId,
        sourceTableIds: sourceTableIds,
      );
      await loadTables();
      return (ok: true, errorMessage: null);
    } catch (e) {
      return (ok: false, errorMessage: ApiClient.extractErrorMessage(e));
    }
  }

  Future<void> loadKdsQueue({String? station}) async {
    final targetStation = station ?? state.selectedKdsStation;
    emit(state.copyWith(isLoading: true, selectedKdsStation: targetStation, clearError: true));
    try {
      final tickets = await _repository.getKdsQueue(station: targetStation);
      emit(state.copyWith(isLoading: false, kdsTickets: tickets, clearError: true));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: ApiClient.extractErrorMessage(e),
      ));
    }
  }

  void selectKdsStation(String station) {
    emit(state.copyWith(selectedKdsStation: station));
  }

  void selectKdsStatus(String status) {
    emit(state.copyWith(selectedKdsStatus: status));
  }

  Future<bool> bumpKdsStatus(int saleId, String nextStatus) async {
    try {
      await _repository.updateKdsStatus(saleId, nextStatus);
      return true;
    } catch (_) {
      return false;
    }
  }
}
