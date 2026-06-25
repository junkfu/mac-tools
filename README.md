# NotchShelf

把檔案丟到 MacBook 瀏海（notch）下方暫存的小工具，需要時再拖出來。
原生 Swift / AppKit，常駐在選單列，不佔 Dock。

## 功能

- **拖入暫存**：把檔案拖到瀏海下方，面板會展開，放開即暫存。
- **拖出取用**：滑鼠移到瀏海下方面板會展開，把項目拖到 Finder 或任何 App 即可取出。
- **暫存位置**：`~/Library/Application Support/NotchShelf/Stash`（選單可直接打開）。
- **選單列**：展開／收合、打開暫存資料夾、搬移模式開關、清空、結束。

## 行為說明（重要）

- **拖入＝複製**：原始檔案保留不動，只把副本放進暫存。
- **拖出＝搬移（預設）**：把項目從瀏海拖到 Finder/App，檔案送達後就會從暫存資料夾刪除（真正的搬移）。
  拖出使用 `NSFilePromiseProvider`，**只有在目的端確實收到完整檔案後**才刪除暫存副本，
  即使是大型檔案也不會發生複製未完成就被刪除的問題；若目的端沒有接收（例如不支援的 App），暫存檔會保留。
  每個項目右上角有 **×** 可手動移除；丟到「垃圾桶」也會移除。
- **改成複製**：若想拖出後仍保留暫存副本，到選單把「拖出後從暫存移除」關掉即可。

## 編譯與安裝

需要 Xcode Command Line Tools（已內含 Swift 與 macOS SDK）。

```bash
cd NotchShelf
./build.sh
open NotchShelf.app
```

`build.sh` 會：release 編譯 → 組裝 `NotchShelf.app` → ad-hoc 簽章。

啟動後沒有視窗也沒有 Dock 圖示，瀏海下方會出現一條深色小條（選單列也會有 📥 圖示）。

### 開機自動啟動（選擇性）

系統設定 →「一般」→「登入項目」→ 加入 `NotchShelf.app`。

## 開發

```
Sources/NotchShelf/
  main.swift                 進入點（accessory app）
  AppDelegate.swift          選單列、生命週期
  ShelfStore.swift           暫存資料夾與檔案清單
  NotchWindowController.swift 浮動面板定位、展開／收合
  ShelfRootView.swift        拖入目標、面板內容、hover 偵測
  ShelfItemView.swift        單一項目（icon + 名稱 + ×），負責拖出
```

重新編譯：`./build.sh`
