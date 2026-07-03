# MacCut

輕量截圖標註工具，取代卡頓的 LINE 內建截圖。原生 Swift / AppKit，常駐選單列，不佔 Dock。

## 設計重點

- **框選交給系統**：按下快捷鍵後，實際的螢幕框選 UI 直接呼叫 macOS 內建的
  `/usr/sbin/screencapture -i`，GPU 原生合成、零額外負擔 —— 這是 LINE 截圖工具卡頓的環節，
  這裡完全繞開，原生系統處理。
- **標註畫布輕量**：標註視窗用 layer-backed `NSView`，畫的時候只疊「已完成的合成圖」+「正在畫的這一筆」，
  放開滑鼠才烘焙進合成圖，不會有大量重繪造成的延遲。

## 功能

- **全域快捷鍵**：預設 `⌘⇧X`，可在選單列「偏好設定…」自訂（也可從選單列圖示手動觸發截圖）。
- **標註工具**：畫筆（自由手繪）、框框（矩形外框）、馬賽克（區塊像素化，適合遮個資／臉），5 色可選（紅／黃／綠／藍／黑，馬賽克不受顏色影響）。
- **`⌘Z`** 復原上一筆、**`⏎`** 複製到剪貼簿並關閉、**`Esc`** 放棄這張截圖。
- 結果只會進剪貼簿，貼到 LINE、Slack、任何地方都行，不會另外存檔。

## 編譯與安裝

需要 Xcode Command Line Tools（已內含 Swift 與 macOS SDK）。

```bash
cd mac-cut
./setup-signing.sh   # 一次性：建立本機簽章身分，見下方「固定簽章身分」說明
./build.sh
open MacCut.app
```

`build.sh` 會：release 編譯 → 組裝 `MacCut.app` → 簽章（有跑過 `setup-signing.sh` 就用固定身分，沒有就退回 ad-hoc）。

啟動後沒有視窗也沒有 Dock 圖示，選單列會出現 ✂️ 圖示。

### 打包成 DMG、安裝到 Applications

```bash
./make-dmg.sh
```

會產生 `MacCut.dmg`（裡面是 `MacCut.app` + 一個指向 `/Applications` 的捷徑，跟一般 Mac App 安裝方式一樣）。
沒有先跑過 `build.sh` 的話，`make-dmg.sh` 會自動先幫你編譯。

打開 `MacCut.dmg` 後把 `MacCut.app` 拖進 `Applications` 捷徑就裝好了，之後從「應用程式」資料夾或 Spotlight
啟動即可，不用再從專案資料夾跑。要在終端機一次做完「掛載 DMG → 複製到 Applications → 打開」也可以：

```bash
hdiutil attach MacCut.dmg -nobrowse -quiet
rm -rf /Applications/MacCut.app
ditto /Volumes/MacCut/MacCut.app /Applications/MacCut.app
hdiutil detach /Volumes/MacCut -quiet
open /Applications/MacCut.app
```

> 這個 DMG 是自簽章、沒有經過 Apple 公證，只適合你自己本機安裝，或給知道怎麼繞過 Gatekeeper 的人。
> 如果之後想給不懂技術的朋友直接下載安裝，需要 Apple Developer ID 簽章 + 公證，是完全不同的流程。

### 第一次使用：授權「螢幕錄製」權限

因為是呼叫系統的 `screencapture` 來框選，第一次按快捷鍵時 macOS 會跳出「螢幕錄製」授權請求，
到「系統設定 → 隱私權與安全性 → 螢幕錄製」把 `MacCut` 打勾即可（可能需要重新啟動 App 一次）。

> 注意：預設用 ad-hoc 簽章（每次 `./build.sh` 重新編譯簽章雜湊都會變），
> 改了程式碼重新編譯後，系統常會要求重新授權一次。
> 如果覺得煩，做下面「固定簽章身分」一次就好，之後重編都不會再重問。

### 固定簽章身分（解決重編後要重新授權的問題，選擇性但建議）

**每個 clone 這份 repo 的人，都要在自己電腦上做這一步一次**（純本機操作，不會跟別人共用同一把身分，
也不會有任何金鑰被 commit 進 repo）：

