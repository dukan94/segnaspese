/// `updatedAt` fisso e volutamente vecchio assegnato a categorie,
/// sottocategorie e regole di default create da `runSeed` (M52), invece di
/// "adesso".
///
/// Bug reale (23 set 2026): i default hanno `syncId` deterministici, uguali
/// su ogni dispositivo (v. default_categories_seed.dart). Con `updatedAt` =
/// "adesso", la prima sync di un dispositivo appena installato spingeva sul
/// server quelle righe come le più recenti, e il last-write-wins
/// dell'upsert resuscitava (`is_deleted = 0`) categorie già unite/eliminate
/// da un altro dispositivo — che poi ricomparivano anche su tutti gli altri.
/// Con un timestamp anteriore a qualunque modifica reale, lo stato già
/// presente sul server vince sempre, sia al push sia al pull; su un server
/// vuoto i default vengono comunque inseriti (il push li seleziona: la
/// filigrana iniziale è l'epoch).
///
/// Serve anche a riconoscere una riga di default mai modificata
/// dall'utente: v. `TursoSyncService._discardPristineSeedIfJoiningExistingRemote`.
/// Precisione al secondo, come Drift salva le date (secondi Unix): il
/// confronto per uguaglianza in SQL resta esatto.
final DateTime kDefaultSeedUpdatedAt = DateTime.utc(2000, 1, 1);
