# mac-tools

一個人的 macOS 選單列工具箱。每個工具都是原生 Swift / AppKit 打造，開機常駐選單列、不佔 Dock，用不到的時候完全不礙眼。

產品介紹頁（GitHub Pages）：**https://junkfu.github.io/mac-tools/**

## 目錄結構

```
mac-tools/
├── index.html          產品介紹頁原始檔（GitHub Pages 由 main 分支根目錄發佈）
├── NotchShelf/          瀏海暫存工具
│   ├── Sources/NotchShelf/
│   ├── build.sh
│   └── README.md        完整功能、行為說明、開發筆記
└── mac-cut/             截圖標註工具
    ├── Sources/MacCut/
    ├── build.sh
    └── README.md        完整功能、行為說明、開發筆記
```

`NotchShelf/` 與 `mac-cut/` 原本是各自獨立的 repo，用 `git subtree` 併入這個 monorepo，兩邊過去的 commit 歷史都完整保留，可以直接用 `git log NotchShelf/` 或 `git log mac-cut/` 查。

## 工具

### 📥 [NotchShelf](NotchShelf/README.md)

把檔案丟到 MacBook 瀏海下方暫存，需要時再拖出來。拖入是複製、拖出預設是搬移——但只有目的端確實收到完整檔案後，暫存副本才會被刪除，大檔案也不怕拖到一半就消失。

```bash
cd NotchShelf && ./build.sh && open NotchShelf.app
```

### ✂️ [mac-cut](mac-cut/README.md)

輕量截圖標註工具，取代卡頓的 LINE 內建截圖。框選直接交給系統原生的 `screencapture -i`，標註畫布只疊「已完成的合成圖」+「正在畫的這一筆」，畫的時候不會有延遲感。

```bash
cd mac-cut && ./setup-signing.sh && ./build.sh && open MacCut.app
```

## 共同的設計原則

- **原生 Swift / AppKit**：不套跨平台框架，啟動快、記憶體佔用低。
- **只住選單列**：沒有主視窗、不佔 Dock。
- **零額外相依**：只需要 Xcode Command Line Tools，`./build.sh` 就能編譯。
- **個人工具，原始碼開放**：自己編、自己簽章，改幾行程式碼就能照習慣調整。

## 更新產品介紹頁

`index.html` 是純靜態頁面，改完直接 commit 到 `main` 分支、push 上去，GitHub Pages 會自動重新部署。
