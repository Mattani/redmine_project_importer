module RedmineProjectImporter
  class JournalImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end
      
      def import_journals(context_mgr)
        target_project = context_mgr.target_project
        issue_id_map = context_mgr.issue_id_map
        members_mapping = context_mgr.mappings[:members_mapping]

        logger.info "  Importing journals for issues in project: #{target_project.name}"
        source_journals = fetch_source_journals(issue_id_map)

        # ジャーナルをターゲット Issue ID ごとにグループ化
        grouped_journals = source_journals.group_by { |journal| issue_id_map[journal.journalized_id] }

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          grouped_journals.each do |target_issue_id, journals|
            next unless target_issue_id

            # ターゲット Issue を取得して subject を取得
            target_issue = Issue.find_by(id: target_issue_id)
            target_issue_subject = target_issue&.subject || "Unknown Subject"

            logger.info "    Target issue ##{target_issue_id}: #{target_issue_subject}"

            # ジャーナルを `created_on` の昇順でソート
            sorted_journals = journals.sort_by(&:created_on)

            sorted_journals.each_with_index do |source_journal, index|
              next if source_journal.notes.blank?

              user_id = members_mapping[source_journal.user_id]&.dig(:target_user_id) || User.anonymous.id

              # チケット内のジャーナルの通番をインデックスから計算
              journal_count = index + 1

              # 最初の1行目だけを取得し、続きがある場合は "..." を付ける
              truncated_notes = source_journal.notes.lines.first.chomp
              truncated_notes += "..." if source_journal.notes.lines.size > 1

              logger.info "      note-##{journal_count}: #{truncated_notes}"
              logger.debug "Journal id: #{source_journal.id} journalized_id: #{source_journal.journalized_id} notes: #{truncated_notes}"

              begin
                Journal.create!(
                  journalized_id: target_issue_id,
                  journalized_type: 'Issue',
                  user_id: user_id,
                  notes: source_journal.notes,
                  created_on: source_journal.created_on
                )
                logger.debug "    Journal ##{source_journal.id} is copied successfully to the target issue ##{target_issue_id} as note-#{journal_count}"
              rescue ActiveRecord::RecordInvalid => e
                context_mgr.add_warning({ message: "    Failed to copy journal ##{source_journal.id}: Validation error - #{e.message}" })
              rescue StandardError => e
                context_mgr.add_warning({ message: "    Failed to copy journal ##{source_journal.id}: Unexpected error - #{e.message}" })
              end
            end
          end
        end

        logger.info "  Journal import completed."
      end

      private

      def fetch_source_journals(issue_id_map)
        source_issue_ids = issue_id_map.keys
        return [] if source_issue_ids.empty?

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          SourceJournal.where(journalized_id: source_issue_ids, journalized_type: 'Issue')
                       .where.not(notes: [nil, '']).to_a
        end
      end
    end
  end
end
