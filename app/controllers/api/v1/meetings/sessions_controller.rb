module Api
  module V1
    module Meetings
      class SessionsController < BaseController
        before_action :set_workspace!
        before_action :set_meeting_session!, only: %i[show transcript]

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

        private

        def set_meeting_session!
          @meeting_session = policy_scope(MeetingSession).for_workspace(workspace).find(params[:id])
        end
      end
    end
  end
end
