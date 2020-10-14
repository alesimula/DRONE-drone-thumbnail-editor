#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <winuser.h>
#include <algorithm>

#include "flutter_window.h"
#include "run_loop.h"
#include "utils.h"

void GetScaledDesktopResolution(int& horizontal, int& vertical) {
  RECT desktop;
  const HWND hDesktop = GetDesktopWindow();

  Win32Window::Point origin(10, 10);
  const POINT target_point = {static_cast<LONG>(origin.x), static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;
  GetWindowRect(hDesktop, &desktop);

  horizontal = static_cast<int>(desktop.right / scale_factor);
  vertical = static_cast<int>(desktop.bottom / scale_factor);
}

static const int width = 600, height = 680;

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  RunLoop run_loop;
  
  int resWidth, resHeight;
  GetScaledDesktopResolution(resWidth, resHeight);
  int originX = (int)((std::max)(resWidth-width, 0)/2.5), originY = (int)((std::max)(resHeight-height, 0)/2.7);

  flutter::DartProject project(L"data");
  FlutterWindow window(&run_loop, project);
  Win32Window::Point origin(originX, originY);
  Win32Window::Size size(width, height);
  if (!window.CreateAndShow(L"drone_thumbnail_editor", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  run_loop.Run();

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
