class SourceIssue < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'issues'
end