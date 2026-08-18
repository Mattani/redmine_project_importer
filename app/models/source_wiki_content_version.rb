class SourceWikiContentVersion < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'wiki_content_versions'
end
