class SourceIssuesStatus < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'issue_statuses'
  # connects_to database: { reading: :import_source, writing: :import_source }

  # 必要に応じて関連付けを追加
  # 例: has_many :workflows, foreign_key: 'old_status_id', class_name: 'SourceWorkflow'
end