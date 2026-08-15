<p align="center">
  <img src="assets/daytrace-header.png" alt="DayTrace — 日記が主役。位置情報は文脈。" width="100%">
</p>

# DayTrace

DayTrace は、iPhone の位置情報を低消費電力で記録し、あとから「今日なにがあったか」を思い出すための位置情報ベースの日記アプリです。日記そのものは人が書き、位置情報は記憶を引き出すための文脈として扱います。

このアプリは GPS ログ閲覧アプリではありません。生の観測データ、自動推定、ユーザーが確認・修正した記憶を分けて保存することで、あとから再解析しても手動修正が勝手に上書きされない設計にしています。

## プロダクト原則

- **日記が主役。** 位置情報は目的地ではなく、文脈です。
- **ユーザーの修正を優先する。** 場所名や時刻の手動修正は、以後のタイムライン再生成でも残ります。
- **不明は不明として扱う。** 証拠が足りない区間は `Gap` になり、移動経路を捏造しません。
- **偽の精度を出さない。** 不確かな時刻や場所は、不確かなものとして表示します。
- **ローカルファースト。** 個人 beta は DayTrace アカウントやバックエンドなしで動作します。
- **標準は低消費電力。** 滞在検知と大幅位置変更を受動記録の軸にし、詳細ルート記録は任意です。
- **記録時のローカル日付を尊重する。** 端末の現在タイムゾーンではなく、各記録に保存されたタイムゾーンで日付へ投影します。

## 現在の個人 beta

- **今日 / 履歴** を中心にした SwiftUI アプリ
- SwiftData 永続化
- Core Location の Visits と significant-change monitoring を標準にした位置証拠レコーダー
- 任意の詳細ルート記録
- `Stay / Move / Gap` の正規タイムライン
- 移動を捏造しない明示的な Gap 生成
- ユーザー確認後の場所学習と、GPS ずれによる同名近接 Place の再利用
- 未解決の滞在名に対する Apple Maps 近隣 POI 候補の自動補完
- 滞在編集画面での場所名、到着時刻、出発時刻の修正
- 取り消し可能な滞在の非表示
- 手動修正を再解析から守る `UserAssertion` レイヤー
- タイムライン選択と双方向に同期する日別マップ
- 空の世界地図を出さない、日記優先の Today 空状態
- 記録日ごとに 1 件の Journal
- 時刻付きの **Moment Notes**
- Apple Journaling Suggestions ピッカー連携
- 履歴カレンダー、最近の日付、学習済み場所マップ、過去日の詳細表示
- タイムライン、Journal、Moment Notes を横断する履歴検索
- ローカル JSON バックアップ書き出し
- 人が読める Markdown アーカイブ書き出し
- 明示操作による生位置情報 GPX 書き出し
- 生証拠データの保持期間ポリシー
- 任意の Face ID / Touch ID / デバイスパスコードによるアプリロック
- アプリロック無効時も働く App Switcher プライバシーカバー
- Journal と Moment Notes を残しつつ位置履歴だけ消す、永続的な **位置履歴リセット**
- リセット前の遅延 Core Location コールバックが削除済み履歴を復活させない cutoff
- When In Use 権限からバックグラウンド記録へ上げるためのアプリ内リトライ導線
- 場所名を含まない、プライバシー安全な夜の振り返り通知
- タイムゾーン / DST、遅延 Visit、Place 再利用、Journal 一意性、リセット cutoff などの回帰テスト
- iOS 26 では操作部品に Liquid Glass を使用し、iOS 18-25 では非 glass フォールバック

## 技術スタック

- Swift 6
- SwiftUI
- SwiftData
- Core Location
- MapKit
- UserNotifications
- LocalAuthentication
- Uniform Type Identifiers / FileDocument export
- Journaling Suggestions
- 最小対応 OS: iOS 18

## アーキテクチャ

中核フローは次の通りです。

```text
センサー証拠
  ├─ LocationEvidence
  └─ VisitEvidence
        ↓
TimelineEngine
        ↓
TimelineEpisode
  ├─ Stay
  ├─ Move
  └─ Gap
        ↓
UserAssertion（常に優先）
        ↓
CalendarDay / DayInterval 投影
        ↓
Today / History / Search / Journal
```

現在のプロダクトルールは [`ARCHITECTURE.md`](ARCHITECTURE.md) と [`DESIGN.md`](DESIGN.md) にまとめています。

## ビルド

Xcode 26 以降で `Daytrace.xcodeproj` を開き、`Daytrace` scheme を選択します。実機ビルドで Journaling Suggestions を使う場合は、利用する署名チームで capability が有効である必要があります。

GitHub Actions では `macos-26` 上で、未署名の iOS Simulator ビルドと XCTest を実行します。

## 状態

DayTrace は UI だけのプロトタイプではなく、個人 beta として実用できる段階です。次に価値が高い作業は、実機でのバッテリー / 精度 / 通知挙動の確認、過去日の安全なタイムライン再生成、正直な境界編集、学習済み場所の管理強化、適応的な詳細ルート記録、写真 / On This Day / 任意同期などの振り返り機能です。
