# Profiling and Faster Test Integration with lazy-idris

## 概要

idris2-coverage と lazy-idris の統合における設計方針を記録する。

## 役割分担

```
lazy-idris audit
  └── idris2-coverage を呼び出す
        └── テスト実行 + プロファイリング
              └── カバレッジデータを出力 (JSON)
                    └── lazy-idris が結果を読んで T-I Score 計算
```

| ツール | 責務 |
|--------|------|
| **lazy-idris** | SPEC.toml 管理、ST/SI Parity 計算、T-I Score 計算 |
| **idris2-coverage** | テスト実行、プロファイリング、カバレッジデータ収集・出力 |

## Golden Test について

### 現状

現在 lazy-idris は Golden Test (期待出力ファイルとの差分比較) を採用している：

```
REQ_COV_LIN_001_Test.idr      ← テストコード
REQ_COV_LIN_001_Test.expected ← 期待される出力
```

### Golden Test の位置づけ

Golden Test は **CLI 出力の差分検出** に優れているため選定された：

- ✅ 出力フォーマットの変更を即座に検出
- ✅ 人間が読める形式でテスト結果を確認
- ✅ セットアップが簡単 (実行して出力を保存するだけ)

しかし、**必須ではない**：

- カバレッジ計測には `IO Bool` を返すユニットテストで十分
- Per-Module 移行後は明示的な pass/fail 判定が主体
- Golden Test は CLI ツールの出力検証など、特定用途に限定可能

### 移行後のテスト形式

```idris
-- Golden Test (現状)
main : IO ()
main = do
  result <- someFunction
  putStrLn $ show result  -- .expected と比較

-- Unit Test (移行後)
test_someFunction : IO Bool
test_someFunction = do
  result <- someFunction
  pure $ result == expectedValue  -- Bool で判定
```

Per-Module 移行により、Golden Test への依存は軽減される。

---

## テストランナー DI (Dependency Injection)

### 概念

lazy-idris にテストランナーを差し替え可能にする設計：

```
lazy-idris audit                              # デフォルト: idris2-coverage
lazy-idris audit --test-runner=idris2-coverage  # 明示的に指定 (同上)
lazy-idris audit --test-runner=golden         # 従来方式 (後方互換)
```

**デフォルト**: `idris2-coverage` を採用。速度とカバレッジの両方を得られるため。

### 比較

| 項目 | Golden Test Runner | idris2-coverage Runner |
|------|-------------------|----------------------|
| 実行速度 | 遅い (Per-Requirement) | 速い (Per-Module) |
| カバレッジ | なし | あり (プロファイリング) |
| セットアップ | 簡単 (.expected 作成) | 要 idris2-coverage |
| 出力検証 | 詳細 (差分表示) | pass/fail のみ |

### メリット

1. **移行コスト低減**
   - 既存プロジェクトは Golden Test をそのまま使える
   - 新規/移行済みプロジェクトは idris2-coverage を選択

2. **段階的移行**
   - プロジェクト単位で移行可能
   - 全体を一度に変更する必要なし

3. **選択の自由**
   - CLI 出力検証が重要 → Golden Test
   - 速度とカバレッジが重要 → idris2-coverage

### インターフェース

```toml
# lazy-idris.toml
[test]
runner = "idris2-coverage"  # or "golden"

# idris2-coverage 使用時のオプション
[test.idris2-coverage]
profile = true
output = "coverage.json"
```

### 実装イメージ

```
lazy-idris audit
  │
  ├── runner = "golden" の場合:
  │     └── 従来通り Per-Requirement で実行
  │           └── .expected と比較
  │                 └── T-I Score = test pass rate のみ
  │
  └── runner = "idris2-coverage" の場合:
        └── idris2-coverage run-tests --profile
              └── JSON 出力を読む
                    └── T-I Score = code coverage %
```

---

## テストアーキテクチャ: Per-Module

### 背景

Per-Requirement (1ファイル/1テスト) は I/O ボトルネックを引き起こす：

| 方式 | テストファイル数 | 実行時間 | I/O操作 |
|------|-----------------|---------|---------|
| Per-Requirement | 581 | 640s (seq) / 218s (8並列) | ~31,000 |
| Per-Module | ~12 | 17s (seq) / ~5s (8並列) | ~600 |

詳細: `../lazy-idris/docs/TEST_IO_BOTTLENECK_AND_PER_MODULE_UNITTEST.md`

### 採用方式

**Per-Module + 全体カバレッジ** を採用：

```idris
-- Coverage/Tests/AllTests.idr
module Coverage.Tests.AllTests

allTests : List (SpecId, String, IO Bool)
allTests =
  [ ("REQ_COV_LIN_001", "Parse quantity annotations", test_parseQuantity)
  , ("REQ_COV_LIN_002", "isErased detection", test_isErased)
  , ("REQ_COV_TYP_001", "Extract linear params", test_extractLinearParams)
  ...
  ]

main : IO ()
main = runAllTests allTests
```

