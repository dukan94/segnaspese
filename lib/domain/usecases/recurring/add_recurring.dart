import '../../entities/recurring_entity.dart';
import '../../repositories/recurring_repository.dart';

/// Crea una nuova ricorrenza.
class AddRecurring {
  AddRecurring(this._repository);

  final RecurringRepository _repository;

  Future<int> call(RecurringEntity recurring) {
    return _repository.add(recurring);
  }
}
