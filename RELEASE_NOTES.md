# DayTrace 1.0

公開者: nisesimadao

DayTrace 1.0 は、iPhone 向け位置情報日記アプリ DayTrace の最初の安定版です。
位置情報から一日の文脈を組み立てつつ、Journal 本文はユーザーが記録する設計です。

含まれる機能は、自動位置タイムライン、記録診断、Today の修正 UI、履歴の閲覧と編集、Journal と Moment Notes、振り返り通知、プライバシー設定、書き出し、On This Day、小 / 中サイズのホーム画面ウィジェットです。

## IPA

GitHub Release には **未署名 IPA** と SHA-256 checksum を添付しています。
通常の iPhone へインストールする場合は、サイドロード用ツールなどを使い、自分の Apple ID / Apple Developer の署名へ置き換えてください。

このリポジトリには Apple の配布証明書や provisioning profile を含めないため、直接インストールできる署名済みビルドは生成しません。

## 主な変更

- README、設計文書、Release Notes、GitHub Release 本文を日本語化しました。
- History カレンダーの年月縦スワイプと日付タップに対する遷移管理を明示化し、操作の取りこぼしを減らしました。
- 月送りを月初基準に固定し、月末日から移動した場合の表示ずれと月ごとの高さ変化を抑えました。
- アプリアイコン、アプリ内ワードマーク、README ヘッダーを「紙と道」を基調にしたデザインへ変更しました。
- Route evidence が移動を裏付ける場合、移動時間は前の Stay の departure と次の Stay の arrival から計算するようにしました。最初の GPS sample が遅れても、表示上の移動時間を必要以上に短くしません。
- 現在地までの移動を連続したタイムラインとして表示し、レールの高さ、行間、選択状態、角丸、画面余白を整理しました。
- Today と History の情報階層を Journal 中心に整理し、学習済み Places map は History の補助画面へ移しました。
- iOS 26 では操作部品と navigation に標準の Liquid Glass を使い、iOS 18–25 では system material へフォールバックします。Reduce Motion にも対応します。
- Dynamic Island や notch と重ならないよう、status area のブランド表示を削除しました。
- History カレンダーは、前後ボタンに加えて縦スワイプでも月を移動できるようになりました。
- Debug build の Settings に、個人データへ触れず 7 日分の決定的な demo data を追加 / 削除する機能を追加しました。
- signing entitlement がない Debug build では Journaling Suggestions を表示せず、対応する Release build では利用可能なままにしました。
- 未解決の Stay 名に Apple Maps の近隣 POI 候補を提示するようにしました。候補はユーザーが確認して保存するまで、学習済み Place として扱いません。
