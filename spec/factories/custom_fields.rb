FactoryBot.define do
  factory :custom_field do
    sequence(:name) { |n| "Custom Field #{n}" }
    field_format { "string" } # デフォルトはテキスト型
    possible_values { nil } # デフォルトでは選択肢なし

    trait :text do
      field_format { "string" }
    end

    trait :list do
      field_format { "list" }
      possible_values { ["Option 1", "Option 2", "Option 3"] }
    end

    trait :version do
      field_format { "version" }
    end

    trait :file do
      field_format { "file" }
    end

    trait :user do
      field_format { "user" }
    end

    trait :link do
      field_format { "link" }
    end

    trait :float do
      field_format { "float" }
    end

    trait :integer do
      field_format { "int" }
    end

    trait :date do
      field_format { "date" }
    end

    trait :boolean do
      field_format { "bool" }
    end

    trait :long_text do
      field_format { "text" }
    end

    # 追加: STI 対応のサブファクトリ
    factory :issue_custom_field, class: 'IssueCustomField'
    factory :project_custom_field, class: 'ProjectCustomField'
  end
end