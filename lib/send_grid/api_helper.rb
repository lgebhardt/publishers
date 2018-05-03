require 'digest'
require "base64"

module SendGrid
  class Error < StandardError; end
  class NotFoundError < StandardError; end
  class Unauthorized < StandardError; end
  class RateLimitExceeded < StandardError; end
  class PageLimitExceeded < StandardError; end

  class ApiHelper
    class << self
      def find_contact_by_email(email:)
        params = { "email": email }
        result = sg.client.contactdb.recipients.search.get(query_params: params)
        check_result(result: result, sucess: '200')

        json_result = JSON.parse(result.body)

        if json_result['recipient_count'] == 0
          raise NotFoundError.new
        end

        json_result['recipients'][0]
      end

      def get_contact_by_email(email:)
        result = sg.client.contactdb.recipients._(id_from_email(email)).get
        check_result(result: result, sucess: '200')
        JSON.parse(result.body)
      end

      def upsert_contacts(publishers:)
        raise PageLimitExceeded.new if publishers.length > 1000

        body = publishers.collect do |publisher|
          contact_params(publisher: publisher)
        end

        result = sg.client.contactdb.recipients.patch(request_body: body)
        check_result(result: result, sucess: '201')

        result_json = JSON.parse(result.body)
        if result_json['error_count'] > 0
          raise SendGrid::Error.new(result_json['errors'])
        end

        result_json['persisted_recipients']
      end

      # Updates or create the SendGrid contact for the publisher
      def upsert_contact(publisher:)
        result = upsert_contacts(publishers: [publisher])
        result[0]
      end

      def add_contact_to_list(list_id:, contact_id:)
        result = sg.client.contactdb.lists._(list_id).recipients._(contact_id).post()
        check_result(result: result, sucess: '201')
      end

      def add_contacts_to_list(list_id:, contact_ids:)
        result = sg.client.contactdb.lists._(list_id).recipients.post(request_body: contact_ids)
        check_result(result: result, sucess: '201')
      end

      def remove_contact_from_list(list_id:, contact_id:)
        params = {"recipient_id": contact_id, "list_id": list_id}
        result = sg.client.contactdb.lists._(list_id).recipients._(contact_id).delete(query_params: params)
        check_result(result: result, sucess: '204')
      end

      def add_contact_by_email_to_list(list_id:, email:)
        add_contact_to_list(list_id: list_id, contact_id: id_from_email(email))
      end

      def remove_contact_by_email_from_list(list_id:, email:)
        remove_contact_from_list(list_id: list_id, contact_id: id_from_email(email))
      end

      def contact_params(publisher:)
        params = { 'email': publisher.email}
        params['name'] = publisher.name unless publisher.name.blank?
        params['phone'] = publisher.phone_normalized unless publisher.phone_normalized.blank?
        params
      end

      private

      def id_from_email(email)
        Base64.strict_encode64(email.downcase)
      end

      def check_result(result:, sucess:)
        case result.status_code
        when sucess
          true
        when '400'
          raise Error.new(result.body)
        when '401'
          raise SendGrid::Unauthorized.new
        when '404'
          raise NotFoundError.new(result.body)
        when '429'
          raise SendGrid::RateLimitExceeded.new
        else
          raise "Unknown Error - status code: #{result.status_code}"
        end
      end

      def sg
        SendGrid::API.new(api_key: Rails.application.secrets[:sendgrid_api_key])
      end
    end
  end
end