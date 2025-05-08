FactoryBot.define do
  factory :issue do
    sequence(:subject) { |n| "Sample Issue #{n}" } # ユニークなチケットタイトル
    description { "これはサンプルのチケットです。" }
    created_on { Time.now }
    updated_on { Time.now }
    start_date { Date.today }
    due_date { Date.today + 7.days }
    status_id { 1 } # デフォルトのステータスID
    priority_id { 2 } # デフォルトの優先度ID
    tracker # トラッカーとの関連付け
    project # プロジェクトとの関連付け
    author_id { 1 } # 作成者のID（適宜変更）

    # トレイト: チケットに関連する子チケットを作成
    trait :with_children do
      transient do
        children_count { 2 } # デフォルトで2つの子チケットを作成
      end

      after(:create) do |issue, evaluator|
        create_list(:issue, evaluator.children_count, parent_id: issue.id, project: issue.project)
      end
    end
  end
end