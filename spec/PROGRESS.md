# Progress log

Append-only. One line per entry: date, task id, what was decided or what failed and why.
- 2026-11-15 README動作確認: 未信頼ワークスペースでは claude -p が permissions.allow を無視すると判明し、セットアップ手順に信頼ダイアログの承認を追記。/goal+-p の行は CLI の OAuth 期限切れで未確認。
- 2026-11-15 /goal+-p の行を --no-pr で確認（T1 を 6 ターン・約 $0.34 で完了、最終ゲート通過）。-p 実行では /usage が使えないため、README の費用確認を run ログの total_cost_usd に変更。
- 2026-11-15 warikan セッションからの報告で改善: /spec に CI の依存インストール確認と base の push を追記し、run-unattended.sh の preflight に「origin より先行なら停止」「setup.sh なしでパッケージマネージャ系チェックなら警告」を追加。先行は integrity の誤検出で実行が無駄になるため警告でなく停止にした。
- 2026-11-15 ユーザー判断でテンプレートの ask から git push を削除（push まではエージェントが進めてよい方針）。force push の deny と gh pr merge の ask は残した。
- 2026-11-15 人の作業を「/spec の質問に答える」だけにする方針: /spec が checks.conf・setup.sh・CI ランタイムを用意し、確認待ちなしで commit・push（リモートなしなら gh で private リポジトリ作成）・run-unattended のバックグラウンド起動まで行う。セッション終了後も続くよう nohup で起動。install.sh は未作成・非 git のディレクトリなら git init する。
- 2026-11-15 install.sh が spec/PROGRESS.md（このリポジトリ自身の開発ログ）をそのままコピーし、jikan の PR に warikan などの記録が混入していた。インストール先にはヘッダーだけの空ログを作るよう変更。
- 2026-11-15 jikan セッションの依頼でテスト弱体化の検知を追加（integrity.sh＋harness/test-guard.conf、jikan の複製で a〜d と未追跡ファイルの skip を拒否、移動・書き換え・新規テストは通過を確認）。マーカーは追加数が削除数を上回ったら失敗（移動は通す）。初回ビルドで新規コードに noqa 等を書くのも失敗になるが、人の許可（harness-change）で逃がせるので厳しい側に倒した。spec-reviewer には git diff を読むため Bash を追加（読み取り専用と指示）。
- 2026-11-16 mijika で /spec セッションが終われなくなった: 無人ビルド起動後、main の Stop hook がまだ存在しないコードのチェック失敗で差し戻し続けた。base ブランチで未完了タスクがある間は Stop hook を integrity だけにした（ビルドブランチと全タスク完了後の main は従来どおり全チェック）。
- 2026-11-16 Stop hook を無人実行（HARNESS_RUN=1）と agent/* ブランチだけに限定。main や人のブランチでは赤いチェックが正常なことが多く（/spec 直後など）、ゲートが邪魔になっていた。前回入れた「main で未完了タスクがある間は integrity だけ」の例外は不要になったので削除。HARNESS_GATE=on/off で上書き可。integrity と CI はブランチに関係なく従来どおり。
- 2026-11-16 claude -p の途中経過が追いにくいので harness/watch.sh を追加（stream-json を発言・コマンド・編集・サブエージェント・失敗・結果の 1 行表示に整形し、worktree のタスク進捗とコミットも出す）。result 行はキー順が一定でないので行頭一致でなく部分一致で検出。
- 2026-11-16 watch.sh で mijika のログを見て判明: goal.md の「各タスクのテストを実装前に失敗させる」が、前タスクで実装済みの T005 では満たせず、エージェントが約 15 ターン空回りした（ごまかしは拒否していた）。前タスクで実装済みなら PROGRESS.md に記録すればよい、コードを壊して失敗を作らない、を goal.md と unattended-prompt.md に追記。
