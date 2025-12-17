# Idris2 実用テストカバレッジ

## 結論

**Idris2 の実用的 Test Coverage で解決すべき問題は1つだけ**：

> Absurd / Impossible が分母に混ざって 100% にならない問題

これ以外は全部どうでもいい。

---

## 1. 実用要件（3行）

1. **実行時に到達し得ない分岐を、分母から除外したい**
2. **到達し得るのにテストされていない分岐だけを Gap として見たい**
3. **100% が理論的に達成可能であってほしい**

「semantic」も「証明」も不要。
**CI で赤くすべき場所だけ赤くしたい**、それだけ。

---

## 2. 100% を阻害する唯一の原因

実際に 100% を阻害するのは **Absurd Pattern 由来のケースだけ**。

Idris2 において：
- `impossible` は「到達しないと信じてよい」もの
- ユーザが明示的に書いている（or `Uninhabited` 経由）
- 破られたらテスト以前に言語のバグ

実用上の結論：

> **Impossible = 実行時に来ない前提でよい**

---

## 3. 分母の分類（これだけ覚えればOK）

| 分岐の種類 | 分母に入れる？ | 理由 |
|-----------|--------------|------|
| Canonical | **入れる** | 普通にテストすべき |
| Impossible | 入れない | ユーザが不可能と宣言 |
| No clauses in void | 入れない | 実行不能 |
| Nat case not covered | 入れない | 最適化 artifact |
| Unhandled input (partial) | **入れる** | バグ候補 |

これで **100% は理論上必ず達成可能**。

---

## 4. 現在の実装（すでに正解）

`--dumpcases` の CRASH 分類：

```
CrashNoClauses      → 除外（void 等）
CrashOptimizerNat   → 除外（Nat 最適化）
CrashUnhandledInput → coverage gap（バグ）
CrashUnknown        → conservative gap
```

対応する `BranchClass`：

```idris
BCCanonical          -- 分母に入る
BCExcludedNoClauses  -- 分母から除外
BCOptimizerNat       -- 分母から除外
BCBugUnhandledInput  -- 分母に入る（Gap）
BCUnknownCrash       -- 分母に入る（conservative）
```

---

## 5. なぜ「精密な BranchId マッピング」は不要か

よくある誤解：

> 「.ss.html の line hit と --dumpcases の BranchId を
> 正確に対応させないと semantic coverage にならない」

**不要な理由**：

1. 100% を壊しているのは absurd だけ
2. absurd は `--dumpcases` で判別できる
3. 実行 hit の粒度は Scheme レベルで十分

Absurd を分母から落とせば、残りは雑でも CI 用 Coverage として成立する。

---

## 6. 実用カバレッジの公式

```
PragmaticCoverage = executed / (canonical - impossible)
```

Where:
- `canonical` = `--dumpcases` の reachable 分岐数
- `impossible` = `NoClauses` + `OptimizerNat` の分岐数
- `executed` = `.ss.html` で hit > 0 の分岐数

---

## 7. CI での使い方

```bash
# カバレッジ実行
idris2-cov pkgs/MyProject

# 出力例
## Branch Classification (main binary - static)
canonical:          2883   # テスト対象
excluded_void:      45     # 除外済み
bugs:               3      # 要修正
optimizer_artifacts: 12    # 無視
unknown:            0      # 調査対象

## Runtime Coverage (test binary)
executed: 126/1517 (8%)
```

**CI 判定基準**：
- `bugs > 0` → 警告（partial code あり）
- `coverage < threshold` → 失敗

---

## 8. まとめ

> **「Absurd を無視した coverage」が欲しかっただけ**

それなら：
- 理論はいらない
- semantic は名乗らなくていい
- **Idris2 が impossible と言ったものを信じる**
- 100% を達成可能にする

現在の設計は、すでに最短・最強ルートにいる。

---

## Appendix: dunham の分類（参考）

Idris2 コミュニティ（dunham）による CRASH メッセージの分類：

| メッセージ | 意味 | 扱い |
|-----------|------|------|
| "No clauses in ..." | void 等の空関数 | 除外（安全） |
| "Unhandled input for ..." | partial code | Gap（バグ） |
| "Nat case not covered" | Nat→Integer 変換 | 除外（optimizer） |
| その他 | 不明 | conservative に Gap |

> downstream consumers probably shouldn't treat all CRASH cases equivalently

この助言に従い、CRASH を一律に扱わず分類している。

---

*実用主義的カバレッジ仕様 v1.0*
*2024-12-17*
