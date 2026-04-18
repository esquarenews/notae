module Api
  module V1
    module Meetings
      class SessionsController < BaseController
        require_api_token_scopes(
          index: ApiToken::SCOPE_MEETINGS_READ,
          show: ApiToken::SCOPE_MEETINGS_READ,
          transcript: ApiToken::SCOPE_MEETINGS_READ,
          create: ApiToken::SCOPE_MEETINGS_WRITE,
          ingest_transcript: ApiToken::SCOPE_MEETINGS_WRITE,
          cancel: ApiToken::SCOPE_MEETINGS_WRITE
        )

        before_action :set_workspace!
        before_action :set_meeting_session!, only: %i[show transcript ingest_transcript cancel]

        def index
          sessions = policy_scope(MeetingSession)
                       .for_workspace(workspace)
                       .includes(:meeting_utterances)
                       .recent_first
          sessions = sessions.where(status: params[:status].to_s) if params[:status].to_s.present?

          render json: { data: Api::V1::Serializers::MeetingSessionSerializer.render_collection(sessions.limit(100)) }, status: :ok
        end

        def show
          render json: { data: Api::V1::Serializers::MeetingSessionSerializer.render(@meeting_session) }, status: :ok
        end

        def create
          session_record = MeetingSession.new(
            workspace: workspace,
            title: create_params[:title],
            capture_mode: "browser_extension",
            provider: "google_meet",
            created_by: current_user,
            updated_by: current_user,
            status: "scheduled"
          )
          authorize session_record, :create?

          session_record = ::Meetings::SessionLifecycleService.new(workspace: workspace, actor: current_user).create_session!(
            title: create_params[:title],
            capture_mode: "browser_extension",
            provider: "google_meet",
            kalendarium_event: matched_event,
            join_url: create_params[:join_url],
            consent_warning_acknowledged: true,
            force_new: ActiveModel::Type::Boolean.new.cast(create_params[:force_new])
          )

          session_record.update!(
            status: "recording",
            started_at: session_record.started_at || Time.current,
            ended_at: nil,
            error_message: nil,
            updated_by: current_user,
            metadata_json: session_record.metadata_json.to_h.merge(
              "transcript_source" => "google_meet_extension",
              "capture_origin" => "chrome_extension"
            )
          )

          render json: { data: Api::V1::Serializers::MeetingSessionSerializer.render(session_record) }, status: :created
        rescue ActiveRecord::RecordInvalid => error
          render_validation_errors(error.record)
        rescue ArgumentError => error
          render_error(code: "bad_request", message: error.message, status: :unprocessable_entity)
        end

        def transcript
          render json: {
            data: {
              id: @meeting_session.id,
              transcript_text: @meeting_session.transcript_text.to_s,
              utterances: @meeting_session.meeting_utterances.ordered.map do |utterance|
                {
                  position: utterance.position,
                  started_ms: utterance.started_ms,
                  ended_ms: utterance.ended_ms,
                  speaker_key: utterance.speaker_key,
                  speaker_name: utterance.speaker_name,
                  text: utterance.text,
                  confidence: utterance.confidence
                }
              end
            }
          }, status: :ok
        end

        def ingest_transcript
          authorize @meeting_session, :update?

          utterances = Array(ingest_transcript_params[:utterances]).map do |utterance|
            utterance.respond_to?(:to_unsafe_h) ? utterance.to_unsafe_h : utterance.to_h
          end
          metadata = ingest_transcript_params[:metadata]
          metadata = metadata.respond_to?(:to_unsafe_h) ? metadata.to_unsafe_h : metadata.to_h

          ::Meetings::TranscriptIngestService.new(
            session: @meeting_session,
            actor: current_user
          ).ingest!(
            utterances: utterances,
            transcript_text: ingest_transcript_params[:transcript_text],
            metadata: metadata.merge(
              "transcript_source" => "google_meet_extension",
              "capture_origin" => "chrome_extension"
            ).compact
          )

          render json: { data: Api::V1::Serializers::MeetingSessionSerializer.render(@meeting_session.reload) }, status: :ok
        rescue ::Meetings::TranscriptIngestService::Error => error
          render_error(code: "invalid_transcript", message: error.message, status: :unprocessable_entity)
        end

        def cancel
          authorize @meeting_session, :update?

          ::Meetings::StopSessionService.new(
            session: @meeting_session,
            actor: current_user,
            reason: "Cancelled from Google Meet extension.",
            process_if_capture: false
          ).call

          render json: { data: Api::V1::Serializers::MeetingSessionSerializer.render(@meeting_session.reload) }, status: :ok
        rescue ActiveRecord::RecordInvalid => error
          render_validation_errors(error.record)
        end

        private

        def set_meeting_session!
          @meeting_session = policy_scope(MeetingSession).for_workspace(workspace).find(params[:id])
        end

        def create_params
          params.require(:meeting_session).permit(:title, :join_url, :kalendarium_event_id, :force_new)
        end

        def ingest_transcript_params
          params.require(:meeting_session).permit(
            :transcript_text,
            metadata: {},
            utterances: [ :speaker_key, :speaker_name, :text, :started_ms, :ended_ms, :confidence ]
          )
        end

        def matched_event
          explicit_event_id = create_params[:kalendarium_event_id].to_s.strip
          return policy_scope(KalendariumEvent).for_workspace(workspace).find(explicit_event_id) if explicit_event_id.present?

          ::Meetings::EventMatcherService.new(
            workspace: workspace,
            join_url: create_params[:join_url],
            title: create_params[:title]
          ).call
        end
      end
    end
  end
end
