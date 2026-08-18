class SourceWikiContent < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'wiki_contents'
end