### Spec ID 紐付け

Strategy B (明示的リスト) を採用：

```idris
allTests : List (SpecId, String, IO Bool)
allTests =
  [ (MkSpecId "REQ_COV_LIN_001", "description", testFunc)
  , ...
  ]
```

理由：
- 型安全
- パース容易
- 明示的で追跡しやすい

## プロファイリング戦略

### 設計判断

**問い**: Per-Module だと「どのテストがどの関数を呼んだか」が分からなくなるが、問題か？

**回答**: 問題ない。

カバレッジの本質は：
- ✅ 「この関数/分岐がテストで実行されたか」
- ❌ 「どのテストが呼んだか」（デバッグ情報であり、カバレッジメトリクスではない）

我々の目的：
```
「コードベースのどの関数/分岐がテストでカバーされているか」
```

### 実行フロー

```
idris2-coverage run-tests --profile
  │
  ├── 1. Per-Module テストバイナリをコンパイル (--profile フラグ)
  │
  ├── 2. 全テスト実行 (~5秒)
  │
  ├── 3. プロファイル出力を収集
  │
  ├── 4. 関数/分岐カバレッジを集計
  │
  └── 5. JSON 出力
        {
          "functions": {
            "parseQuantity": {"calls": 15, "covered": true},
            "isErased": {"calls": 8, "covered": true},
            "generateReport": {"calls": 0, "covered": false}
          },
          "summary": {
            "total": 103,
            "covered": 87,
            "coverage": 84.5
          }
        }
```

### lazy-idris との連携

```
lazy-idris audit
  │
  ├── ST Parity: SPEC.toml の [[spec]] とテスト関数名をマッチ
  │     └── allTests リストから SpecId を抽出
  │
  ├── SI Parity: SPEC.toml の [[type]] と実装をマッチ
  │
  └── T-I Parity: idris2-coverage の JSON 出力を読む
        └── coverage rate を T-I Score として使用
```

## 移行計画

### 現状
- 44 個の Per-Requirement テストファイル (`REQ_*_Test.idr`)
- 各テストは独立した `main` を持つ

### 目標
- モジュール別テストスイート (Per-Module)
- 単一の `allTests` リストで Spec ID を管理

### ステップ

1. **テストランナー作成**
   - `Coverage/Tests/TestRunner.idr` を作成
   - `runAllTests : List (SpecId, String, IO Bool) -> IO ()` を実装

2. **モジュール別テストファイル作成**
   - `Coverage/Tests/LinearityTests.idr` (LIN_001-004)
   - `Coverage/Tests/TypeAnalyzerTests.idr` (TYP_001-004)
   - `Coverage/Tests/StateSpaceTests.idr` (SPC_001-004)
   - etc.

3. **統合テストスイート作成**
   - `Coverage/Tests/AllTests.idr`
   - 全モジュールの allTests をインポート・結合

4. **プロファイリング統合**
   - `--profile` フラグでコンパイル
   - プロファイル出力のパース
   - JSON カバレッジレポート生成

5. **旧テストファイル削除**
   - Per-Requirement ファイルを削除
   - .expected ファイルも削除

## メリット

| 項目 | 効果 |
|------|------|
| 実行速度 | 44× 高速化 (218s → ~5s) |
| I/O削減 | 52× 削減 (~31,000 → ~600) |
| 設計簡潔性 | 役割分担明確、二重実行なし |
| Spec追跡 | 明示的リストで型安全 |

---

## 実装状況

### 完成したモジュール (v0.4.0)

1. **Coverage.ProfileParser** - Chez Scheme プロファイル HTML パーサー
   - `profile.html` と `*.ss.html` を解析
   - 関数ヒット数、式カバレッジを抽出
   - JSON 出力対応

2. **Coverage.SchemeMapper** - Scheme 関数名を Idris 識別子にマッピング
   - `PreludeC-45Show-u--show_Show_Nat` → `Prelude.Show.show`
   - ランタイム関数 vs ユーザーコードの判別
   - モジュール別フィルタリング

### 検証結果

lazy-idris の Audit テストモジュールでプロファイリングを実行：

```bash
$ idris2 --profile ... -o audit-tests src/Audit/Tests/AllTests.idr
$ ./build/exec/audit-tests
$ idris2-coverage parse audit-tests.ss.html
```

結果:
```
ProfileResult: 277/277 functions, 73.73% expr coverage

=== Coverage Summary ===
Covered functions: 277
Uncovered functions: 0

=== Expression Coverage ===
Total expressions: 18034
Covered expressions: 13296
Expression coverage: 73.73%
```

### 残タスク

1. **CLI 統合**: `idris2-coverage run-tests --profile` コマンド
2. **分岐カバレッジ抽出**: `cond`/`case` 分岐のカバレッジ集計
3. **lazy-idris 統合**: テストランナー DI の実装
4. **JSON スキーマ**: lazy-idris が読み取る出力形式の確定
