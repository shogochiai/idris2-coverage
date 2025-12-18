# Pragmatic 100% Coverage: Research Plan

## 問題設定

### 理論上の100% vs Pragmatic 100%

| 概念 | 定義 | 達成可能性 |
|-----|------|-----------|
| **理論上の100%** | `--dumpcases` の全 Canonical ブランチをカバー | 不可能（阻害要因あり） |
| **Pragmatic 100%** | 「ユーザコードの到達可能分岐」のみをカバー | 達成可能（要アーキテクチャ） |

### 阻害要因の分類

現在観測されている「分母に入れるべきでないもの」：

| カテゴリ | 例 | 現状の対応 | 理想の対応 |
|---------|-----|-----------|-----------|
| **Absurd/Void** | `No clauses in...` | 除外済み (BCExcludedNoClauses) | 完了 |
| **Optimizer Artifact** | `Nat case not covered` | 除外済み (BCOptimizerNat) | 完了 |
| **Compiler Generated** | `{csegen:N}`, `{eta:N}`, `prim__*` | targets フィルタのみ | 分母除外も検討 |
| **標準ライブラリ** | `Prelude.*`, `System.*` | targets フィルタのみ | 分母除外も検討 |
| **依存ライブラリ** | 外部パッケージ由来 | **未対応** | 要設計 |
| **型コンストラクタ** | 末尾 `.` で終わる名前 | targets フィルタのみ | 分母除外も検討 |

---

## Research Questions

### RQ1: 分母除外 vs Targets フィルタ

> 現在「targets から除外」しているものを「分母からも除外」すべきか？

**現状の哲学 (compiler-generated-functions.md より):**
- Compiler-generated は「技術的には到達可能」
- 「テスト可能」であるため、分母除外は「philosophically incorrect」

**Pragmatic 100% の観点:**
- ユーザが「100%」と言いたいなら、制御できない分岐は分母から外すべき
- **「テスト可能」と「テストすべき」は違う**

**検討事項:**
- [ ] `--pragmatic` フラグで分母計算を切り替える？
- [ ] デフォルトを pragmatic にして `--strict` で従来動作？

### RQ2: 依存ライブラリの境界

> `.ipkg` の `depends` から自動判定できるか？

**調査項目:**
- [ ] `depends` フィールドからパッケージ名取得
- [ ] パッケージ名 → モジュール prefix のマッピング
- [ ] 「自分のパッケージ」の判定方法

### RQ3: Idris2 バージョン追随

> バージョンアップで除外パターンが増えた時、どう対応するか？

**候補アプローチ:**

1. **Unknown Logger** - 未分類パターンをログ出力
2. **Versioned Config** - バージョン別設定ファイル
3. **Community Pattern DB** - 共有除外パターンデータベース

---

## Proposed Architecture

### Option A: 二段階分母

```
raw_denominator     = 全 Canonical (現在の実装)
pragmatic_denominator = raw - compiler_gen - stdlib - deps - type_ctors

JSON出力:
{
  "denominator": {
    "raw": 2883,
    "pragmatic": 1517,
    "excluded": {
      "compiler_generated": 234,
      "standard_library": 891,
      "dependencies": 156,
      "type_constructors": 85
    }
  }
}
```

### Option B: Version-Aware Exclusion Policy (採用案)

```idris
-- Idris2 バージョン表現
record IdrisVersion where
  constructor MkVersion
  major, minor, patch : Nat

-- 除外理由（追跡可能性のため）
data ExclusionReason : Type where
  AbsurdPattern       : CrashReason -> ExclusionReason
  OptimizerArtifact   : String -> ExclusionReason
  CompilerGenerated   : String -> ExclusionReason  -- {csegen:*}, prim__*, etc.
  StandardLibrary     : String -> ExclusionReason  -- Prelude.*, System.*, etc.
  DependencyLibrary   : String -> ExclusionReason  -- depends で指定されたパッケージ
  TypeConstructor     : String -> ExclusionReason  -- 末尾 "." の名前
  UserDefined         : String -> ExclusionReason  -- .idris2-cov.json で指定

-- バージョン依存パターン
record VersionPattern where
  constructor MkVersionPattern
  minVersion : Maybe IdrisVersion  -- Nothing = 全バージョン
  maxVersion : Maybe IdrisVersion  -- Nothing = 最新まで
  pattern : String -> Bool
  reason : String -> ExclusionReason

-- ExclusionPolicy: バージョン対応 + 拡張可能
record ExclusionPolicy where
  constructor MkPolicy
  idrisVersion : IdrisVersion

  -- バージョン固有パターン（Idris2 の変更に追随）
  versionPatterns : List VersionPattern

  -- 汎用パターン（バージョン非依存）
  universalPatterns : List (String -> Maybe ExclusionReason)

  -- ユーザ設定による上書き
  userOverrides : List (String -> Maybe ExclusionReason)

-- 判定関数
shouldExclude : ExclusionPolicy -> String -> Maybe ExclusionReason
shouldExclude policy name =
  -- 優先順位: user > version-specific > universal
  firstJust (map (\f => f name) policy.userOverrides) <|>
  firstJust (map (applyVersionPattern policy.idrisVersion name) policy.versionPatterns) <|>
  firstJust (map (\f => f name) policy.universalPatterns)

-- バージョン範囲チェック
applyVersionPattern : IdrisVersion -> String -> VersionPattern -> Maybe ExclusionReason
applyVersionPattern ver name pat =
  if inVersionRange ver pat.minVersion pat.maxVersion && pat.pattern name
  then Just (pat.reason name)
  else Nothing
```

