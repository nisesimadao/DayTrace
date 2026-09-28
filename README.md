<p align="center">
  <img src="assets/daytrace-header.png" alt="DayTrace — 日記が主役。位置情報は文脈。" width="100%">
</p>

# DayTrace

DayTrace は、iPhone の位置情報を低消費電力で記録し、「今日なにがあったか」を振り返るための位置情報日記アプリです。
日記本文はユーザーが書き、位置情報は記憶をたどるための文脈として扱います。

GPS ログそのものを閲覧することを主目的にはしていません。
生の観測データ、自動推定、ユーザーが確認・修正した内容を別々に保存し、再解析によって手動修正が上書きされない構成にしています。

## プロダクト原則

- **日記を中心にする**：位置情報は日記を補う文脈として扱います。
- **ユーザーの修正を優先する**：場所名や時刻の手動修正は、その後のタイムライン再生成でも保持します。
- **不明な区間を明示する**：証拠が足りない区間は `Gap` とし、推定経路を作りません。
- **不確実性を隠さない**：時刻や場所の確度が低い場合は、その状態を UI に反映します。
- **ローカルファースト**：個人 beta は DayTrace アカウントやバックエンドなしで動作します。
- **低消費電力を既定にする**：Visit monitoring と significant-change monitoring を受動記録の中心にし、詳細ルート記録は任意です。
- **記録時のローカル日付を使う**：現在の端末タイムゾーンではなく、各記録に保存したタイムゾーンから日付を投影します。

## 現在の個人 beta

- **Today / History** を中心にした SwiftUI UI。
- SwiftData によるローカル永続化。
- Core Location の Visits と significant-change monitoring を使った位置証拠記録。
- 任意の詳細ルート記録。
- `Stay / Move / Gap` の正規タイムライン。
- 証拠が足りない区間の明示的な `Gap` 生成。
- ユーザー確認後の場所学習と、GPS ずれで近接する同名 Place の再利用。
- 未解決の滞在名に対する Apple Maps の近隣 POI 候補。
- 滞在の場所名、到着時刻、出発時刻の編集。
- 取り消し可能な Stay suppression。
- 手動修正を再解析から守る `UserAssertion` レイヤー。
- タイムライン選択と同期する日別マップ。
- 記録日ごとに最大 1 件の Journal。
- 時刻付きの **Moment Notes**。
- Apple Journaling Suggestions picker との連携。
- 履歴カレンダー、最近の日付、学習済み場所マップ、過去日の詳細表示。
- Timeline / Journal / Moment Notes を対象にした履歴検索。
- ローカル JSON backup、Markdown archive、明示操作による GPX export。
- 生の位置証拠に対する保持期間 policy。
- Face ID / Touch ID / device passcode を使う任意の app lock。
- app lock の有無にかかわらず働く App Switcher privacy cover。
- Journal と Moment Notes を保持したまま位置履歴だけを削除する **位置履歴リセット**。
- reset 前の遅延 Core Location callback を拒否する cutoff。
- When In Use から background location permission へ移行するための retry flow。
- 場所名を含めない夜の振り返り通知。
- timezone / DST、遅延 Visit、Place 再利用、Journal 一意性、reset cutoff などの regression tests。
- iOS 26 では操作部品に Liquid Glass を使い、iOS 18–25 では非 glass UI へフォールバック。

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
- 最小対応 OS：iOS 18

## アーキテクチャ

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

詳細なデータモデルと不変条件は [`ARCHITECTURE.md`](ARCHITECTURE.md)、UI と編集の原則は [`DESIGN.md`](DESIGN.md) にまとめています。

## ビルド

Xcode 26 以降で `Daytrace.xcodeproj` を開き、`Daytrace` scheme を選択します。
実機ビルドで Journaling Suggestions を使う場合は、使用する signing team で対応 capability が必要です。

GitHub Actions では `macos-26` 上で unsigned iOS Simulator build と XCTest を実行します。

## 開発状況

個人 beta として、位置記録、タイムライン生成、日記、履歴、通知、書き出し、プライバシー機能を実装しています。
今後の検証項目には、実機での battery / accuracy / notification behavior、過去日の安全な timeline regeneration、境界編集、学習済み Place の管理、adaptive な detailed route recording、写真・On This Day・任意同期などがあります。
