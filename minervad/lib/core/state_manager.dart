import 'event_bus.dart';

/// Gestore dello stato globale di Minerva Desktop.
/// Mantiene lo stato in memoria e notifica l'Event Bus ad ogni cambiamento.
///
/// ── Qui dentro c'era l'elenco delle finestre, e nessuno lo leggeva ────────
///
/// Costava questo, a ogni finestra aperta o chiusa e a ogni cambio di
/// scrivania: un `getWorkspaces()` al compositore — cioè un giro di IPC che
/// fa elencare a Hyprland tutti i suoi client — e poi l'elenco completo
/// spedito in JSON a ognuno dei processi di Minerva collegati.
///
/// Nessuno di quei processi lo apriva. Le finestre la shell le riceve da
/// `FinestreService` (`windows_state`), che è un'altra strada, più recente e
/// più ricca; questa era rimasta accesa sotto, a fare lo stesso lavoro per il
/// cestino. Non si vedeva perché non rompeva niente: consumava e basta.
///
/// Ora l'elenco lo si compone **quando qualcuno lo chiede** (`get_state`, che
/// è l'API dei plugin), e qui resta solo ciò che costa zero: quale scrivania
/// è attiva, che arriva già dentro l'evento del compositore.
class StateManager {
  final EventBus _eventBus;
  final int _version = 1;
  int _activeWorkspace = 1;
  final List<Map<String, dynamic>> _workspaceProfiles = [];

  StateManager(this._eventBus);

  int get version => _version;
  int get activeWorkspace => _activeWorkspace;

  /// Aggiorna il workspace attivo e notifica il cambiamento.
  void setActiveWorkspace(int id) {
    if (_activeWorkspace != id) {
      _activeWorkspace = id;
      _notifyStateChanged('workspace_active_changed');
    }
  }

  /// Lo stato che non costa niente. Le finestre le aggiunge chi risponde a
  /// `get_state`, perché per averle bisogna chiederle al compositore.
  Map<String, dynamic> toJson() => {
        'version': _version,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'workspace_active': _activeWorkspace,
        'workspace_profiles': _workspaceProfiles,
      };

  void _notifyStateChanged(String reason) {
    _eventBus.publish(MinervaEvent(
      type: 'state_changed',
      payload: {
        'reason': reason,
        'state': toJson(),
      },
    ));
  }
}
