# AppJump

按住**右 ⌘**再按一個字母，直接跳到那個 App。操作方式類似 rcmd，設定與資料都留在自己的 Mac 上。

右 ⌘ 在 macOS 沒有任何預設用途，拿來當觸發鍵不會跟既有快捷鍵打架——但代價是 Carbon 的 `RegisterEventHotKey` 和 `NSEvent.modifierFlags` 都分不出左右 ⌘，只有 CGEventTap 讀得到事件的 device-dependent 旗標，這也是它需要「輔助使用」權限的唯一原因。不想給權限也還是能用：改綁 `⌃⌥S` 這類傳統組合鍵走的是 Carbon 熱鍵，完全不需要授權。

## 功能

- **左右修飾鍵快捷鍵**：預設「右 ⌘ + 字母」，也可改成左／右 ⌘、⌥ 或 ⌃。沒綁定的鍵一律原樣放行，右 ⌘ 不會變成廢鍵。
- **一般全域快捷鍵**：每個 App 可另外設定 `⌃⌥S`、`⌘⇧N` 這類組合鍵，不需要輔助使用權限。
- **自動指派字母**：新增 App 時自動用名稱裡還沒被佔用的字母當快捷鍵（Safari → S），不滿意再自己改。
- **啟動與切換**：App 沒在跑就開起來，已經在跑就切到最前面；視窗全被縮到 Dock 時會順手還原一個。
- **重複按鍵行為**：目標已在最前面時可隱藏、循環該 App 的視窗，或不動作。可設全域預設，也能逐一覆寫。
- **快捷提示板**：按住觸發鍵約 0.4 秒不放，浮出所有綁定的 App 與按鍵；面板不搶焦點，放開即消失。
- **衝突提示**：一般全域快捷鍵被系統或其他 App 佔走時，設定表格與選單會標上 ⚠︎。
- **登入時啟動**：走 macOS 原生的 `SMAppService`，不需要額外安裝 helper。
- **本機設定檔**：所有綁定存在 `~/Library/Application Support/AppJump/config.json`，可讀、可備份、可進版控。

## 建置與啟動

需要 macOS 13 以上，以及 Xcode Command Line Tools。

```bash
cd AppJump
./setup-signing.sh   # 建議先執行一次，固定本機簽章
./build.sh
open AppJump.app
```

第一次設定「右 ⌘ + 字母」時，macOS 會要求「輔助使用」權限：

> 系統設定 → 隱私權與安全性 → 輔助使用 → 開啟 AppJump

授權後不必重開 AppJump，程式會自動偵測到並開始監聽。

`setup-signing.sh` 會在登入鑰匙圈建立僅供本機使用的 `AppJump Local Signing` 自簽身分。macOS 的權限授權綁在程式碼簽章上，固定簽章後重新編譯就不必反覆重新授權；若用 ad-hoc 簽章，每次重編譯都會被系統當成另一份 App。

## 使用方式

1. 點選單列的 ↔ 圖示 →「設定…」。
2. 按「＋ 新增 App」，從執行中的清單挑，或「選擇應用程式…」自己選 `.app`。
3. 設定「觸發鍵 + 按鍵」、一般全域快捷鍵，或兩者都設。
4. 儲存後立即生效。

例如把 Safari 設成 `右⌘S`，之後在任何 App 按住右側 Command 再按 S，就會切到 Safari；Safari 沒開就自動開啟。設定表格與提示板一律把左右標出來（顯示成 `右⌘S` 而不是 `⌘S`），才不會跟系統原生的 ⌘S 混淆。

選單列的選單會列出所有綁定，可以直接點著切換；另外有「在 Finder 顯示設定檔」方便備份或手改。

## 專案結構

- `AppDelegate.swift`：選單列、權限流程與兩套熱鍵系統的協調中心。
- `TriggerTap.swift`：CGEventTap，辨識左右修飾鍵、攔截並吞掉有綁定的按鍵。
- `ClassicHotKeyManager.swift`：Carbon `RegisterEventHotKey`，註冊一般全域組合鍵。
- `AppSwitcher.swift`：啟動、切換、隱藏，以及走 Accessibility API 的視窗循環。
- `PreferencesWindowController.swift`：設定視窗、App 選擇、快捷鍵錄製與衝突檢查。
- `ShortcutOverlayController.swift`：按住觸發鍵時浮出的快捷提示板。
- `HotKeyRecorderButton.swift`：錄製單鍵／組合鍵的按鈕。
- `BindingStore.swift`／`Models.swift`：JSON 設定檔與資料模型。
- `AppCatalog.swift`／`KeyCodeMap.swift`：App 名稱圖示查詢（含快取）、keyCode 與鍵名互轉。
- `AXPermission.swift`／`LaunchAtLogin.swift`：輔助使用權限、登入項目。

## 開發筆記

- **事件 tap 跑在自己的執行緒**。callback 只要卡超過系統容忍時間，整個 tap 會被停用、鍵盤開始偶爾漏鍵。tap 的 callback 只做查表與吞不吞的判斷，實際動作全部 async 丟回主執行緒；真的被停用時也會自動重新啟用。
- **「右 ⌘ 是否按著」以事件自己帶的旗標為準**，不完全依賴累積狀態——鎖定畫面、切換使用者都可能吃掉某次 keyUp，純靠狀態會卡在「以為還按著」，之後每個字母都被吞掉。
- **keyDown 被吞，keyUp 一定要跟著吞**，否則前景 App 會收到沒有配對的 keyUp。
- `overlayDelay`（提示板延遲，預設 0.4 秒）目前只能改 `config.json`，設定視窗沒有開這個選項。

## 已知限制

- 左右修飾鍵快捷功能需要「輔助使用」權限；沒授權時程式不會攔截鍵盤，一般全域快捷鍵照常可用。
- 「循環視窗」與還原最小化視窗同樣需要輔助使用權限。
- 部分系統快捷鍵或其他工具已註冊的組合鍵無法重複使用，AppJump 會標示衝突。
- 手動修改 `config.json` 後需要重新啟動 AppJump 才會生效。
- 同時只會有一份 AppJump 在跑；偵測到已有實例時新啟動的那份會自行結束（兩份會各自架一組 tap，同一次按鍵被處理兩次）。
