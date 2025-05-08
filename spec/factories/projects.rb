# サンプルプロジェクトデータをfactoryブロックの外に移動
SAMPLE_PROJECTS = [
  {
    name: "開発プロジェクト",
    identifier: "development_project",
    description: "新しいアプリケーションの開発を行うプロジェクトです。",
    group: [:development] # 開発グループに関連付け
  },
  {
    name: "新規事業立ち上げ",
    identifier: "new_business_launch",
    description: "新しいビジネスモデルの構築と立ち上げを目的としたプロジェクトです。",
    group: [:sales] # 営業グループに関連付け
  },
  {
    name: "社内改善タスク",
    identifier: "internal_improvement",
    description: "社内業務の効率化とプロセス改善を行うためのタスク群です。",
    group: [:kaizen] # 改善グループに関連付け
  },
  {
    name: "次世代システム構築",
    identifier: "next_gen_system",
    description: "次世代基盤となるシステムを構築する大型プロジェクトです。",
    group: [:development, :sales] # 開発、営業グループに関連付け
  },
  {
    name: "テスト自動化",
    identifier: "test_automation",
    description: "回帰テストの自動化により開発効率の向上を目指します。",
    group: [:development] # 開発グループに関連付け
  },
  {
    name: "マーケティング戦略",
    identifier: "marketing_strategy",
    description: "市場調査と分析をもとにしたマーケティング施策の企画実行。",
    group: [:sales] # 営業グループに関連付け
  },
  {
    name: "顧客満足度向上",
    identifier: "customer_satisfaction",
    description: "カスタマーサポートやUI改善を通じて顧客満足度を高めます。",
    group: [:sales,:kaizen] # 営業、改善グループに関連付け
  },
  {
    name: "クラウド移行計画",
    identifier: "cloud_migration",
    description: "オンプレミス環境からクラウドへのシステム移行を進めるプロジェクトです。",
    group: [:development] # 開発グループに関連付け
  },
  {
    name: "品質管理改善",
    identifier: "quality_improvement",
    description: "製品品質の標準化とチェックプロセスの最適化を目指します。",
    group: [:kaizen] #  改善グループに関連付け
  },
  {
    name: "リモートワーク最適化",
    identifier: "remote_work_optimize",
    description: "リモートワーク環境の改善と支援策の導入を行います。",
    group: [:kaizen] # 改善グループに関連付け
  }
]

FactoryBot.define do
  factory :project do
    # サンプルプロジェクトデータを順番に使用
    transient do
      project_index { 0 } # デフォルトで最初のプロジェクトを使用
    end

    # 指定されたインデックスのデータをプロジェクト属性に割り当て
    name        { SAMPLE_PROJECTS[project_index][:name] }
    identifier  { SAMPLE_PROJECTS[project_index][:identifier] }
    description { SAMPLE_PROJECTS[project_index][:description] }

    created_on { Time.now }
    updated_on { Time.now }

    # 複数のプロジェクトを作成するためのトレイト
    trait :with_multiple do
      transient do
        count { 5 } # デフォルトで5つのプロジェクトを作成
      end

      after(:build) do |project, evaluator|
        evaluator.count.times do |index|
          project_data = SAMPLE_PROJECTS[index % SAMPLE_PROJECTS.size]
          project.name = project_data[:name]
          project.identifier = project_data[:identifier]
          project.description = project_data[:description]
        end
      end
    end
  end
end
