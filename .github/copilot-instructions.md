# GitHub Copilot compatibility instructions

このリポジトリのAIエージェント向け共通ルールの正本はルートの `AGENTS.md` である。
GitHub Copilotの利用面で `AGENTS.md` が自動適用されない場合も、リポジトリ作業では `AGENTS.md` のルールを確認して従う。

- 非自明な調査、デバッグ、設計、実装、外部仕様の検証では、関連する場合に `.agents/skills/repo-knowledge/SKILL.md` の `repo-knowledge` Skillを使用する。
- 恒久知識の正本は `docs/knowledge/`。Copilot Memoryやチャット履歴だけを必須知識の唯一の保存先にしない。
- `docs/knowledge/` 全体を無条件に読み込まず、Skillの段階的探索を使う。
- 深い横断探索が必要なら、利用可能な場合は `.github/agents/knowledge-explorer.agent.md` の `knowledge-explorer` を使用する。
- OS固有コマンドを前提にせず、WindowsとLinuxの両方で成立する手段を優先する。
