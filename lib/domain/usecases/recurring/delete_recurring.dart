import '../../repositories/recurring_repository.dart';

/// Elimina (soft delete) una ricorrenza.
class DeleteRecurring {
  DeleteRecurring(this._repository);

  final RecurringRepository _repository;

  Future<void> call(int id) {
    return _repository.delete(id);
  }
}
