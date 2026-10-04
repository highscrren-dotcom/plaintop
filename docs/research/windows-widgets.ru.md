# Виджеты на рабочем столе Windows: что даёт система, как делают другие, что это значит для порта

Рабочая заметка к решению 17 (`docs/DECISIONS.md`) и `win/README.md`. Собрано 2026-10-05 по первоисточникам (Microsoft Learn, исходники Qt и Rainmeter, трекеры
Qt, Lively, Wallpaper Engine) без машины с Windows. Пометки: **[док.]** — так написано у производителя; **[код]** — прочитано в исходнике; **[сообщ.]** —
сообщают пользователи или сторонние проекты, на столе не проверено.

## Коротко

**Что Windows даёт сама**

- Ничего для виджета *на столе*. Windows Widgets живут только в доске Win+W («the only Widgets host is the Widgets Board»), виджет — JSON Adaptive Card,
  поставщик — упакованное (MSIX) Win32-приложение или PWA [док.]. Наш QML туда не ляжет ни при каком упаковывании.
- Закрепление виджетов на столе обещали в 2023 и не выпустили; в феврале 2025 инженер Microsoft в Feedback Hub: «this isn't something we currently support»
  [сообщ.].
- Desktop Gadgets удалены в Windows 8 как дыра в безопасности [док.]; AppBar — панель, прибитая к краю экрана и отбирающая рабочую область [док.]. Остаётся
  обычное окно Win32 с правильными стилями — путь Rainmeter.
- Первопартийное, что нам действительно нужно: WASAPI loopback, Global SMTC, тосты, трей. Всё есть, у каждого свои оговорки (§4–5).

**Как делают Rainmeter и движки обоев**

- Rainmeter *не* сажает скины под WorkerW. Скин — `WS_POPUP` с `WS_EX_LAYERED | WS_EX_TOOLWINDOW`, рисуется `UpdateLayeredWindow` (попиксельная альфа); «On
  Desktop» = `SetWindowPos(HWND_BOTTOM)` плюс запрет чужих перестановок в `WM_WINDOWPOSCHANGING` [код].
- Click-through у Rainmeter — ровно `WS_EX_TRANSPARENT` на `GWL_EXSTYLE`, перетаскивание — `WM_NCHITTEST → HTCAPTION` [код].
- Win+D Rainmeter ловит сам: окно-страж на `HWND_BOTTOM`; когда хост иконок оказался *над* стражем — стол показан, и скины вставляются под самое нижнее
  topmost-окно (таймер 250 мс + `EVENT_SYSTEM_FOREGROUND`) [код]. Без этого окно на `HWND_BOTTOM` после Win+D не видно — так в их руководстве про позицию Bottom
  [док.].
- WorkerW — путь движков обоев. В 24H2 (сборка 26100) иерархия сломалась: `SHELLDLL_DefView` и `WorkerW` стали детьми `Progman`, `0x052C` с нулями слой не
  порождает; Lively переписал ядро (v2.2.0, сентябрь 2024), Microsoft чинила со своей стороны в KB5050009 (январь 2025) [код Rainmeter, сообщ.].

**Что это меняет для нашего порта**

1. **Главное: WorkerW — не основной режим.** Он гибнет с перезапуском Explorer (дитя уничтожается с родителем [док.]), зависит от сборки Windows и может
   сбросить DPI-режим процесса при `SetParent` между процессами [док.]. Основной режим — как «Bottom/On Desktop» у Rainmeter; наши флаги уже дают его, Qt сам
   держит `HWND_BOTTOM` в `WM_WINDOWPOSCHANGING` [код]. Не хватает одного — слежки за Win+D.
2. `Qt.WindowTransparentForInput` на Windows — `WS_EX_TRANSPARENT | WS_EX_LAYERED` [код], то же, что ClickThrough Rainmeter. Смена флага на лету HWND не
   пересоздаёт [код].
3. **Прозрачные пиксели QQuickWindow клики не пропускают.** Хост рисует через D3D11; для такого окна Qt делает `DwmEnableBlurBehindWindow` +
   `SetLayeredWindowAttributes(LWA_ALPHA)`, а попиксельный hit-test по альфе Windows даёт только окнам, нарисованным `UpdateLayeredWindow` [док., код]. Qt Quick
   так рисует лишь с программным бэкендом (`QT_QUICK_BACKEND=software`) [код]. Это кандидат на вторую стадию без C++ — частичный click-through даром. Проверить
   первым.