**アーキテクチャの特徴:**

1. **バージョン範囲指定** - パターンごとに `minVersion`/`maxVersion` を持つ
2. **追跡可能性** - 除外理由が `ExclusionReason` として記録される
3. **優先順位** - User > Version-specific > Universal の順で評価
4. **拡張性** - 新しいカテゴリは `ExclusionReason` に追加するだけ

**バージョン依存パターンの例:**

```idris
-- Idris2 0.7.0 で追加された csegen パターン
csegen070 : VersionPattern
csegen070 = MkVersionPattern
  (Just $ MkVersion 0 7 0)  -- 0.7.0 以降
  Nothing                    -- 最新まで
  (isPrefixOf "{csegen:")
  (CompilerGenerated)

-- Idris2 0.8.0 で変更された builtin パターン（仮）
builtin080 : VersionPattern
builtin080 = MkVersionPattern
  (Just $ MkVersion 0 8 0)
  Nothing
  (isPrefixOf "_builtin.")
  (CompilerGenerated)
```

### Option C: Configuration File

```json
// .idris2-cov.json
{
  "exclusions": {
    "compiler_generated": true,
    "standard_library": true,
    "dependencies": ["contrib"],
    "custom_patterns": ["MyProject.Internal.*"]
  }
}
```

---

## Implementation Milestones

### M1: 現状の定量化
- [ ] `--json` 出力に除外カテゴリ別件数を追加
- [ ] 複数プロジェクトでデータ収集
- [ ] 「分母に残っているが除外すべきもの」の実態把握

### M2: ExclusionPolicy 型の導入
- [ ] `ExclusionReason` 型を `Types.idr` に追加
- [ ] `ExclusionPolicy` record を定義
- [ ] 既存の `isCompilerGenerated`, `isStandardLibrary` を Policy に移行

### M3: Version Detection
- [ ] `idris2 --version` 出力のパース
- [ ] `IdrisVersion` record の実装
- [ ] バージョン範囲チェック関数

### M4: Version-Aware Pattern Database
- [ ] `src/Coverage/ExclusionPatterns.idr` を新規作成
- [ ] バージョン別パターンをデータとして定義
- [ ] Unknown パターンのログ出力機能

### M5: Pragmatic Denominator
- [ ] `shouldExclude` を分母計算に統合
- [ ] JSON に `pragmatic_coverage` と `exclusion_breakdown` を追加
- [ ] `--strict` フラグで従来動作を維持

### M6: 依存ライブラリ判定
- [ ] `.ipkg` パーサに `depends` 解析追加
- [ ] パッケージ名 → モジュール prefix の推定
- [ ] `DependencyLibrary` 除外理由の実装

### M7: 設定ファイル対応
- [ ] `.idris2-cov.json` スキーマ定義
- [ ] `userOverrides` へのマッピング
- [ ] CLI オプションとの優先順位決定

---

## Version-Aware 運用フロー

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Idris2 バージョン検出                                      │
│    idris2 --version → "Idris 2 version 0.7.0-..."           │
│    → IdrisVersion { major=0, minor=7, patch=0 }             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. ExclusionPolicy 構築                                      │
│    - Universal patterns (全バージョン共通)                    │
│    - Version patterns (バージョン範囲でフィルタ)              │
│    - User overrides (.idris2-cov.json から)                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. 分母計算                                                  │
│    for each function in --dumpcases:                        │
│      reason = shouldExclude(policy, functionName)           │
│      if reason == Nothing:                                  │
│        add to pragmatic_denominator                         │
│      else:                                                  │
│        record exclusion with reason                         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Unknown Pattern 検出                                      │
│    if function looks suspicious but no pattern matches:     │
│      log as "unknown" for future investigation              │
│      → Community feedback で新パターン追加                   │
└─────────────────────────────────────────────────────────────┘
```

### Idris2 バージョンアップ時の対応

1. **新しい compiler-generated パターンが観測される**
   - `unknown` としてログに出力
   - Issue 作成 → 分類決定

2. **ExclusionPatterns.idr に追加**
   ```idris
   newPattern081 : VersionPattern
   newPattern081 = MkVersionPattern
     (Just $ MkVersion 0 8 1)
     Nothing
     (isPrefixOf "{newprefix:")
     CompilerGenerated
   ```

3. **idris2-coverage をリリース**
   - パッチバージョンで新パターン追加
   - Idris2 本体のマイナーバージョンに追随

---

## Open Questions

1. **デフォルトは strict か pragmatic か？**
   - CI 用途なら pragmatic がデフォルトで良さそう

2. **依存ライブラリの粒度は？**
   - パッケージ単位？モジュール単位？

3. **型コンストラクタの判定精度は？**
   - 末尾 `.` ルールで十分か、誤検出はないか

4. **Unknown パターンの報告先は？**
   - stderr？専用ログファイル？JSON の warnings フィールド？

---

## Success Criteria

Pragmatic 100% 達成の条件：

1. **ユーザコードのみ**が分母に含まれる
2. **除外理由が透明**で、JSON で確認可能
3. **100% が達成可能**（ユーザが全分岐をテストすれば）
4. **バージョン追随コストが最小**

---

## 参考資料

- [minimal-test-coverage.md](./minimal-test-coverage.md) - 現在の実用カバレッジ仕様
- [compiler-generated-functions.md](./compiler-generated-functions.md) - 除外パターン一覧

---

*Research Plan v0.1*
*2024-12-18*