```bash
./setup-signing.sh
```

這支腳本會在你自己的登入鑰匙圈建立一把叫 `MacCut Local Signing` 的自簽程式碼簽署憑證
（本機產生 RSA 金鑰、自簽、匯入鑰匙圈，只授權 `codesign` 這支工具可以用它，不連網、不需要任何帳號）。
建好之後 `./build.sh` 會自動偵測到並改用它簽章；沒跑這支腳本的話會自動退回 ad-hoc（一樣能跑，只是重編後可能要重新授權螢幕錄製）。

跑完之後，如果你之前已經在「系統設定 → 隱私權與安全性 → 螢幕錄製」授權過 `MacCut`，
把舊的那筆移除（選取後按「−」）、`./build.sh` 重新編譯、重新打開 App 再授權一次——
這是最後一次要重新授權，之後身分固定了就不會再變。

> 想自己手動用「鑰匙圈存取」的 GUI 做也可以（Keychain Access → 憑證輔助程式 → 建立憑證…，
> 名稱填 `MacCut Local Signing`、身分類型選「自簽根憑證」、憑證類型選「程式碼簽署」），效果跟跑腳本一樣。

### 開機自動啟動（選擇性）

先照上面「打包成 DMG、安裝到 Applications」裝到 `/Applications/MacCut.app`，
再到系統設定 →「一般」→「登入項目」→ 加入它。

## 使用方式

1. 按快捷鍵（預設 `⌘⇧X`），游標變成十字，拖曳框選想要的區域（放開就完成框選，按 `Esc` 可取消框選）。
2. 跳出標註視窗：選畫筆、框框或馬賽克工具，直接在圖上畫／拖曳。
3. 按 `⏎`（或按工具列綠色打勾）→ 複製到剪貼簿並關閉視窗，直接去 LINE 貼上。
4. 不想要這張就按 `Esc`（或紅色叉叉）捨棄。

### 自訂快捷鍵

選單列圖示 →「偏好設定…」→ 點快捷鍵按鈕 → 按下想要的組合鍵（至少要含 `⌘`／`⌥`／`⌃` 其中一個，避免誤綁純字母鍵）。
按 `Esc` 可取消錄製；「還原預設值」改回 `⌘⇧X`。設定存在 `UserDefaults`，重開機、重編都不會不見。

## 開發

```
build.sh            release 編譯 + 組 .app + 簽章
setup-signing.sh     一次性：建立本機固定簽章身分
make-dmg.sh          把 .app 包成可安裝的 .dmg
Sources/MacCut/
  main.swift                      進入點
  AppDelegate.swift                選單列圖示、快捷鍵註冊、串起截圖→標註流程
  HotKeyManager.swift              Carbon 全域快捷鍵（RegisterEventHotKey／UnregisterEventHotKey）
  HotKeyStore.swift                快捷鍵持久化（UserDefaults）、Carbon 修飾鍵 <-> 顯示符號轉換
  HotKeyRecorderControl.swift      「偏好設定」裡的錄製按鈕：local monitor 抓下一個按鍵組合
  PreferencesWindowController.swift 偏好設定視窗
  CaptureController.swift          呼叫 screencapture -i -s -c，用剪貼簿 changeCount 判斷是否取消
  AnnotationView.swift             標註畫布：合成圖 + 目前這一筆的即時預覽、undo 快照堆疊、馬賽克像素化
  ToolbarView.swift                浮動工具列：工具／顏色／undo／取消／複製
  AnnotationWindowController.swift 標註視窗的建立、定位（依截圖大小置中、超過螢幕自動縮小顯示）
```

改快捷鍵出廠預設：`HotKeyManager.swift` 裡的 `HotKeyDefaults`（使用者自訂過的話會蓋掉這個，存在 `HotKeyStore`）。
改預設顏色／線寬：`ToolbarView.swift` 的 `colors` 陣列、`AnnotationView.swift` 的 `baseLineWidth`。
改馬賽克顆粒大小：`AnnotationView.swift` 的 `mosaicBlockSize`（越大顆粒越粗）。

重新編譯：`./build.sh`
