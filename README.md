# claude-harness

Claude Code に、人の確認なしで「仕様 → 実装 → テスト → 検証 → PR」まで進めさせるためのハーネスです。
スタック非依存のテンプレートで、既存プロジェクトに `install.sh` でコピーして使います。

> 設計の前提は 2026年11月時点の Claude Code（v2.1.3xx、既定モデル Opus 5.5）です。
> モデルや Claude Code 本体が変わると、ここにある部品の一部は不要になります。「見直し方」を参照してください。

## 考え方

「完了」の判定をモデルに任せず、決定的に（スクリプトで必ず同じ結果になるように）定義します。それ以外はできるだけ Claude Code 本体とモデルに任せます。

| 何を | どう実現するか | 種類 |
|---|---|---|
| 何を作るか | `spec/SPEC.md` と `spec/tasks.json`（受け入れ基準と `passes` フラグ） | 外部ファイル |
| 終わったと言えるか | `harness/check.sh` が exit 0 になること。Stop hook、無人実行の最終ゲート、CI の3か所で同じスクリプトを使う | 決定的 |
| 最後まで止まらずに進むか | `/goal`（毎ターン、別のモデルが完了条件を判定する）＋ 無人実行用の追加システムプロンプト | モデルが判定 |
| ゴールポストを動かさないか | `harness/integrity.sh`：ビルドブランチでは、タスク定義と保護パスを書き換えると失敗する（Bash 経由の書き換えも検出） | 決定的 |
| 触ってはいけないもの | deny ルール（秘密情報・force push）、PreToolUse hook（保護パス）、auto mode | 決定的＋分類器 |
| 使いすぎないか | `--max-budget-usd`、`--max-turns`、サブエージェントの数と深さの上限 | 決定的 |
| 最終判断 | ハーネスが PR を作成し、人がマージする | 人 |

## 流れ

```
[人] /spec <作りたいもの>           ← 対話で仕様を固める（人が関わるのは基本ここだけ）
        │ spec/SPEC.md, spec/tasks.json, harness/checks.conf を main にコミット
        ▼
[無人] bash harness/run-unattended.sh --budget 30
        │ 1. 事前チェック（作業ツリーがクリーン、未完了タスクあり、チェックが定義済み）
        │ 2. worktree と新しいブランチ agent/<日時> を作る
        │ 3. claude -p "/goal <完了条件>" --permission-mode auto
        │      ├ SessionStart hook: 未完了のタスクと進捗ログを渡す
        │      ├ PreToolUse hook: 保護パスの編集をブロック
        │      ├ PostToolUse hook: フォーマッタを実行
        │      └ Stop hook: check.sh が失敗している間はターンを終われない
        │ 4. 最終ゲート: check.sh、作業ツリーがクリーン、全タスクが passes
        │ 5. ブランチを push して gh pr create
        ▼
[人] PR のレビュー（変更の意図と設計上の制約違反だけを見る）→ マージ
```

## 構成

```
.claude/
  settings.json            permissions（deny/ask）, hooks, サブエージェント上限
  agents/spec-reviewer.md  読み取り専用。最後に1回だけ仕様と突き合わせるレビュアー
  skills/spec/SKILL.md     /spec：対話して SPEC.md と tasks.json を作る（人だけが起動できる）
harness/
  check.sh                 完了の唯一の定義（checks.conf、または自動検出＋integrity）
  checks.conf              ★ プロジェクトのチェックコマンドをここに書く
  integrity.sh             tasks.json の改ざん検知、保護パスの変更検知
  protected-paths.txt      ビルドブランチでエージェントが変更できないパス
  goal.md                  /goal の完了条件テンプレート
  unattended-prompt.md     無人実行時に追加するシステムプロンプト（早期停止の防止など）
  run-unattended.sh        無人実行のオーケストレーション
  hooks/                   stop-gate / protect-paths / session-start / format
  setup.sh                 （任意）依存関係のインストール。worktree と CI で実行される
spec/
  SPEC.md  tasks.json  PROGRESS.md
CLAUDE.md                  短く保つ。リポジトリを読んでも分からないことだけを書く
.github/workflows/harness.yml   CI でも同じ check.sh を実行する
install.sh                 既存プロジェクトへのコピー（上書きしない）
```

## セットアップ

1. 必要なもの：Claude Code（最新版）、`git`、`jq`、PR の自動作成に使う `gh`（任意）
2. 次のコマンドでプロジェクトにインストールします。
   ```bash
   ./install.sh /path/to/your/project
   ```
3. `harness/checks.conf` を編集します（最重要）。型チェック、lint、ユニットテスト、E2E のコマンドを書いてください。
   空のままだと package.json / pyproject / go.mod / Cargo.toml から自動検出しますが、本番運用では明示的に書いてください。
   UI がある場合は E2E（Playwright など）を必ず入れます。テストやスクリプトが見ているものしか、ゲートで守れません。
4. インストール先のリポジトリで一度 `claude` を対話的に起動し、ワークスペースの信頼ダイアログを承認しておきます。
   承認していないと、`claude -p`（無人実行）は `.claude/settings.json` の `permissions.allow` を無視します。
