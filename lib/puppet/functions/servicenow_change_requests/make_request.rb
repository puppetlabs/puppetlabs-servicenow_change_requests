require 'net/http'
require 'uri'
require 'json'

Puppet::Functions.create_function(:'servicenow_change_requests::make_request') do
  dispatch :make_request do
    required_param 'String', :endpoint
    required_param 'String', :type
    required_param 'Hash', :proxy
    required_param 'String', :username
    required_param 'Sensitive[String]', :password
    required_param 'Sensitive[String]', :oauth_token
    optional_param 'Hash', :payload
  end

  def make_request(endpoint, type, proxy, username, password, oauth_token, payload = nil)
    uri = URI.parse(endpoint)
    max_attempts = 3
    attempts = 0
    while attempts < max_attempts
      attempts += 1
      begin
        Puppet.debug("servicenow_change_request: performing #{type} request to #{endpoint}")
        case type
        when 'delete'
          request = Net::HTTP::Delete.new(uri.request_uri)
        when 'get'
          request = Net::HTTP::Get.new(uri.request_uri)
        when 'post'
          request = Net::HTTP::Post.new(uri.request_uri)
          request.body = payload.to_json unless payload.nil?
        when 'patch'
          request = Net::HTTP::Patch.new(uri.request_uri)
          request.body = payload.to_json unless payload.nil?
        else
          raise Puppet::Error, "servicenow_change_request#make_request called with invalid request type #{type}"
        end
        if oauth_token.unwrap.to_s.strip.empty?
          request.basic_auth(username, password.unwrap)
        else
          request['Authorization'] = "Bearer #{oauth_token.unwrap}"
        end
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'

        if proxy['enabled'] == true
          proxy_conn = Net::HTTP::Proxy(
            proxy['host'],
            proxy['port'],
          )
          response = proxy_conn.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http| # rubocop:disable Style/HashSyntax
            http.read_timeout = 60
            http.request(request)
          end
        else
          connection = Net::HTTP.new(uri.host, uri.port)
          connection.use_ssl = true if uri.scheme == 'https'
          connection.read_timeout = 60
          response = connection.request(request)
        end
      rescue SocketError => e
        raise Puppet::Error, "Could not connect to the ServiceNow endpoint at #{uri.host}: #{e.inspect}", e.backtrace
      end

      case response
      when Net::HTTPSuccess, Net::HTTPRedirection
        result = {
          'code' => response.code.to_i,
          'body' => JSON.parse(response.body)['result'],
        }
        return result
      when Net::HTTPInternalServerError
        if attempts < max_attempts # rubocop:disable Style/GuardClause
          Puppet.debug("Received #{response} error from #{uri.host}, attempting to retry. (Attempt #{attempts} of #{max_attempts})")
          Kernel.sleep(3)
        else
          raise Puppet::Error, "Received #{attempts} server error responses from the ServiceNow endpoint at #{uri.host}: #{response.code} #{response.body}"
        end
      else
        result = {
          'code' => response.code.to_i,
          'body' => JSON.parse(response.body)['error'],
        }
        return result
      end
    end
  end
end
