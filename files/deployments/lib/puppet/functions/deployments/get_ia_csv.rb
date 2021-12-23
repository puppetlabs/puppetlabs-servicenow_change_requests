# frozen_string_literal: true

Puppet::Functions.create_function(:'deployments::get_ia_csv') do
  dispatch :get_ia_csv do
    required_param 'String', :url
    required_param 'String', :domain
    required_param 'Integer', :id
  end

  # Download csv with impact analysis results from CD4PE
  # The URL from the impact analsys data does not match the
  # api. So the api url has to be combined.
  def get_ia_csv(url, domain, id)

    arr = url.split('/')
    proto = arr[0]
    cd4pe_domain = arr[2]
    uri = arr[3]
    endpoint = "#{proto}//#{cd4pe_domain}/#{uri}/api/v1/impact-analysis/#{id}/csv?workspaceId=#{domain}" 
    # TODO: get token or have an API call without token needed
    token = 'just a workarround'
    headers = {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json',
      'authorization' => token,
    }
    response_res = cd4pe_api_request(endpoint, :get, headers)
    raise Puppet::Error, "Received unexpected response from the CD4PE endpoint: #{response_res.code} #{response_res.body}" unless response_res.is_a?(Net::HTTPSuccess)
    
    data = response_res.body
    json = JSON.parse(data)   
    csv = json['csv']
    # if csv is empty or nil add some text as empty attachments are not possible in ServiceNOW
    # and a missing attachment could be an error as well.
    if csv.nil? || csv == ''
      csv = 'Impact analysis didn\'t detect any resource changes!'
    end
    csv
  end

  # Call CD4PE API
  def cd4pe_api_request(endpoint, type, headers)
  
    uri = URI.parse(endpoint)
    
    begin
      Puppet.debug("servicenow_change_request: performing #{type} request to #{endpoint}")
      case type
      when :delete
        request = Net::HTTP::Delete.new(uri.request_uri)
      when :get
        request = Net::HTTP::Get.new(uri.request_uri)
      when :post
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = payload.to_json unless payload.nil?
      when :patch
        request = Net::HTTP::Patch.new(uri.request_uri)
        request.body = payload.to_json unless payload.nil?
      else
        raise Puppet::Error, "servicenow_change_request#cd4pe_api_request called with invalid request type #{type}"
      end
      headers.each do |header, value|
        request[header] = value
      end
      connection = Net::HTTP.new(uri.host, uri.port)
      connection.use_ssl = true if uri.scheme == 'https'
      connection.read_timeout = 60
      response = connection.request(request)
    rescue SocketError => e
      raise Puppet::Error, "Could not connect to the CD4PE endpoint at #{uri.host}: #{e.inspect}", e.backtrace
    end

    case response
    when Net::HTTPInternalServerError
      if attempts < max_attempts # rubocop:disable Style/GuardClause
        Puppet.debug("Received #{response} error from #{uri.host}, attempting to retry. (Attempt #{attempts} of #{max_attempts})")
        Kernel.sleep(3)
      else
        raise Puppet::Error, "Received #{attempts} server error responses from the ServiceNow endpoint at #{uri.host}: #{response.code} #{response.body}"
      end
    else # Covers Net::HTTPSuccess, Net::HTTPRedirection
      return response
    end
  end

end