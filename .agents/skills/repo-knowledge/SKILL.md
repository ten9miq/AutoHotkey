---
name: repo-knowledge
description: リポジトリの過去知識を低コストで検索・再検証・更新するSkill。調査、デバッグ、設計、非自明な実装、GitHub Issueや外部記事・仕様の検証など、将来再利用できる知見が生まれうる作業で使用する。単純な編集、明白なコード質問、一時的な進捗記録だけでは使用しない。
---

# Repository Knowledge Lifecycle

`docs/knowledge/` を、Codex / GitHub Copilot / 人間が共有できるGit管理の恒久知識として扱う。
目的は「毎回大量の文書を読む」ことではなく、過去の有用な知見を必要な時だけ検索し、現在状態で検証して再利用することである。

## 0. ポータビリティ

このSkillはWindowsとLinuxの両方で動作することを前提とする。

- 特定シェルを前提にしない。
- `rg` は利用可能なら使ってよいが、必須ではない。
- 検索は、エージェント/IDEの組み込み検索ツールを最優先する。
- deterministicな検索が必要でPython 3.6+がある場合は `scripts/search_knowledge.py` を使う。
- INDEX再生成はPython 3.6+標準ライブラリだけで動く `scripts/rebuild_index.py` を使う。
- Pythonの実行コマンドは環境に応じて選ぶ。Linuxでは通常 `python3`、Windowsでは通常 `py -3` または `python`。

## 1. 作業開始時: 検索を安い順に行う

### Level 1: 圧縮インデックス検索

`docs/knowledge/INDEX.md` が存在する場合、最初から全文をコンテキストへ取り込まず、タスクのキーワード、対象パス、コンポーネント名、エラー名などで検索する。

推奨順:

1. 利用中のエージェントに組み込みのファイル/テキスト検索。
2. Python 3.6+が利用できる場合:
   - Linux例: `python3 .agents/skills/repo-knowledge/scripts/search_knowledge.py raw-input hid rollermouse`
   - Windows例: `py -3 .agents/skills/repo-knowledge/scripts/search_knowledge.py raw-input hid rollermouse`
3. `rg` が既に利用可能なら、例えば `rg -n -i 'raw input|hid|rollermouse' docs/knowledge/INDEX.md`。

候補が少数に絞れたら、その文書だけを読む。

### Level 2: 対象限定検索

INDEXだけで十分に絞れないが検索語や対象パスが分かる場合は、必要な範囲だけ検索を広げる。

- 組み込み検索機能で `docs/knowledge/` 内のfrontmatter、見出し、本文を検索する。
- Python検索を使う場合は `search_knowledge.py --content ...` を使う。
- 「なぜこの実装なのか」「いつ壊れたか」など履歴が重要な場合だけ、対象パスに限定して `git log` / `git blame` を確認する。
- 関連しそうな文書をすべて読むのではなく、検索結果から上位候補を選ぶ。

### Level 3: Knowledge Explorer

以下のいずれかなら、カスタム/サブエージェントが利用可能な場合は `knowledge-explorer` を明示的に起動し、横断探索を委譲する。

- 候補が多く、メインエージェントが多数のknowledge文書を読むことになりそう。
- 複数分野にまたがり、キーワードだけでは関連度を判断しにくい。
- 過去文書同士の矛盾、廃止、上書き関係を整理する必要がある。
- 過去の失敗・設計判断・調査結果を横断的に照合する必要がある。
- INDEXが古い、または十分な候補を返さないが、過去知識が存在する可能性が高い。

製品別の実装:

- Codex: `.codex/agents/knowledge_explorer.toml`
- GitHub Copilot: `.github/agents/knowledge-explorer.agent.md`
- 共通の探索仕様: `.agents/agent-guides/knowledge-explorer.md`

`knowledge-explorer` には探索と要約だけを任せる。最終的な設計判断・実装判断は親エージェントが現在のコードと要件を確認して行う。

サブエージェントが利用不可、起動されなかった、またはクライアントがcustom agentをサポートしない場合はブロックせず、メインエージェントがLevel 2へフォールバックする。

## 2. 利用時: Just-in-timeで再検証する

過去知識を重要な判断に使う前に、その知識が現在ブランチでも成立するかを安価に確認する。

- 記録されたファイル、シンボル、テスト、設定などの根拠を確認する。
- 行番号は移動しやすいため、パス + シンボル/識別子/テスト名を優先して検証する。
- `freshness: version-sensitive` または `volatile` の外部仕様は、現在のタスクで重要なら現行の一次情報を再確認する。
- 過去知識と現在コードが矛盾する場合、過去知識を盲目的に適用しない。

## 3. 調査・実装中: 保存候補を見極める

保存候補は「将来の別セッションで、調査や誤りを実質的に減らすか」で判断する。

特に以下を候補とする。

- 確認済みの根本原因。
- コードだけから直ちには分からない制約や挙動。
- 重要な設計判断と、その代替案・理由・結果。
- 将来再試行されそうな失敗したアプローチと失敗条件。
- 複数ファイルやコンポーネント間の非自明な同期関係。
- 再利用可能なデバッグ、検証、復旧手順。
- 実装判断に直接影響する外部仕様、GitHub Issue、公式記事等の確認結果。

一方、生ログ、一時的な進捗、コードの単純な要約、未検証の思いつきは保存しない。

## 4. 作業終了時: 永続化判定

実質的な調査・デバッグ・設計・実装を行った場合、最終回答の前に一度だけ永続化判定を行う。

永続化する場合は、まず `references/persistence-policy.md` を読み、既存文書の更新を新規作成より優先する。

分類:

- `investigations/`: 原因調査、外部調査、実験結果、失敗と検証。
- `decisions/`: 重要な設計・技術判断。ADRに近い形式。
- `patterns/`: リポジトリ固有の非自明な規約、同期関係、実装パターン。
- `runbooks/`: 再現可能な調査、復旧、運用、検証手順。

知識を書いた後、Python 3.6+が利用できる場合はINDEXを再生成・検証する。

- Linux例: `python3 .agents/skills/repo-knowledge/scripts/rebuild_index.py`
- Windows例: `py -3 .agents/skills/repo-knowledge/scripts/rebuild_index.py`

そのコマンド名が利用できなければ、別のPython 3インタープリタを使う。Pythonを利用できない場合は、`docs/knowledge/INDEX.md` の該当エントリを手動で最小限更新する。

## 5. 長期タスクとの分離

現在進行中の計画、チェックポイント、未完了項目、作業再開用メモは `docs/plans/` に置く。

完了後、そこから将来も価値がある知識だけを `docs/knowledge/` に蒸留する。進捗ログ全体をknowledgeへコピーしない。
