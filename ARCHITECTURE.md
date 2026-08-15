# DayTrace アーキテクチャ

## データレイヤー

```text
Core Location / journaling context / 直接入力
                    |
                    v
              センサー証拠
                    |
                    v
              TimelineEngine
                    |
                    v
          Stay / Move / Gap episodes
                    |
             + UserAssertion
                    |
                    v
             正規タイムライン
                    |
                    v
        CalendarDay / DayInterval 投影
                    |
                    v
 Today / History / Search / Journal / Export
```

## 真実の優先順位

1. ユーザーの assertion
2. 高信頼の推定 episode
3. 生のセンサー証拠
4. 不明 (`Gap`)

生の証拠は証拠であり、正規の真実ではありません。別に永続化することで、将来推定アルゴリズムを改善しても、ユーザーが明示的に直した内容を再定義しないようにします。

## 時刻モデル

- 絶対時刻の `Date` を保存します。
- 各 evidence / memory record に紐づく timezone identifier を保存します。
- `CalendarDay` は `year/month/day` だけを持つ、タイムゾーン非依存の市民日付キーです。
- record は、その record に保存された timezone で絶対 `Date` を解釈し、year/month/day を取り出すことで `CalendarDay` になります。
- これにより、あとから端末のタイムゾーンが変わっても、その出来事を経験したローカル日付で History をまとめられます。
- 実際の start/end `Date` range が必要な場合は、timezone 固有の `DayInterval` 投影を使います。
- 日跨ぎの滞在は 1 つの episode のまま保持し、日別投影のときだけ切り出します。
- History、検索グルーピング、Journal 一意性、Markdown export、過去日詳細は、この記録時ローカル日付の意味論を使います。
- 過去の市民日に Journal を作る場合、記録済み Timeline の timezone context を優先します。Timeline context がない場合は、その日に記録された Moment Note の timezone を使い、それもなければ呼び出し元 / 端末の timezone にフォールバックします。

## 永続化

SwiftData models:

- `LocationEvidence`
- `VisitEvidence`
- `PlaceRecord`
- `TimelineEpisode`
- `UserAssertion`
- `JournalEntry`
- `MomentNote`

現在の beta はローカル専用です。将来 `ModelContainer` に CloudKit 設定を追加できますが、起動、記録、振り返り、日記作成に sync が必須になってはいけません。

## 位置レコーダー

現在の動作:

- durable な滞在シグナルとして Visit monitoring を使う
- 受動的な移動シグナルとして significant-change monitoring を使う
- アプリ起動時に foreground の one-shot 位置 snapshot を取る
- **詳細ルート** が明示的に有効な場合だけ continuous standard location updates を使う
- 生証拠データの保持期間ポリシーを持つ。Visit の保持判定は、遅延 callback の到着時刻ではなく、Visit 自体の arrival/departure 時刻に基づきます
- When In Use 権限からバックグラウンド記録へ上げるため、Settings へ逃がす前に 1 度だけアプリ内アップグレードを試みたことを記憶します

詳細 update は将来的に adaptive にするべきです。出発 / 到着の可能性が高い前後で起き、役に立つ間だけ sample し、その後はまた sleep します。高精度 GPS の常時利用は標準にしません。

### 位置履歴リセット cutoff

位置履歴リセットは cutoff timestamp を保存します。本番の Core Location 取り込み経路と回帰テストは、同じ cutoff policy を共有します。

- cutoff より古い location sample は拒否する
- cutoff 以降の sample は通常通り受け入れる
- cutoff 以前に終わった Visit は捨てる
- cutoff を跨ぐ Visit は arrival を cutoff に clamp して受け入れる
- cutoff 前に始まった ongoing Visit も同様に cutoff から再開できる

これにより、遅延した Core Location callback が、ユーザーが明示的に消した履歴を勝手に作り直すことを防ぎます。

## タイムライン推定

`TimelineEngine` は現在、直近 window を再構築し、主に 3 種類の episode を管理します。

- `Stay` — Visit evidence に裏付けられ、必要に応じて学習済み Place に解決される滞在
- `Move` — 保持された location sample を持つ移動区間
- `Gap` — 十分な証拠がない移行区間。経路は捏造しません

Place 解決では、非常に精度の低い Visit を拒否します。また GPS ずれで重複した学習済み Place が増えないよう、ユーザー確認済みの近い同名 Place を再利用できます。