4. Тост `CreateToastNotifier("plaintop")` без ярлыка в «Пуске» с `System.AppUserModel.ID` не покажется: «Without a valid shortcut … you cannot raise a toast
   notification from a desktop app» [док.].
5. Автозапуск через `shell:startup` верен, пока ни сервис, ни `qml.exe` не требуют повышения; что требует (LibreHardwareMonitor ради датчиков) — из Startup/Run
   блокируется UAC [док.]. Тосты из повышенного процесса не работают [док.] — сервис держать обычным.
6. Магазин: EXE/MSI принимают с 2021, но с подписью сертификатом из Microsoft Trusted Root Program за наш счёт; бесплатная подпись Microsoft — только у MSIX
   [док.]. Без подписи SmartScreen показывает «Windows protected your PC» на каждом релизе заново [док.].

## 1. Что Windows предоставляет

**Windows Widgets (Win+W).** «Installed widgets are displayed in a grid in the Widgets Board: a flyout plane that overlays the Windows desktop»; хост один
[док.: [Windows Widgets](https://learn.microsoft.com/en-us/windows/apps/design/widgets/)]. Поставщик — «a packaged Win32 desktop app or a Progressive Web App»;
содержимое — Adaptive Cards трёх размеров, интерактив ограничен переходами в приложение [док.: [Widget
providers](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-providers)]. Сторонние виджеты — с Windows App SDK 1.2: «Widgets can only be
created for packaged, Win32 apps», в розничных сборках — через Store-версию приложения [док.: [release notes
1.2](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-1-2)]. Доска могла бы показать пересказ наших данных карточкой
— не виджет.

**Закрепление на столе.** Май 2023 — «тестируется внутри» [сообщ.: [winaero](https://winaero.com/you-will-soon-be-able-to-pin-windows-11-widgets-to-desktop/)];
февраль 2025 — не вышло, ответ инженера Microsoft: «this isn't something we currently support» [сообщ.:
[xda](https://www.xda-developers.com/windows-11-lock-screen-widgets-get-boost-desktop-pinning-remains-ignored/)].

**Desktop Gadgets.** «Gadgets also present a security risk … even benign Gadgets could be exploited»; API оставлен, гаджеты не запускаются [док.: [Desktop
gadgets removed](https://learn.microsoft.com/en-us/windows/win32/w8cookbook/desktop-gadgets-removed)]. Замена — сторонний
[8GadgetPack](https://gadgetpack.net/gadgets/sidebar7.html), возвращающий хост sidebar.exe [сообщ.].

**AppBar.** «anchored to an edge of the screen … The system prevents other applications from using the desktop area used by an appbar» [док.: [Application
Desktop Toolbars](https://learn.microsoft.com/en-us/windows/win32/shell/application-desktop-toolbars)]. Не для виджета.

**Трей и перезапуск Explorer.** При создании панели задач рассылается `TaskbarCreated`: приложение «should assume that any taskbar icons it added have been
removed and add them again» [док.: [The Taskbar](https://learn.microsoft.com/en-us/windows/win32/shell/taskbar)]. Qt это делает сам
(`qwindowssystemtrayicon.cpp` повторяет `NIM_ADD`) [код].

## 2. Как это делают Rainmeter, Wallpaper Engine, Lively

**Rainmeter — позиция** ([AlwaysOnTop](https://docs.rainmeter.net/manual/settings/skin-sections/)): `2` Stay topmost, `1` Topmost, `0` Normal («brought to the
foreground … on click»), `-1` Bottom — «will **not** stay visible when showing the desktop {Win-D} and stay behind other normal application windows», `-2` On
Desktop — «will stay visible when showing the desktop {Win-D} and stay behind other normal application windows» [док.]. `NormalStayDesktop=1` «keeps the skins
in the correct "Z order" when the Windows "Show Desktop" button is clicked» [док.: [Rainmeter
section](https://docs.rainmeter.net/manual/settings/rainmeter-section/)].

**Rainmeter — устройство** ([Skin.cpp](https://github.com/rainmeter/rainmeter/blob/master/Library/Skin.cpp),
[System.cpp](https://github.com/rainmeter/rainmeter/blob/master/Library/System.cpp)) [код]:
- Окно: `CreateWindowEx(WS_EX_LAYERED | WS_EX_TOOLWINDOW, …, WS_POPUP, …)`; кадр — `UpdateLayeredWindow(…, {AC_SRC_OVER, 0, alpha, AC_SRC_ALPHA}, ULW_ALPHA)`.
  `SetParent` к WorkerW — нет.
- `ChangeZPos`: `ONTOPMOST/ONTOP → HWND_TOPMOST`; `ONBOTTOM`, `ONDESKTOP → HWND_BOTTOM` (или после окна-помощника); флаги
  `SWP_NOMOVE|SWP_NOSIZE|SWP_NOOWNERZORDER|SWP_NOACTIVATE|SWP_NOSENDCHANGING`. `OnWindowPosChanging` для `ONDESKTOP/ONBOTTOM` ставит `SWP_NOZORDER` («This keeps
  the window on bottom»); свои вызовы идут с `SWP_NOSENDCHANGING`.
- Show desktop: окна `RainmeterSystem` (`WS_EX_TOOLWINDOW`) стоят на `HWND_BOTTOM`; `CheckDesktopState` ищет `FindWindowEx(nullptr, iconsHost,
  "RainmeterSystem", "System")` — страж *ниже* хоста иконок означает «стол показан». Тогда помощник вставляется после самого нижнего `WS_EX_TOPMOST`-окна над
  хостом иконок, скины — за ним. Проверка: `INTERVAL_SHOWDESKTOP = 250` мс и `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)`.
- Хост иконок: до 24H2 — видимый `WorkerW` оболочки с `SHELLDLL_DefView` внутри; с 24H2 — сам `Progman` (`GetShellWindow()`). Признак: `GetProcAddress(user32,
  "GetCurrentMonitorTopologyId")` — «present only on Windows 11 build 10.0.26100.2454». Комментарий даёт обе иерархии: до — `WorkerW{SHELLDLL_DefView}`,
  `WorkerW`, `Progman` соседи; после — `Progman{SHELLDLL_DefView, WorkerW}`.
- ClickThrough: `AddWindowExStyle(WS_EX_TRANSPARENT)` / `RemoveWindowExStyle` на лету. Перетаскивание: `OnNcHitTest → HTCAPTION` внутри `DragMargins`, иначе
  `HTCLIENT`. Смена дисплеев: `WM_DISPLAYCHANGE`, `SPI_SETWORKAREA` → пересчёт позиций.

**WorkerW-приём.** Классика — «Draw Behind Desktop Icons in Windows 8+» ([CodeProject
856020](https://www.codeproject.com/Articles/856020/Draw-Behind-Desktop-Icons-in-Windows-plus); при сборе заметки сайт отдавал 503):
`SendMessageTimeout(Progman, 0x052C, 0, 0, …)` порождает `WorkerW` за иконками, его находят как соседа окна с `SHELLDLL_DefView` и делают `SetParent` [сообщ.].
В 24H2 ([kirie PR #11](https://github.com/UnhingedSoftware/kirie/pull/11), со ссылкой на Lively, Seelen и
[FeatherWall](https://github.com/RitvikDayal/featherwall)) [сообщ.]: «0x052C with zeros no longer makes Progman spawn the WorkerW layer»; шлют `0x052C` с
`wParam=0xD, lParam=0x1`, и только если слоя нет; на «поднятом столе» у `Progman` стоит `WS_EX_NOREDIRECTIONBITMAP`, и окно обоев должно быть *layered-ребёнком
Progman с альфой 255 между `SHELLDLL_DefView` и WorkerW Explorer'а*. Lively v2.2.0.0 (2024-09-03): «Core components were fully rewritten to adapt to platform
changes introduced in Windows 11 24H2 … wallpapers could enter a restart loop» [сообщ.: [releases](https://github.com/rocksdanister/lively/releases)], типичный
лог — «WorkerW destroyed → Restarting wallpaper service» [сообщ.: [issue 2407](https://github.com/rocksdanister/lively/issues/2407)]. Wallpaper Engine на 24H2
исчезал при скрытых иконках, фикс Microsoft — KB5050009/KB5050094 [сообщ.: [Steam](https://steamcommunity.com/app/431960/discussions/1/4846526727955382962/),
[Lively #2464](https://github.com/rocksdanister/lively/discussions/2464)]. #11](https://github.com/UnhingedSoftware/kirie/pull/11), со ссылкой на то, что шлют
Lively, Seelen и FeatherWall) [сообщ.]: «0x052C with zeros no longer makes Progman spawn the WorkerW layer»; шлют `0x052C` с `wParam=0xD, lParam=0x1`, и только
если слоя нет; на «поднятом столе» у `Progman` стоит `WS_EX_NOREDIRECTIONBITMAP`, и окно обоев должно быть *layered-ребёнком Progman с альфой 255 между
`SHELLDLL_DefView` и WorkerW Explorer'а*. [FeatherWall](https://github.com/RitvikDayal/featherwall) различает «classic WorkerW» и «24H2+ raised desktop» и
пишет, что восстановление после перезапуска explorer.exe не проверено [сообщ.]. Lively v2.2.0.0 (2024-09-03): «Core components were fully rewritten to adapt to
platform changes introduced in Windows 11 24H2 … wallpapers could enter a restart loop» [сообщ.: [releases](https://github.com/rocksdanister/lively/releases)];
типичный лог — «WorkerW destroyed → Restarting wallpaper service» [сообщ.: [issue 2407](https://github.com/rocksdanister/lively/issues/2407)]. Wallpaper Engine
на 24H2 исчезал при скрытых иконках; фикс Microsoft — KB5050009/KB5050094, обход — включить значки стола [сообщ.:
[Steam](https://steamcommunity.com/app/431960/discussions/1/4846526727955382962/), [Lively #2464](https://github.com/rocksdanister/lively/discussions/2464)].

Для `win/service/ui.py` это значит: ветка «WorkerW внутри Progman» на 24H2 находит *слой Explorer'а под иконками*, и не факт, что окно, посаженное в него,
окажется над обоями и под иконками (kirie: нужен свой layered-ребёнок Progman в правильном месте z-порядка). `SetParent` сам не меняет `WS_POPUP → WS_CHILD`:
«you should clear the WS_POPUP style and set the WS_CHILD style before calling SetParent» [док.:
[SetParent](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setparent)]. Перезапуск Explorer убивает WorkerW, а «DestroyWindow
automatically destroys the associated child or owned windows» [док.:
[DestroyWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-destroywindow)] — хост надо перезапускать, как Lively. XWidget («mouse
through») и 8GadgetPack нового против Rainmeter не показывают [сообщ.].

## 3. Факты Win32 и как их использует Qt 6

**Стили** ([Extended Window Styles](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles), [Window Features → Layered
Windows](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features)) [док.]:
- `WS_EX_TRANSPARENT` (0x20) сам по себе про *рисование*: «should not be painted until siblings beneath the window (that were created by the same thread) have
  been painted». Про мышь — только у layered-окна: «if the layered window has the WS_EX_TRANSPARENT extended window style, the shape of the layered window will
  be ignored and the mouse events will be passed to other windows underneath». Частичного пропуска он не даёт.
- `WS_EX_LAYERED` + попиксельная альфа: «Hit testing of a layered window is based on the shape and transparency of the window … areas of the window that are
  color-keyed or whose alpha value is zero will let the mouse messages through». Форму даёт `UpdateLayeredWindow` (`ULW_ALPHA`, `AC_SRC_ALPHA`, 32-битная
  ARGB-поверхность); `SetLayeredWindowAttributes` — только общая непрозрачность или цветовой ключ, и после него `UpdateLayeredWindow` «will fail until the
  layering style bit is cleared and set again» [док.:
  [UpdateLayeredWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-updatelayeredwindow)].
- `WS_EX_TOOLWINDOW` — без кнопки на панели задач и в Alt+Tab; `WS_EX_NOACTIVATE` — не становится foreground по клику. `HWND_BOTTOM` — «Places the window at the
  bottom of the Z order … loses its topmost status»; без `SWP_NOACTIVATE` окно активируется и поднимается; владеемые окна всегда выше владельца [док.:
  [SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)].
- `WM_NCHITTEST → HTTRANSPARENT`: «In a window currently covered by another window in the same thread» — работает только между окнами одного потока, клик на
  стол так не отдать [док.: [WM_NCHITTEST](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-nchittest)]. `SetWindowRgn` «determines the area within
  the window where the system permits drawing» — режет и клики, и картинку, со сглаживанием текста по краю маски [док.:
  [SetWindowRgn](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowrgn)].

**Qt 6, `qwindowswindow.cpp`** ([dev](https://github.com/qt/qtbase/blob/dev/src/plugins/platforms/windows/qwindowswindow.cpp); в ветке 6.8 те же места) [код]:
- `Qt::Tool` → `WS_EX_TOOLWINDOW`; `FramelessWindowHint` → `WS_POPUP`; `WindowDoesNotAcceptFocus` → `WS_EX_NOACTIVATE` (мы не ставим — стоит подумать);
  `WindowTransparentForInput` → `WS_EX_TRANSPARENT`, а `setWindowLayered()` добавляет `WS_EX_LAYERED` при этом флаге, при альфе у безрамочного окна или opacity
  < 1.
- `WindowStaysOnBottomHint` → `SetWindowPos(HWND_BOTTOM, …, SWP_NOACTIVATE)` при создании; в `WM_WINDOWPOSCHANGING` при любом изменении порядка `hwndInsertAfter
  = HWND_BOTTOM`; `raise_sys()` ничего не делает; `requestActivateWindow` пишет «Windows with Qt::WindowStaysOnBottomHint can't be brought to the foreground».
  Флаг на Windows честный и держится так же, как у Rainmeter, но Win+D не знает. История: «Qt::WindowStaysOnBottomHint does not work» (Windows 7, Qt 5.5–5.9)
  исправлено в 5.11.2 [док.: [QTBUG-53717](https://bugreports.qt.io/browse/QTBUG-53717)]. Документация флага оговаривает только X11 [док.:
  [Qt::WindowType](https://doc.qt.io/qt-6/qt.html#WindowType-enum)].
- Прозрачность: ускоренное окно с альфой (QQuickWindow на RHI, по умолчанию D3D11) — `applyBlurBehindWindow()` (`DwmEnableBlurBehindWindow`: с Windows 8 без
  размытия, но «The alpha values in the window are honored» [док.:
  [DwmEnableBlurBehindWindow](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmenableblurbehindwindow)]) +
  `SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)`; растровое — `UpdateLayeredWindow(ULW_ALPHA)`, кадры через `UpdateLayeredWindowIndirect` с
  `AC_SRC_ALPHA` [код: [qwindowsbackingstore.cpp](https://github.com/qt/qtbase/blob/dev/src/plugins/platforms/windows/qwindowsbackingstore.cpp)]. По
  документации Microsoft выше: у растрового окна Qt клики проходят через альфу 0, у D3D-окна вся площадь «твёрдая». Виджеты это подтверждают: `QWidget` с
  `WA_TranslucentBackground` на Windows пропускает клики через прозрачное [сообщ.: [QTBUG-65058](https://bugreports.qt.io/browse/QTBUG-65058)], но не колесо
  [сообщ.: [QTBUG-53418](https://bugreports.qt.io/browse/QTBUG-53418)]; для Qt Quick запрос «input events should pass through out of the shape» висит без ответа
  [сообщ.: [QTBUG-86819](https://bugreports.qt.io/browse/QTBUG-86819)]. Фраза документации `WA_TranslucentBackground` про «pixels that are not painted at all
  will also not receive any mouse input» — про виджеты, не про QQuickWindow [док.].
- Программный бэкенд: `QSGSoftwareRenderLoop::windowSurfaceType()` = `RasterSurface` [код]; включается `QT_QUICK_BACKEND=software` [док.: [Scene Graph
  Adaptations](https://doc.qt.io/qt-6/qtquick-visualcanvas-adaptations.html)]; не умеет `ShaderEffect` и частицы, текст «does not respond as well to
  transformations» [док.: [Software Adaptation](https://doc.qt.io/qt-6/qtquick-visualcanvas-adaptations-software.html)]. В нашем QML ни того, ни другого нет
  (grep). Не путать с `qml --software` — это программный *OpenGL*, поверхность остаётся ускоренной [код: `tools/qml/main.cpp`].
- `setWindowFlags()` → `applyWindowFlags` + `SetWindowPos(SWP_FRAMECHANGED)`: HWND не пересоздаётся [код]. Переключение Mouse на лету безопасно.
- Оговорки: `WindowTransparentForInput` на *дочерних* окнах Windows не работает [сообщ.: [QTBUG-50505](https://bugreports.qt.io/browse/QTBUG-50505)] — важно,
  если окно станет ребёнком WorkerW; прозрачные QQuickWindow на некоторых NVIDIA были чёрными (Qt 5.12–5.15, «Out of scope») [сообщ.:
  [QTBUG-85524](https://bugreports.qt.io/browse/QTBUG-85524)] — помнить про `--rhi d3d11|opengl`. Диагностика без Spy++: `QT_LOGGING_RULES=qt.qpa.window=true`
  печатает `Style`/`ExStyle` при каждом изменении флагов [код].

## 4. Практика

**Автозапуск.** `Run` — командная строка до 260 символов, порядок не определён, «the system may choose to delay the execution of programs in the Run key and in
the Startup group» [док.: [Run and RunOnce](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)]. Всё, что требует
повышения, «blocked in the logon path» из обеих Startup-папок и обоих `Run`; совет Microsoft — AsInvoker, повышенное — планировщиком [док.: [UAC
blog](https://learn.microsoft.com/en-us/archive/blogs/uac/elevations-are-now-blocked-in-the-users-logon-path)]. `pythonw plaintop.py` или замороженный exe без
`requireAdministrator` — ярлыка достаточно; LibreHardwareMonitor («Some sensors require administrator privileges» [док.:
[README](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)]) запускается отдельно, задачей планировщика с «highest privileges» [сообщ.].

**DPI.** «Qt 6 is Per-Monitor DPI Aware V2 by default», `qt.conf` → `WindowsArguments = dpiawareness=0,1,2` [док.: [High
DPI](https://doc.qt.io/qt-6/highdpi.html)] — `qml.exe` манифеста не требует. Со стороны Windows: «unaware» растягивается битмапом, PMv2 получает
`WM_DPICHANGED`; `SetParent` между процессами с разной осведомлённостью — «Forced reset (of child window's process)» [док.: [High DPI Desktop Application
Development](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows)]. Explorer и Qt оба PMv2 — конфликт не
ожидается, проверить на смешанных мониторах.

**Несколько мониторов.** Индекс в `Qt.application.screens` меняется от порядка подключения; Rainmeter хранит `@N` и пересчитывает по `WM_DISPLAYCHANGE` [код],
`QScreen::name` на Windows — `\\.\DISPLAY1` из `szDevice` [код: `qwindowsscreen.cpp`]. Хранить имя плюс запасной индекс.

**Тосты.** Старое правило: ярлык в `%APPDATA%\Microsoft\Windows\Start Menu\Programs` со свойством `System.AppUserModel.ID`, иначе «you cannot raise a toast
notification from a desktop app»; `CreateToastNotifier(appId)` с тем же AUMID [док.: [How to enable desktop toast notifications through an
AppUserModelID](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/legacy/hh802762(v=vs.85))]. Windows App SDK `AppNotificationManager` —
другой рантайм, и общее ограничение «Apps running with administrator privileges (elevated) cannot send or receive app notifications» [док.: [App
notifications](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/)]. Обход без ярлыка — чужой зарегистрированный AUMID
(PowerShell'ный) или ключ `HKCU\Software\Classes\AppUserModelId\<id>` с `DisplayName` [сообщ.].

**SmartScreen.** Два сигнала — репутация издателя и хеша; «When a file is not signed, SmartScreen reputation must build for each new version of your files,
starting with zero reputation»; без подписи и самоподписанный — «Windows protected your PC», OV/EV — предупреждение с именем издателя, EV ничего не ускоряет;
Smart App Control может блокировать неподписанное вовсе [док.: [SmartScreen
reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)]. Пока запускается `pythonw.exe` (подписан PSF) с нашими
`.py`, SmartScreen смотрит на zip при скачивании; замороженный exe без подписи упрётся в предупреждение.

**Магазин.** «Microsoft Store has allowed unpackaged applications since June 2021» — ссылка на офлайновый `.msi/.exe`, но «Publishers must sign with a
certificate issued by a CA that is part of the Microsoft Trusted Root Program», хостинг и автообновления свои; у MSIX подпись и хостинг от Microsoft [док.:
[Distribute your Win32 app through Microsoft
Store](https://learn.microsoft.com/en-us/windows/apps/distribute-through-store/how-to-distribute-your-win32-app-through-microsoft-store)]. Store без сертификата
= MSIX; виджеты доски — только поверх MSIX.

## 5. Звук и медиа

**WASAPI loopback.** `GetDefaultAudioEndpoint(eRender)` + `Initialize(…, AUDCLNT_STREAMFLAGS_LOOPBACK, …)`; «A client can enable loopback mode only for a
shared-mode stream … Exclusive-mode streams cannot operate in loopback mode»; событийный режим для loopback — с Windows 10 1703; захватывается микс движка со
всех сессий [док.: [Loopback Recording](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording)]. Ловушки:
- *Тишина.* «If no audio is playing whatsoever, then the DataAvailable event won't fire» — обход: играть тишину самим или дописывать нули по таймеру [сообщ.:
  [NAudio WasapiLoopbackCapture](https://github.com/naudio/NAudio/blob/master/Docs/WasapiLoopbackCapture.md)]. Кольцо визуализатора должно гаснуть по таймауту
  кадров, а не ждать данных.
- *Формат.* Loopback отдаёт mix format устройства (float32, 44.1/48 кГц) и частоту не пересчитывает: «Converting sample rate from 44100 to 48000 is a
  non-trivial operation so loopback capture won't perform it» (инженер Microsoft в комментариях); «loopback capture is the aggregate of all shared-mode streams
  … This also won't work for applications that play in exclusive mode» [сообщ.: [van
  Eerde](https://learn.microsoft.com/en-us/archive/blogs/matthew_van_eerde/sample-wasapi-loopback-capture-record-what-you-hear)].
- *Смена устройства.* Приложение на WASAPI «needs to provide the stream routing implementation» — слушать `IMMNotificationClient`, переоткрывать поток [док.:
  [Stream Routing](https://learn.microsoft.com/en-us/windows/win32/coreaudio/stream-routing)]. Иначе наушники воткнули — визуализатор замер.
- *Exclusive mode.* «Exclusive-mode streams seize the audio endpoint—all system sounds, notifications, and audio from other applications are silenced» [док.:
  [Exclusive-Mode Streams](https://learn.microsoft.com/en-us/windows/win32/coreaudio/exclusive-mode-streams)]; loopback такое не слышит.
- *Захват одного процесса* (`AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS`, include/exclude дерева) — с build 20348 [док.:
  [AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS](https://learn.microsoft.com/en-us/windows/win32/api/audioclientactivationparams/ns-audioclientactivationparams-audioclient_process_loopback_params)];
  им можно исключить собственный звук напоминаний.

**Global System Media Transport Controls.** Windows 10 1809+, «playback sessions throughout the system that have integrated with SystemMediaTransportControls»;
`GetCurrentSession()` — «the session the system believes the user would most likely want to control» [док.:
[SessionManager](https://learn.microsoft.com/en-us/uwp/api/windows.media.control.globalsystemmediatransportcontrolssessionmanager)]. Публикуют: всё на
`MediaPlayer` — автоматически [док.: [Integrate with
SMTC](https://learn.microsoft.com/en-us/windows/apps/develop/media-playback/integrate-with-systemmediatransportcontrols)]; Spotify и Chrome — сами [сообщ.:
[Q&A](https://learn.microsoft.com/en-us/answers/questions/317008/properly-integrate-globalsystemmediatransportcontr)]. `TimelineProperties.Position` — «The
playback position, current as of LastUpdatedTime» [док.:
[TimelineProperties](https://learn.microsoft.com/en-us/uwp/api/windows.media.control.globalsystemmediatransportcontrolssessiontimelineproperties)] — снимок,
который надо экстраполировать `now − LastUpdatedTime` при `Playing`; как часто его обновлять — дело приложения, есть и не сообщающие позицию вовсе [сообщ.:
[Cider #2043](https://github.com/ciderapp/Cider-2/issues/2043)]. `player_win.py` должен экстраполировать сам.

**LibreHardwareMonitor.** Веб-сервер (Options → Remote Web Server → Run, порт 8085): `GET /data.json` — дерево; `GET /Sensor?action=Get&id=/some/node/path/0` →
`{"result":"ok","value":42.0,"format":"{0:F2} RPM"}`; есть `Set` и Basic-аутентификация [код:
[HttpServer.cs](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/blob/master/LibreHardwareMonitor.Windows.Forms/Utilities/HttpServer.cs)].
Именованного канала у LHM нет; WMI-провайдер (`root\LibreHardwareMonitor`, классы `Hardware`/`Sensor`, по образцу OpenHardwareMonitor) упоминают пользователи,
файла в исходниках я не нашёл [сообщ.] — проверить на столе. HTTP JSON — верный выбор; датчики требуют LHM от администратора [док.].

**psutil на Windows.** `sensors_temperatures()`, `sensors_fans()` — «availability: Linux, FreeBSD»; `cpu_freq` на Windows значение возвращает всегда [док.:
[docs/api.rst](https://github.com/giampaolo/psutil/blob/master/docs/api.rst)]. Температуры, вентиляторы, GPU — только LHM.

## Что проверить на столе в первую очередь

От самого дешёвого и решающего к остальному. PowerShell; `$u` из п. 1 нужен дальше.

1. **Сборка Windows и иерархия стола.** `[Environment]::OSVersion.Version.Build` и `(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR`
   — 26100 = 24H2, порог Rainmeter 26100.2454. Затем:
   ```powershell
   $sig = '[DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
   [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
   [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
   [DllImport("kernel32.dll")] public static extern IntPtr GetProcAddress(IntPtr m, string n);
   [DllImport("kernel32.dll")] public static extern IntPtr GetModuleHandle(string n);'
   $u = Add-Type -MemberDefinition $sig -Name U -Namespace W -PassThru
   $p = $u::FindWindow('Progman', $null)
   'DefView in Progman: {0}  WorkerW in Progman: {1}  ExStyle: 0x{2:X}' -f $u::FindWindowEx($p,0,'SHELLDLL_DefView',$null), $u::FindWindowEx($p,0,'WorkerW',$null), $u::GetWindowLong($p,-20)
   'GetCurrentMonitorTopologyId: ' + $u::GetProcAddress($u::GetModuleHandle('user32'), 'GetCurrentMonitorTopologyId')
   ```
   Ненулевой DefView внутри Progman и бит `0x200000` (`WS_EX_NOREDIRECTIONBITMAP`) = «поднятый стол» 24H2+; ветка `ui.py` «WorkerW inside Progman» тогда находит слой Explorer'а, а не место для нас.
2. **Стили нашего окна.** `$env:QT_LOGGING_RULES='qt.qpa.window=true'; python win\plaintop.py` — stderr `qml.exe` при создании и при каждом переключении Mouse
   должен показать `WS_EX_TOOLWINDOW WS_EX_LAYERED` и (Mouse=on) `WS_EX_TRANSPARENT`, без пересоздания окна.
3. **Keep-below.** Блокнот поверх виджета — виджет под ним; клик по виджету (Mouse=off) — не всплывает; в Alt+Tab его нет. По коду Qt так и должно быть.
4. **Win+D.** Ожидание: виджеты исчезли (стол поднят над `HWND_BOTTOM`, как у Rainmeter «Bottom»), после второго Win+D вернулись. Если так — нужен аналог
   Rainmeter в сервисе: страж на `HWND_BOTTOM`, таймер/`EVENT_SYSTEM_FOREGROUND`, `SetWindowPos` виджетов под нижнее topmost-окно. Если видны и после Win+D —
   записать, это расходится с Rainmeter.
5. **Клики сквозь (Mouse=on).** Левый клик по тексту выделяет иконку под ним, правый открывает меню стола; проверить колесо и двойной клик по иконке под
   строкой.
6. **Прозрачные пиксели без флага (Mouse=off).** Клик по пустому месту окна между строками — ожидание: *не* проходит (D3D). Затем
   `$env:QT_QUICK_BACKEND='software'` и снова — ожидание: проходит через альфу 0, по буквам ловится. Сравнить вид текста и CPU визуализатора на 30 кадрах — это
   решает вторую стадию без C++. Не путать с `qml --software`.
7. **За иконками (WorkerW).** Включить в меню: окно между обоями и иконками? иконки кликаются? виджет кликается (QTBUG-50505)? Затем `taskkill /f /im
   explorer.exe; Start-Process explorer` — ожидание: виджет пропал, порт должен заметить и перезапустить хост. Отдельно сменить обои.
8. **DPI и мониторы.** На дисплее 125–150 % текст резкий (PMv2); перенести на монитор с другим масштабом; сравнить с
   `$env:QT_QPA_PLATFORM='windows:dpiawareness=0'` (должно замылиться); отключить монитор — какой индекс экрана сохранился.
9. **Трей.** После п. 7 иконка возвращается сама (`TaskbarCreated`); меню из трея открывается поверх виджетов.
10. **Тост.** Скрипт из `notify_win.py` вручную: ожидание — тишина без ошибки. Контроль канала: вместо `"plaintop"` подставить
    `'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'` — тост появится. Потом ярлык с AUMID или ключ `AppUserModelId` и снова
    `"plaintop"`.
11. **Звук.** В тишине кольцо замирает на последнем кадре (пакетов нет); смена устройства вывода — поток умер, нужен переоткрыв; плеер в WASAPI exclusive —
    loopback молчит.
12. **Плеер.** Через `winsdk` печатать `Position`, `LastUpdatedTime`, `PlaybackStatus` раз в секунду для Spotify и вкладки браузера; сходится ли экстраполяция с
    треком.
13. **Датчики.** `Invoke-RestMethod http://localhost:8085/data.json` при LHM от администратора и без него — какие ветки пустеют; `Get-CimInstance -Namespace
    root\LibreHardwareMonitor -ClassName Sensor -ErrorAction SilentlyContinue | Select -First 5` — есть ли WMI вообще.
14. **Автозапуск.** Ярлык в `shell:startup` на `pythonw.exe … plaintop.py`: после входа все пять окон на местах; LHM — отдельно, задачей планировщика с «highest
    privileges».
