class SourceWorkflow < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'workflows'
  # connects_to database: { reading: :import_source, writing: :import_source }

  # 必要に応じて関連付けを追加
  # 例: belongs_to :tracker, foreign_key: 'tracker_id', class_name: 'SourceTracker'
  # 例: belongs_to :old_status, foreign_key: 'old_status_id', class_name: 'SourceStatus'
end