# Repository Knowledge

このディレクトリは、Codex、GitHub Copilot、人間が将来の作業で再利用できる**恒久的なリポジトリ知識**を保存する。

## 目的

保存するのは作業ログではなく、次回の調査・設計・実装判断を短縮できる知識である。

- `investigations/`: 原因調査、外部調査、実験、失敗したアプローチ。
- `decisions/`: 重要な技術・設計判断と理由・代替案・結果。
- `patterns/`: リポジトリ固有の非自明な規約、同期関係、実装パターン。
- `runbooks/`: 再現可能なデバッグ、検証、復旧、運用手順。
- `INDEX.md`: 検索用の圧縮カタログ。自動生成対象。

## 原則

1. **必要な知識だけ読む。** `INDEX.md` は通常、エージェントの検索機能またはSkill付属検索スクリプトで絞り込み、最初から全文をコンテキストに入れない。
2. **利用時に再検証する。** 過去文書より現在のコード・テスト・現行仕様を優先する。
3. **根拠を残す。** ファイル + シンボル、テスト、コミット、Issue、公式仕様、URL等を記録する。
4. **外部情報は鮮度を持つ。** バージョン依存の情報は `freshness: version-sensitive`、変化が速いものは `volatile` とする。
5. **失敗にも条件を書く。** 「失敗した」だけでなく、なぜ失敗したか、どの条件なら再検討すべきかを残す。
6. **古い知識を黙って削除しない。** 履歴価値があれば `superseded` / `stale` として置換先や理由を残す。
7. **製品非依存にする。** knowledge本文にはCodex/Copilot固有の一時状態を混ぜず、どちらからでも利用できる事実・判断・手順を残す。
8. **パスは `/` 区切りで記録する。** Windows/Linux間の検索性を揃える。

詳細な保存ルールとテンプレートは `.agents/skills/repo-knowledge/references/persistence-policy.md` を参照する。

## INDEXの更新

knowledge文書を追加・更新したら、Python 3.6+が利用できる場合は再生成する。

```text
Linux:   python3 .agents/skills/repo-knowledge/scripts/rebuild_index.py
Windows: py -3 .agents/skills/repo-knowledge/scripts/rebuild_index.py
```

このスクリプトは外部パッケージを使用しない。
