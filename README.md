# Codex + GitHub Copilot Repository Knowledge Starter

CodexとGitHub Copilotが、リポジトリ内で得た調査結果、失敗、設計判断、実装上の非自明な知識を共有し、次回以降のセッションで低コストに再利用するためのスターター。

## 設計方針

**知識とSkillは共通、製品固有部分だけ薄いアダプタに分ける。**

```text
共通層
  AGENTS.md
  .agents/skills/repo-knowledge/
  .agents/agent-guides/knowledge-explorer.md
  docs/knowledge/
  docs/plans/

Codex adapter
  .codex/agents/knowledge_explorer.toml

GitHub Copilot adapter
  .github/copilot-instructions.md
  .github/agents/knowledge-explorer.agent.md
```

`AGENTS.md` と `.agents/skills/` はCodexとGitHub Copilotの両方で利用できるため、主要ロジックを二重管理しない。

## 導入

このディレクトリの内容を対象Gitリポジトリのルートへコピーする。

- 既存の `AGENTS.md` がある場合は上書きせず、共通ルールを統合する。
- 既存の `.github/copilot-instructions.md` がある場合は、互換レイヤーの内容を統合する。
- 既存のCodex/Copilot custom agentがある場合は、同名エージェントとの競合を確認する。

## 構成

```text
AGENTS.md
.agents/
  agent-guides/
    knowledge-explorer.md
  skills/repo-knowledge/
    SKILL.md
    references/persistence-policy.md
    scripts/search_knowledge.py
    scripts/rebuild_index.py
.codex/agents/
  knowledge_explorer.toml
.github/
  copilot-instructions.md
  agents/knowledge-explorer.agent.md
docs/knowledge/
  README.md
  INDEX.md
  investigations/
  decisions/
  patterns/
  runbooks/
docs/plans/
  README.md
  TEMPLATE.md
```

## 動作イメージ

```text
通常タスク
  ↓
repo-knowledge Skill（Codex / Copilot共通）
  ↓
INDEXを検索 ── 候補明確 → 必要文書だけ読む
  ↓候補不明
knowledge本文を対象限定検索
  ↓まだ重い/曖昧
knowledge-explorer
  ├─ Codex: GPT-5.6 Luna xhigh / read-only
  └─ Copilot: GPT-5.6 Luna / read+search only
  ↓
関連知識だけ親へ返す
  ↓
親が現在コード/外部仕様を再検証して判断・実装
  ↓
終了前に永続化判定
  ↓
価値がある場合のみknowledge更新 + INDEX再生成
```

## Windows / Linux互換

Skill付属スクリプトは **Python 3.6+、標準ライブラリのみ**で動作するようにしている。
Rocky Linux 8系の古いPython 3環境も想定し、Python 3.7+専用構文や外部PyPIパッケージは使用しない。

`rg`、bash、PowerShellは必須ではない。検索は次の順で利用する。

1. Codex/Copilot/IDEの組み込み検索機能。
2. `scripts/search_knowledge.py`。
3. 環境に既にある場合だけ `rg` 等。

Pythonコマンド例:

```text
Linux:   python3 .agents/skills/repo-knowledge/scripts/rebuild_index.py
Windows: py -3 .agents/skills/repo-knowledge/scripts/rebuild_index.py
```

Windowsで `py` が無い場合は、利用可能な `python` コマンド等を使う。

> このスターターのOS互換性は、リポジトリ内のSkill・文書・補助スクリプトについてのもの。Codex/Copilot本体の各クライアントが特定OSを公式サポートするかは別問題なので、導入先クライアントの要件を確認する。

## Knowledge Explorerのモデル

### Codex

`.codex/agents/knowledge_explorer.toml` で `gpt-5.6-luna` + `xhigh` + `read-only` を固定する。

### GitHub Copilot

`.github/agents/knowledge-explorer.agent.md` では `GPT-5.6 Luna` を指定し、ツールを `read` / `search` に限定する。

GitHub Copilotのcustom agent profileには現時点でreasoning effortを固定するfrontmatter項目がないため、Codexの `xhigh` と完全に同一にはできない。Copilotクライアント側でreasoningを設定できる場合は、深い横断探索時だけ高いreasoningを選ぶ運用にする。

## GitHub Copilot互換レイヤー

GitHub Copilotは多くのAgent面で `AGENTS.md` を利用できるが、GitHub.comの通常Copilot Chatなど一部の面では `.github/copilot-instructions.md` がリポジトリ全体の命令として使われる。そのため薄い互換ファイルを置き、正本の `AGENTS.md` と共通Skillへ誘導する。

## Memoriesについて

Copilot MemoryやCodex Memoriesは補助的な想起層として利用してよいが、このスターターはそれらを前提にしない。共有・再現可能で必須の知識はGit管理される `AGENTS.md` / `docs/knowledge/` を正とする。
