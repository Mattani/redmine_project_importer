# サンプルトラッカーデータをfactoryブロックの外に移動
SAMPLE_TRACKERS = [
  "タスク",
  "要望",
  "改善",
  "バックログ",
  "調査",
  "ドキュメント",
  "UI変更",
  "パフォーマンス",
  "セキュリティ",
  "テスト"
]

FactoryBot.define do
  factory :tracker do
    # トラッカーのインデックスを指定
    transient do
      tracker_index { 0 } # デフォルトで最初のトラッカーを使用
    end

    # SAMPLE_TRACKERS から順番にデータを取得
    name { SAMPLE_TRACKERS[tracker_index] }
    sequence(:position) { |n| n } # ユニークな表示順
    default_status_id { 1 }       # デフォルトのステータスID
  end
end