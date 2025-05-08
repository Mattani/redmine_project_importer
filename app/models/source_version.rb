class SourceVersion < ActiveRecord::Base
  self.table_name = 'versions'

  # 関連付け（必要に応じて追加）
  belongs_to :project, class_name: 'SourceProject', foreign_key: 'project_id'

  # バリデーション（必要に応じて追加）
  validates :name, presence: true
end