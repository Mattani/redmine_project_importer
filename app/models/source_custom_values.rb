class SourceCustomValues < ActiveRecord::Base
  self.table_name = 'custom_values'

  belongs_to :custom_field, class_name: 'SourceCustomField', foreign_key: 'custom_field_id'
  belongs_to :issue, class_name: 'SourceIssue', foreign_key: 'customized_id'

  scope :for_issues, -> { where(customized_type: 'Issue') }

  # カスタムフィールド値を取得するヘルパーメソッド
  def self.fetch_for_issue(issue_id)
    for_issues.where(customized_id: issue_id).pluck(:custom_field_id, :value).to_h
  end
end
