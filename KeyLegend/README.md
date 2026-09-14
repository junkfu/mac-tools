# KeyLegend

長按 **Option (⌥)** 一小段時間，浮出一份你自己寫的熱鍵筆記——分好類的那種。放開就消失，完全不會擋到你正在用的畫面。

沒有資料庫、沒有表單編輯器：整份筆記就是一個純文字檔，用你自己習慣的編輯器打開來改，存檔立刻生效。

## 功能

- **長按 Option 顯示**：單獨按著 Option 約 0.35 秒觸發；夾雜其他鍵（⌥Tab、⌥點按…）或加上其他修飾鍵一律視為正常操作，不會跳出來擋路。
- **手寫筆記檔**：`## 分類名稱` 開一個分類，`按鍵: 說明` 記一條熱鍵，順序就是顯示順序。壞掉的行（沒有冒號、格式怪怪的）只會被略過，不會讓整份筆記讀取失敗。
- **存檔即生效**：監看筆記檔變動，改完存檔不用重開 App。
- **自訂分類**：VSCode、全域、Claude Code……分類名稱、數量都自己定義。
- **不搶焦點、不擋滑鼠**：面板用 `nonactivatingPanel` + `ignoresMouseEvents`，長按期間前景 App 該怎麼用還是怎麼用。

## 建置與啟動

需要 macOS 13 以上，以及 Xcode Command Line Tools。

```bash
cd KeyLegend
./setup-signing.sh   # 建議先執行一次，固定本機簽章
./build.sh
open /Applications/KeyLegend.app
```

第一次啟動時，macOS 會要求「輔助使用」權限：

> 系統設定 → 隱私權與安全性 → 輔助使用 → 開啟 KeyLegend

為什麼需要：長按判定要在別的 App 是前景時也偵測到 Option 鍵的狀態，這類全域鍵盤事件監控在現行 macOS 上一律要「輔助使用」權限才收得到事件，沒有例外或迂迴路徑。授權後不必重開 App，KeyLegend 會自動偵測到並開始監聽。沒有授權時選單列圖示還在、選單也能用，只是長按不會有反應。

`build.sh` 會直接把 App 組裝到 `/Applications`，repo 裡不會留第二份 `.app`。`setup-signing.sh` 會建立僅供本機使用的 `KeyLegend Local Signing` 自簽身分——macOS 的權限授權綁在程式碼簽章上，固定簽章後重新編譯就不必反覆重新授權。

> 代價：這把私鑰對 `codesign` 免提示，表示任何以你身分執行的程式也能用它重簽二進位、繼承 KeyLegend 的「輔助使用」授權。`build.sh` 有開 hardened runtime 擋掉 dyld 注入，私鑰也設為不可匯出；若你的機器會跑不信任的程式，改成每次 build 手動按「允許」會更安全。

## 使用方式

1. 點選單列的 ⌥ 圖示 →「編輯熱鍵筆記…」，用預設的文字編輯器打開筆記檔。
2. 照這個格式打：

   ```
   ## VSCode
   ⌘P: 快速開檔
   ⌘⇧P: 命令面板

   ## 全域
   ⌘⇧4: 螢幕截圖選取範圍
   ```

3. 存檔。
4. 長按 Option 看看新內容有沒有出現。

筆記檔放在 `~/Library/Application Support/KeyLegend/hotkeys.md`，選單列的「在 Finder 顯示筆記檔」可以直接跳過去；第一次啟動時會自動放一份帶範例的預設內容，照著改就好。

## 專案結構

- `AppDelegate.swift`：選單列、權限流程、把長按判定跟面板接起來。
- `OptionHoldMonitor.swift`：`NSEvent` 全域監控 + 狀態機，判斷「單獨長按 Option」。
- `OverlayWindowController.swift`／`OverlayColumnsView.swift`：不搶焦點的浮動面板與分欄排版。
- `HotkeyModel.swift`／`HotkeyFileParser.swift`：資料模型與純文字格式的解析器。
- `HotkeyStore.swift`：筆記檔路徑、首次啟動的預設內容、目前資料。
- `HotkeyFileWatcher.swift`：監看筆記檔變動、存檔後自動重新讀取。
- `AXPermission.swift`：輔助使用權限的檢查、請求與等待。

## 開發筆記

- **只用 `NSEvent.addGlobalMonitorForEvents`，不架 CGEventTap**。KeyLegend 從頭到尾只是「看」Option 鍵的狀態，從不攔截或吞掉任何按鍵——這點跟 AppJump 的 `TriggerTap` 不一樣，AppJump 需要吞掉綁定的組合鍵才必須上 CGEventTap 那整套執行緒／run loop 機器；KeyLegend 沒有這個需求，用最輕量的全域監控就夠，換來的代價一樣（現行 macOS 上兩者都要輔助使用權限）。
- **長按判定看 `modifierFlags.intersection(.deviceIndependentFlagsMask) == .option`**：必須「剛好只有 Option」才起算，任何其他修飾鍵加入或 Option 放開都會取消計時，這樣才不會在使用者按 ⌥Tab、⌘⌥ 之類的正常快捷鍵時誤跳出來。
- **面板內容每次顯示都重新讀 `HotkeyStore` 現況並重建**，不做簽名比對／快取——純文字內容重繪很便宜，換來的好處是編輯筆記檔存檔後，下一次長按看到的保證是最新內容。
- **筆記檔監看要處理 rename-safe 的存檔行為**：多數編輯器存檔其實是「寫暫存檔、再原地換掉舊檔」，原本的檔案描述符會撲空，收到 `.delete`/`.rename` 就要整組重建監看。

## 已知限制

- 長按判定需要「輔助使用」權限；沒授權時選單列照常可用，只是長按沒有反應。
- 手動改筆記檔的格式一定要照 `## 分類` / `按鍵: 說明` 這兩種行來寫，其他寫法會被當成裝飾略過。
- 同時只會有一份 KeyLegend 在跑；偵測到已有實例時新啟動的那份會自行結束。
