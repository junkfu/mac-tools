# mac-tools

自己在開發、日常使用 Mac 的時候，總會碰到一些「要是能更順手一點就好了」的小地方：檔案想暫放一下再拖去別的地方、截圖想馬上畫兩筆、想一鍵跳到某個 App、忘了快捷鍵想瞄一眼。這個 repo 收的就是為了這些場景自己動手寫的工具，目的很單純：讓用 Mac 更有效率，而且照自己的習慣客製。

每個工具都是原生 Swift / AppKit 打造，開機常駐選單列、不佔 Dock，用不到的時候完全不礙眼。原始碼開放，自己編、自己簽章，哪裡不順手就改幾行調成自己要的樣子。

產品介紹頁（GitHub Pages）：**https://junkfu.github.io/mac-tools/**

## 目錄結構

```
mac-tools/
├── index.html          產品介紹頁原始檔（GitHub Pages 由 main 分支根目錄發佈）
├── NotchShelf/          瀏海暫存工具
│   ├── Sources/NotchShelf/
│   ├── build.sh
│   └── README.md        完整功能、行為說明、開發筆記
├── MacCut/              截圖標註工具
│   ├── Sources/MacCut/
│   ├── build.sh
│   └── README.md        完整功能、行為說明、開發筆記
├── AppJump/             快捷鍵 App 切換工具
│   ├── Sources/AppJump/
│   ├── build.sh
│   └── README.md        完整功能、行為說明、開發筆記
└── KeyLegend/           長按 Option 顯示熱鍵筆記
    ├── Sources/KeyLegend/
    ├── build.sh
    └── README.md        完整功能、行為說明、開發筆記
```

`NotchShelf/` 與 `MacCut/` 原本是各自獨立的 repo，用 `git subtree` 併入這個 monorepo，兩邊過去的 commit 歷史都完整保留，可以直接用 `git log NotchShelf/` 或 `git log MacCut/` 查。

## 工具

### 📥 [NotchShelf](NotchShelf/README.md)

把檔案丟到 MacBook 瀏海下方暫存，需要時再拖出來。拖入是複製、拖出預設是搬移——但只有目的端確實收到完整檔案後，暫存副本才會被刪除，大檔案也不怕拖到一半就消失。可以框選或點選多個一起拖，拖到 cmux、iTerm2 這類只認路徑的終端機也收得到。

```bash
cd NotchShelf && ./build.sh && open /Applications/NotchShelf.app
```

### ✂️ [MacCut](MacCut/README.md)

輕量截圖標註工具，取代卡頓的 LINE 內建截圖。框選直接交給系統原生的 `screencapture -i`，標註畫布只疊「已完成的合成圖」+「正在畫的這一筆」，畫的時候不會有延遲感。

```bash
cd MacCut && ./setup-signing.sh && ./build.sh && open /Applications/MacCut.app
```

### ↔️ [AppJump](AppJump/README.md)

按住右 ⌘ 再按一個字母，直接跳到那個 App，沒開就順手開起來。右 ⌘ 在 macOS 沒有任何預設用途，當觸發鍵不會跟既有快捷鍵打架——代價是 Carbon 熱鍵分不出左右 ⌘，只有 CGEventTap 讀得到左右旗標，所以這條路要「輔助使用」權限；不想授權就改綁 `⌃⌥S` 這類傳統組合鍵，那條路完全不用權限。

```bash
cd AppJump && ./setup-signing.sh && ./build.sh && open /Applications/AppJump.app
```

### ⌨️ [KeyLegend](KeyLegend/README.md)

單獨長按 Option 約 0.35 秒，浮出一份自己手寫、分好類的熱鍵筆記，放開就消失。筆記就是一個純文字檔（`## 分類` 開一類、`按鍵: 說明` 記一條），用慣用的編輯器改、存檔立刻生效；面板不搶焦點也不擋滑鼠，前景 App 照常操作。

```bash
cd KeyLegend && ./setup-signing.sh && ./build.sh && open /Applications/KeyLegend.app
```

## 共同的設計原則

- **原生 Swift / AppKit**：不套跨平台框架，啟動快、記憶體佔用低。
- **只住選單列**：沒有主視窗、不佔 Dock。
- **零額外相依**：只需要 Xcode Command Line Tools，`./build.sh` 就能編譯。
- **個人工具，原始碼開放**：先解決自己的痛點，不追求功能齊全；自己編、自己簽章，改幾行程式碼就能照習慣調整。

## 更新產品介紹頁

`index.html` 是純靜態頁面，改完直接 commit 到 `main` 分支、push 上去，GitHub Pages 會自動重新部署。
