FactoryBot.define do
  factory :group do
    sequence(:name) { |n| "Group #{n}" } # ユニークなグループ名を生成
  end
end