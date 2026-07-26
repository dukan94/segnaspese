import '../../entities/recurring_entity.dart';
import '../../repositories/recurring_repository.dart';

/// Aggiorna una ricorrenza esistente.
class UpdateRecurring {
  UpdateRecurring(this._repository);

  final RecurringRepository _repository;

  Future<void> call(RecurringEntity recurring) {
    return _repository.update(recurring);
  }
}
