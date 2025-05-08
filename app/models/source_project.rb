class SourceProject < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'projects'
  # connects_to database: { reading: :import_source, writing: :import_source }

  has_many :members, foreign_key: 'project_id', class_name: 'SourceMember'
end