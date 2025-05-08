FactoryBot.define do
  factory :version do
    sequence(:name) { |n| "Version #{n}" } # ユニークなバージョン名
    description { "これはサンプルのバージョンです。" }
    status { "open" } # デフォルトのステータス
    sharing { "none" } # デフォルトの共有設定
    effective_date { Date.today + 30.days } # デフォルトの有効期限
    project # プロジェクトとの関連付け
  end
end