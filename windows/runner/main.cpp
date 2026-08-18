#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Nome univoco per evitare collisioni con mutex di altre app.
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Tally_FinanceApp_SingleInstance_Mutex_9F2E1C";

// Classe e titolo della finestra creata sotto, in fondo a questo file
// (window.Create(L"finance_app", ...)). Servono entrambi per essere sicuri
// di trovare la NOSTRA finestra: la classe "FLUTTER_RUNNER_WIN32_WINDOW" è
// generica, la userebbe anche qualunque altra app Flutter Windows in
// esecuzione sulla stessa macchina.
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"finance_app";

// Se un'altra istanza è già in esecuzione, la porta in primo piano invece di
// aprirne una seconda in silenzio. Due istanze aperte per errore sullo
// stesso file finance_app.sqlite hanno già causato una migrazione dello
// schema interrotta a metà (v. CLAUDE.md, "Migrazioni schema locale —
// insidia").
void ActivateExistingInstance() {
  HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
  if (existing == nullptr) {
    return;
  }
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  }
  ::SetForegroundWindow(existing);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Il mutex resta volutamente aperto per tutta la vita del processo (mai
  // CloseHandle qui): Windows lo rilascia da solo alla chiusura, anche in
  // caso di crash, così una seconda istanza non resta bloccata per sempre
  // da un mutex "orfano".
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance();
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"finance_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