### 再処理の不変条件

`TimelineEngine` は、active な `UserAssertion` に守られた episode を、ユーザー修正を失う形で削除 / 上書きしてはいけません。

現在の rebuild window は意図的に直近に限定しています。そのため過去日の Timeline detail は読み取り専用です。任意日の transition regeneration がないまま古い Stay を編集すると、古い `Move` / `Gap` geometry が stale になる可能性があります。過去編集は、選択日 / 範囲を安全に rebuild できるようになってから解放します。

## 編集モデル

通常の編集は正規の記憶に作用し、生の証拠には作用しません。

- 名前変更、arrival、departure の修正は `UserAssertion` を作成 / 更新します。
- Stay suppression は取り消し可能で、assertion として表現されます。
- 確認により再利用可能な Place を学習できます。
- DayTrace は Apple Maps の近隣 POI lookup を使って未解決 Stay 名を補完でき、ユーザーは Stay editor から場所 / 住所候補を明示的に探せます。どちらも候補であり、ユーザーが保存 / 確認するまでは学習済み Place として扱いません。
- overlap する Stay 編集は構造的に拒否します。
- 生証拠は、ユーザーが直した Timeline とは別に保持します。

直接の境界 drag はまだ延期しています。現在の Timeline row height は経過時間に比例していないため、drag gesture が偽の pixel-to-time scale を示してはいけません。

## Journaling

記録済み calendar day には最大 1 つの `JournalEntry` だけがあります。保存時に accidental duplicate を調停し、ユーザーが書いた文章は Timeline 再処理から独立して保持します。

`MomentNote` は、今その場で残す短い記憶の手がかりです。記録時のローカル時刻で表示され、検索 / export に含まれ、日記本文へ自動マージされることはありません。

### Journaling Suggestions

アプリが suggestion detail を受け取るのは、ユーザーが system picker で明示的に suggestion を選んだ後だけです。picker は記憶の手がかりであり、バックグラウンドデータ源ではありません。連携は `canImport(JournalingSuggestions)` で gate し、この module がない環境でも core journal は使えるようにします。

## 夜の振り返り通知

振り返り通知はローカル `UserNotifications` です。push backend はありません。

- Settings から opt-in し、通知権限もそこで要求します。
- 標準の振り返り時刻は 21:00 で、変更できます。
- 通知 title/body には訪問した場所名や生座標を含めません。
- 個別の Journal 日を skip / cancel できるよう、1 つの repeating request ではなく、日別 one-shot request を rolling に schedule します。
- 既に Journal がある日は refresh 時に除外します。
- Journal の保存 / 更新時は、その市民日の pending reminder を即座に cancel します。
- Journal を削除すると、管理対象 reminder schedule を refresh します。
- DayTrace の振り返り通知を tap すると、アプリが History 選択中に background へ行っていた場合も Today へ route します。
- feature refresh / disable 時に削除するのは、DayTrace 管理の reminder identifier だけです。

## History と振り返り

History は 1 つの app tab のままですが、浅い mode として **日付** と **マップ** を持ちます。

日付 mode から recorded day へ入る経路は 3 つです。

- Calendar day
- Recent day row
- Search result

過去日 detail は day map と Timeline presentation を再利用し、Moment Notes を表示し、Journal 編集を許可します。古い Timeline 編集は、上で説明した rebuild-window の理由によりまだ無効です。

History search は、表示される Timeline title/subtitle、Journal text、Moment Notes を検索します。結果は recorded `CalendarDay` ごとに 1 度だけ group し、result row ごとに全履歴を再 scan するのではなく UI 表示用に cap します。

### 個人 Places マップ

Map mode は **学習済み Place を思い出すための面** であり、生位置情報マップではありません。

- 表示対象の Stay episode と紐づく `PlaceRecord` identity を描画します
- 生の `LocationEvidence` は map dot として描画しません
- 未確認の近接 Stay は、座標が近いだけでは merge しません
- visible Stay を `placeID` ごとに 1 度 group し、Place ごとの visit count と most-recent visit を導きます
- most-recent date は、端末の現在 timezone で再 format せず、Stay の recorded-local `CalendarDay` として保存 / 表示します
- map pin と Place row selection は、同じ selected Place と camera focus state を共有します
- `isPrivate` Place 名は、この recall surface では sanitize します
- 選択 Place card から **最後の記録** を開けます。calendar / search History と同じ `HistoricalDayDetailView` を再利用し、別の過去日 detail 実装を持ちません

