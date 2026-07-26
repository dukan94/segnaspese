import '../../repositories/recurring_repository.dart';

/// Mette in pausa o riattiva una ricorrenza. In pausa non genera più
/// transazioni finché non viene riattivata.
class SetRecurringActive {
  SetRecurringActive(this._repository);

  final RecurringRepository _repository;

  Future<void> call(int id, bool active) {
    return _repository.setActive(id, active);
  }
}
