RSpec.describe 'ImportSource Database', type: :model do
  before do
    # import_source のDBに接続
    RedmineProjectImporter::DatabaseConnector.with_connection(
      env: Rails.env,
      config_path: File.expand_path('../../config/database.yml', __dir__),
      namespace: :import_source
    ) do
      @source_issues = SourceIssue.all
    end
  end

  it 'import_source の issues テーブルにデータが存在することを確認する' do
    expect(@source_issues.count).to be > 0
  end

  it 'import_source の issues に特定のプロジェクトIDのデータがあることを確認する' do
    project_id = 5  # 確認したいプロジェクトID
    expect(@source_issues.where(project_id: project_id).count).to be > 0
  end
end