正直な city / zoom aggregation は、学習済み Places が実利用で十分増えるまで延期します。将来 aggregation を入れる場合も、基礎の Place identity を保ち、空間的に近いことだけを同一 Place の証拠として扱ってはいけません。

## 書き出し

すべての export 生成はローカルです。

- **JSON**: Timeline、Places、Journal entries、Moment Notes、UserAssertions。生 location sample は含めません。
- **Markdown**: recorded-local-date projection を使った、人が読める日別 archive。
- **GPX**: ユーザーが明示的に選ぶ、保持済みの生 `LocationEvidence` のみ。10 分を超える gap では新しい track segment を始め、証拠のない区間を連続経路として描画しません。

SwiftUI `fileExporter` / `FileDocument` が、生成したファイルを system save UI に渡します。

## プライバシー

- 任意の app lock は `LocalAuthentication` の owner authentication を使います。利用可能なら biometrics と system passcode fallback を使います。
- scene が inactive / background になるたびに app content を覆い、App Switcher snapshot で位置履歴や journal text が見えないようにします。
- 生証拠には、durable な Timeline / journal memory とは別の保持期間ポリシーがあります。
- コア利用に backend は不要です。
- **位置履歴リセット** は `LocationEvidence`、`VisitEvidence`、`TimelineEpisode`、`UserAssertion`、`PlaceRecord` を削除し、`JournalEntry` と `MomentNote` は意図的に保持します。
- reset time は cutoff として永続化します。cutoff より古い遅延 location sample は、削除済み履歴を勝手に復活させないよう破棄します。
- cutoff 前に終わった Visit は破棄します。reset を跨ぐ Visit は cutoff から再開できるため、reset 後の履歴だけが戻ります。
- review notification copy は意図的に location-free にし、lock-screen 通知で学校、自宅、店、経路が漏れないようにします。
- raw-only manual deletion はまだ出していません。生の Visit anchor だけを削除すると、直近の正規 Stay の survival / re-delivery semantics が変わる可能性があるためです。

## 回帰テスト方針

XCTest suite には、happy-path UI / domain behavior だけでなく、新しい意味論に対する focused coverage を含めています。

- timezone 変更と DST 境界を跨ぐ civil-day projection
- delayed Visit retention behavior
- 近い同名 Place の再利用と、遠い同名 Place の分離
- CalendarDay ごとに 1 Journal を守る duplicate reconciliation
- 過去日の MomentNote-only Journal timezone anchoring
- 位置履歴 reset が Journals / Moment Notes を保持し cutoff を永続化すること
- pre-cutoff delayed location sample の拒否
- reset cutoff を跨ぐ Visit の clamp

cutoff tests は、test のために private delegate internals を露出するのではなく、本番 Core Location ingestion と同じ pure policy を exercise します。

## 現在のマイルストーン

### 実装済みの個人 beta 基盤

- 受動的な位置証拠記録
- Stay / Move / Gap 推定
- ユーザーに保護された rename / retime / confirmation
- Stay naming のための Apple Maps 候補 lookup
- 取り消し可能な suppression + undo
- 現在地 freshness states
- 記録 timezone に基づく civil-day projection
- CalendarDay ごとに 1 Journal
- Place 学習と近接 duplicate 再利用
- Moment Notes
- History search
- historical day detail
- latest-record navigation 付きの個人 learned-Places map
- JSON / Markdown / GPX export
- 生証拠 retention cleanup
- app lock + App Switcher privacy cover
- delayed-callback cutoff 付きの durable location-history reset
- When In Use から background recording への recovery flow
- 日記優先の Today 空状態
- Timeline selection と map camera / pin の同期
- privacy-safe で設定可能な夜の振り返り通知
- 新しいデータ意味論に対する focused regression coverage
- CI build + iOS Simulator XCTest

### 次: beta を実機で固める

- 実機 battery / accuracy tests
- 実機 notification permission / delivery / timezone checks
- より安全な任意日 Timeline regeneration
- regeneration 後の historical Stay editing
- 正直な time interaction model に基づく direct boundary editing
- adaptive detailed-route recording
- 必要に応じた debug / support diagnostics

### その後: もっと豊かな振り返り

- photo timeline opt-in
- On This Day
- backup-health UX
- 任意 iCloud sync
- 学習済み場所管理 / merge UI の強化