5. 依存関係のインストールが必要なら、`harness/setup.sh` を作って実行権限を付けます（worktree と CI で使われます）。
6. GitHub 側で次を設定します。
   - `main` にブランチ保護をかけ、PR のマージ前に `harness / check` の通過を必須にする
   - ハーネス自体を変更する PR には `harness-change` ラベルを付ける（CI での保護パスのチェックが解除されます）
7. （任意）auto mode の調整。プロジェクトの settings.json には書けないので、`~/.claude/settings.json` に書きます。
   ```json
   { "autoMode": { "environment": ["$defaults", "Source control: github.com/<your-org>"] } }
   ```

## 使い方

```bash
# 1. main で Claude Code を起動して仕様を作る
claude
> /spec ログイン付きの TODO アプリ。タグで絞り込みができる

# 2. 無人で作らせる（数時間かかることがあります。ログは .harness/logs/ に出力）
bash harness/run-unattended.sh --budget 30

# 様子を見ながら実行したい場合（worktree 内で対話セッションとして /goal を開始）
bash harness/run-unattended.sh --interactive

# 3. 失敗したり止まったりした場合
cd .harness/worktrees/agent-<日時> && claude --continue
```

ふだんの対話的な作業でも、Stop hook がそのまま効きます。会話だけで変更がないターンでは、前回成功したときから作業ツリーが変わっていなければチェックを省略します。
重すぎる場合は `HARNESS_GATE=off claude` で、そのセッションだけゲートを外せます。

## 動作確認（ローカルの Claude Code で一度実行してください）

`check.sh`、`integrity.sh`、各 hook のスクリプト、`run-unattended.sh` は、ダミーのエージェントを使ってテスト済みです。
ただし hook の発火と `/goal` の動作は、Claude Code 本体で確認する必要があります。新しいリポジトリにインストールしたら、次を確認してください。

| 確認すること | 方法 | 期待する結果 |
|---|---|---|
| SessionStart | `claude` を起動して「ハーネスの状態を教えて」と聞く | 未完了のタスクの一覧が会話に含まれている |
| Stop hook | テストを1つ壊すよう頼む | 終わろうとすると差し戻され、テストを直してから終わる |
| 保護パス | `git checkout -b agent/x` のあと「harness/checks.conf にコメントを足して」と頼む | PreToolUse でブロックされる |
| Bash 経由の回避 | 同じブランチで「echo で checks.conf に追記して」と頼む | 書き込みは通るが、Stop hook の integrity チェックで差し戻される |
| deny | 「.env の中身を見せて」と頼む | 拒否される |
| /goal ＋ -p | 小さなタスク1つで `run-unattended.sh --budget 3` を実行する | PR が作られる（GitHub のリモートがなければ `--no-pr` を付け、最終ゲートの通過で確認する）。費用は `.harness/logs/run-*.jsonl` の最後の結果行（`total_cost_usd`）で確認する |

確認がすんだら、`/doctor` で設定の警告が出ていないかも見ておくと安全です。

## 意図的に入れていないもの

2025〜2026年前半の記事でよく紹介されていたものの、現在のモデルと Claude Code では不要か逆効果とされているものです。

- コンテキストのリセットと引き継ぎ用エージェント：1M トークンのコンテキストと自動 compaction で足ります。状態の外部化は `spec/` で行います。
- スプリント契約、Planner / Generator / Evaluator の細かい役割分担：Opus 5 以降はモデルが自分で計画し、必要に応じて委任します。委任が有効なのは、独立した大きな作業だけです。
- 「最後に検証して」「サブエージェントで確認して」といったプロンプト：過剰な検証を招くだけです。検証はハーネス側のゲートと、最後に1回だけ行うレビューに任せます。
- 「IMPORTANT」の強調、「think hard」の指示：守られない指示は hook に移し、思考の深さは effort 設定で調整します。

## 見直し方

各部品は「モデルが単独ではできないこと」という前提を表しています。新しいモデルが出たら、1つずつ外して結果を比べてください（まとめて外すと、何が効いていたのか分からなくなります）。
外してよい候補は `unattended-prompt.md` の早期停止対策、spec-reviewer、サブエージェントの上限です。`check.sh` と `integrity.sh` は外さないでください。

## 参考

- Claude Code best practices：https://code.claude.com/docs/en/best-practices
- /goal：https://code.claude.com/docs/en/goal
- Prompting Claude Opus 5.5（早期停止、時間予算、effort）：https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5
- Prompting Claude Opus 5（検証の指示を削る、委任の制御）：https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- Harness design for long-running application development（Anthropic, 2026-03）：https://www.anthropic.com/engineering/harness-design-long-running-apps
- Effective harnesses for long-running agents（Anthropic, 2025-11）：https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Harness engineering（OpenAI, 2026-02）：https://openai.com/index/harness-engineering/
- Redesigning source control at Anthropic（2026-10）：https://www.anthropic.com/engineering/redesigning-source-control
