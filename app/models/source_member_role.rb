class SourceMemberRole < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'member_roles'

  belongs_to :member, class_name: 'SourceMember', foreign_key: 'member_id'
  belongs_to :role
end