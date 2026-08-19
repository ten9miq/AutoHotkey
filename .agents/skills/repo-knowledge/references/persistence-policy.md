# Knowledge Persistence Policy

この文書はCodex/GitHub Copilot共通で使用する。knowledge本文は特定AI製品やOSに依存させず、Windows/Linuxのどちらからも再検証できる形を優先する。
リポジトリ内パスは `/` 区切りで記録する。OS固有コマンドが根拠として必要な場合は、対象OSを明示する。

この文書は、`repo-knowledge` Skill が知識を新規作成・更新するときだけ読む。

## 保存ゲート

次の3条件を原則として満たす内容だけを恒久化する。

1. **再利用性**: 将来の別タスク・別セッションでも使う可能性がある。
2. **非自明性**: コードやREADMEを一読すれば分かる内容ではない。
3. **根拠**: コード、テスト、実行結果、コミット、Issue、公式仕様などで裏付けられる。

「今回やったこと」ではなく「次回の判断を変える事実」を保存する。

## 文書の状態

frontmatter の `status` は次から選ぶ。

- `current`: 現在有効と確認済み。
- `provisional`: 有力だが追加確認が必要。
- `superseded`: 新しい判断・知識に置き換えられた。削除せず置換先を本文に記載する。
- `stale`: 現在の状態と合わないことが判明したが、履歴として残す価値がある。

`freshness` は次から選ぶ。

- `stable`: リポジトリ固有の設計理由など、頻繁には変わらない。
- `version-sensitive`: ライブラリ、OS、API、製品仕様等のバージョンに依存する。
- `volatile`: 外部サービス、価格、現行Issue状況など変化が速い。

## frontmatter

各knowledge文書は次の最小メタデータを持つ。値は1行に収める。

```yaml
---
type: investigation
status: current
summary: "Raw Inputで特定HIDを識別する際の確認済み制約"
tags: "raw-input, hid, input"
paths: "src/input/**"
last_verified: "2026-08-20"
verified_commit: "abc1234"
freshness: stable
---
```

- `type`: `investigation` / `decision` / `pattern` / `runbook`
- `summary`: INDEX検索に使える、結論中心の1文。
- `tags`: 検索語。過剰に増やさない。
- `paths`: 関連する代表的パス。複数ならカンマ区切り。
- `last_verified`: 最後に現在状態で確認した日。
- `verified_commit`: 可能なら確認時の短いGit commit。取得できなければ空でもよい。
- `freshness`: `stable` / `version-sensitive` / `volatile`

## 根拠の残し方

本文には、重要な結論ごとに再検証できる根拠を残す。

### リポジトリ内の根拠

優先順位:

1. ファイルパス + シンボル/関数/クラス/設定キー/テスト名。
2. 再現または検証コマンド。
3. 関連コミット、PR、Issue。
4. 行番号は補助としてのみ利用する。

### 外部の根拠

GitHub Issue、公式ドキュメント、仕様、技術記事等を利用した場合は、少なくとも以下を残す。

- タイトルまたは識別可能な名称。
- URL。
- 確認日。
- そのソースが支える具体的な事実。

外部記事の一般的な要約を大量に保存しない。リポジトリの判断や実装に影響した部分だけを蒸留する。

可能ならブログ記事より公式仕様、公式ドキュメント、原著論文、公式GitHub Issue/PRなど一次情報を優先する。

## Just-in-time verification

既存知識を再利用する際は、全文を再調査するのではなく、今回依存する主張の根拠だけを確認する。

- パス/シンボルが消えていれば、その知識を再評価する。
- 現在コードが反対の挙動を示す場合は現在コードを優先する。
- 外部仕様が `version-sensitive` / `volatile` なら、重要な判断に使う前に現行情報を再確認する。
- 知識が無効になった場合、削除より `superseded` / `stale` と置換先・理由を残すことを優先する。

## 既存文書の更新を優先

同一テーマの文書がある場合は新規作成しない。

新規文書にするのは、以下のいずれかの場合に限る。

- 独立した問題・判断である。
- 既存文書に追記すると検索性または意味が著しく悪化する。
- ADRとして独立したライフサイクルを持たせるべき設計判断である。

## 文書テンプレート

### Investigation

```markdown
---
type: investigation
status: current
summary: "<結論中心の1文>"
tags: "<tag1, tag2>"
paths: "<関連パス>"
last_verified: "YYYY-MM-DD"
verified_commit: "<short hash>"
freshness: stable
---

# <調査タイトル>

## 結論

## 背景・発生条件

## 確認した事実

## 失敗したアプローチ

### <方法>
- 結果:
- 失敗条件/理由:
- 再試行する条件:

## 有効だった方法 / 現在の実装

## 根拠

### Repository
- `<path>` — `<symbol/test/config>`

### External
- `<title>` — `<URL>` — 確認日: `YYYY-MM-DD`
  - 支える事実: ...

## 未解決・再確認条件
```

### Decision

```markdown
---
type: decision
status: current
summary: "<何を選び、なぜ重要か>"
tags: "<tag1, tag2>"
paths: "<関連パス>"
last_verified: "YYYY-MM-DD"
verified_commit: "<short hash>"
freshness: stable
---

# <設計判断>

## Status
Current

## Context

## Decision

## Alternatives

## Consequences

## Evidence

## Revisit when
```

### Pattern

```markdown
---
type: pattern
status: current
summary: "<非自明な規約・同期関係>"
tags: "<tag1, tag2>"
paths: "<関連パス>"
last_verified: "YYYY-MM-DD"
verified_commit: "<short hash>"
freshness: stable
---

# <パターン名>

## Rule / Pattern

## Why

## Applies to

## Evidence

## Exceptions
```

### Runbook

```markdown
---
type: runbook
status: current
summary: "<何を診断・復旧・検証する手順か>"
tags: "<tag1, tag2>"
paths: "<関連パス>"
last_verified: "YYYY-MM-DD"
verified_commit: "<short hash>"
freshness: version-sensitive
---

# <Runbook名>

## When to use

## Preconditions

## Procedure

## Expected result

## Failure modes

## Evidence / references
```
