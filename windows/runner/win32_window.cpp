#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <objbase.h>
#include <shobjidl.h>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

// Private message used to re-apply the icons once a show has fully completed.
constexpr UINT kReapplyIconsMessage = WM_APP + 0x4A1;

// Re-applies the app icon (big + small) to the window and to the window class.
// Windows can drop the taskbar button icon (it turns blank/white) when a hidden
// window is shown again or when the taskbar is re-created, so this is called at
// those points.
void ApplyWindowIcons(HWND hwnd) {
  if (!hwnd) {
    return;
  }
  HINSTANCE instance = GetModuleHandle(nullptr);
  HICON big_icon = static_cast<HICON>(
      LoadImage(instance, MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
                GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON),
                LR_SHARED));
  HICON small_icon = static_cast<HICON>(
      LoadImage(instance, MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
                GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
                LR_SHARED));
  if (big_icon) {
    SendMessage(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(big_icon));
    SetClassLongPtr(hwnd, GCLP_HICON, reinterpret_cast<LONG_PTR>(big_icon));
  }
  if (small_icon) {
    SendMessage(hwnd, WM_SETICON, ICON_SMALL,
                reinterpret_cast<LPARAM>(small_icon));
    SetClassLongPtr(hwnd, GCLP_HICONSM, reinterpret_cast<LONG_PTR>(small_icon));
  }
}

// Property keys of System.AppUserModel.* (fmtid 9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3).
const PROPERTYKEY kPkeyRelaunchCommand = {
    {0x9F4C2855, 0x9F79, 0x4B39,
     {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}},
    2};
const PROPERTYKEY kPkeyRelaunchIconResource = {
    {0x9F4C2855, 0x9F79, 0x4B39,
     {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}},
    3};
const PROPERTYKEY kPkeyRelaunchDisplayName = {
    {0x9F4C2855, 0x9F79, 0x4B39,
     {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}},
    4};
const PROPERTYKEY kPkeyAppUserModelId = {
    {0x9F4C2855, 0x9F79, 0x4B39,
     {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}},
    5};

bool SetStringProperty(IPropertyStore* store, const PROPERTYKEY& key,
                       const std::wstring& value) {
  PROPVARIANT pv;
  PropVariantInit(&pv);
  const size_t bytes = (value.size() + 1) * sizeof(wchar_t);
  pv.vt = VT_LPWSTR;
  pv.pwszVal = static_cast<LPWSTR>(CoTaskMemAlloc(bytes));
  if (!pv.pwszVal) {
    return false;
  }
  memcpy(pv.pwszVal, value.c_str(), bytes);
  HRESULT hr = store->SetValue(key, pv);
  PropVariantClear(&pv);
  return SUCCEEDED(hr);
}

// Gives the window its own taskbar identity (AppUserModelID) together with an
// explicit icon. Without this the taskbar button can borrow the icon of the
// Start-menu shortcut that the notifications plugin creates for the process,
// and that icon can be blank, which shows up as a white icon after the window
// was hidden to the tray and shown again.
void ApplyWindowTaskbarIdentity(HWND hwnd) {
  if (!hwnd) {
    return;
  }
  wchar_t exe_path[MAX_PATH];
  const DWORD len = GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return;
  }
  const std::wstring exe(exe_path);

  IPropertyStore* store = nullptr;
  if (FAILED(SHGetPropertyStoreForWindow(hwnd, IID_PPV_ARGS(&store))) ||
      !store) {
    return;
  }
  // Relaunch command, icon and display name must be set together.
  SetStringProperty(store, kPkeyRelaunchCommand, L"\"" + exe + L"\"");
  SetStringProperty(store, kPkeyRelaunchIconResource, exe + L",0");
  SetStringProperty(store, kPkeyRelaunchDisplayName, L"Gaming Hall");
  SetStringProperty(store, kPkeyAppUserModelId, L"GamingHall.MainWindow");
  store->Commit();
  store->Release();
}

// Message id Explorer broadcasts when the taskbar is (re)created.
UINT g_taskbar_created_message = 0;

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  g_taskbar_created_message = RegisterWindowMessage(L"TaskbarCreated");
  ApplyWindowTaskbarIdentity(window);
  ApplyWindowIcons(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  if (g_taskbar_created_message != 0 && message == g_taskbar_created_message) {
    ApplyWindowIcons(hwnd);
  }

  switch (message) {
    case WM_SHOWWINDOW:
      if (wparam) {
        ApplyWindowIcons(hwnd);
        // Once more after the show has finished (the taskbar button is
        // created after this message).
        PostMessage(hwnd, kReapplyIconsMessage, 0, 0);
      }
      break;

    case kReapplyIconsMessage:
      ApplyWindowIcons(hwnd);
      return 0;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
