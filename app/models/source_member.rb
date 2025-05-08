class SourceMember < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'members'

  belongs_to :user, class_name: 'SourceUser', foreign_key: 'user_id'
  belongs_to :project, foreign_key: 'project_id', class_name: 'SourceProject'
  belongs_to :principal, polymorphic: true

  has_many :member_roles, foreign_key: 'member_id', class_name: 'SourceMemberRole'
  has_many :roles, through: :member_roles

  # グループメンバーを取得するスコープ
  scope :group_members, -> { joins(:user).where(users: { type: 'Group' }) }
end