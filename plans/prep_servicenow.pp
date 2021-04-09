# @summary
#   Prepares ServiceNow for the Change Request integration by ensuring all necessary objects exist (Change Category, Business Rule, Connection & Credential objects)
# 
# @example
#   bolt plan run servicenow_change_requests::prep_servicenow snow_endpoint=customer.service-now.com admin_user=admin admin_password=password cd4pe_endpoint=cd4pe.company.local
# 
# @param [String] snow_endpoint
#   FQDN of your ServiceNow instance. Only specify the FQDN, do not specify https://
# @param [String] admin_user
#   Username of the account in ServiceNow that has permissions to create objects
# @param [String] admin_password
#   Password of the account in ServiceNow that has permissions to create objects
# @param [String] cd4pe_endpoint
#   FQDN of your CD4PE instance. Only specify the FQDN, do not specify https://
# @param [Optional[Boolean]] cd4pe_https
#   If your CD4PE instance is published over HTTP and not HTTPS, change this setting to false
# @param [Optional[Integer]] cd4pe_port
#   If your CD4PE instance is published on a port other than 80(HTTP)/443(HTTPS), specify this setting
# @param [Optional[String]] connection_suffix
#   If you are connecting multiple CD4PE instances to a single ServiceNow instance, specify a string here to identify this CD4PE instance
# @param [Optional[String]] proxy_host
#   If you need to connect via a proxy server, specify its FQDN here
# @param [Optional[Integer]] proxy_port
#   If you need to connect via a proxy server, specify its port here
# 
plan servicenow_change_requests::prep_servicenow(
  String $snow_endpoint,
  String $admin_user,
  String $admin_password,
  String $cd4pe_endpoint,
  Optional[Boolean] $cd4pe_https = true,
  Optional[Integer] $cd4pe_port = undef,
  Optional[String] $connection_suffix = undef,
  Optional[String] $proxy_host = undef,
  Optional[Integer] $proxy_port = undef,
){
  # Parse flexible parameters
  $_snow_endpoint = $snow_endpoint[0,8] ? {
    'https://' => $snow_endpoint,
    default    => "https://${snow_endpoint}"
  }

  unless cd4pe_port {
    $_cd4pe_port = $cd4pe_https ? {
      true  => 443,
      false => 80
    }
  }
  else {
    $_cd4pe_port = $cd4pe_port
  }

  if $proxy_host and $proxy_port {
    $proxy = { 'enabled' => true, 'host' => $proxy_host, 'port' => $proxy_port }
  } else {
    $proxy = { 'enabled' => false }
  }

  # Connect to ServiceNow and validate credentials
  $cred_uri = "${_snow_endpoint}/api/now/table/sys_user_group?sysparm_limit=1"
  $cred_result = servicenow_change_requests::make_request($cred_uri, 'get', $proxy, $admin_user, $admin_password)
  unless $cred_result['code'] == 200 {
    fail("Unable to authenticate to ServiceNow! Got error ${cred_result['code']} with message ${cred_result['body']}")
  }
  else {
    out::message("Successfully authenticated to ServiceNow endpoint ${_snow_endpoint}")
  }

  # Check if 'Puppet Code' is listed as a change category
  $category_check_uri = "${_snow_endpoint}/api/now/table/sys_choice?sysparm_query=name=change_request&element=category&language=en"
  $category_check_result = servicenow_change_requests::make_request($category_check_uri, 'get', $proxy, $admin_user, $admin_password)
  unless $category_check_result['code'] == 200 {
    fail("Unable to request change categories! Got error ${category_check_result['code']} with message ${category_check_result['body']}")
  }
  $arr_choices = $category_check_result['body']
  $pc_choice = $arr_choices.filter |$choice| { $choice['value'] == 'Puppet Code' }

  unless $pc_choice.size == 1 {
    # Add 'Puppet Code' as an extra change category
    out::message("Change request category 'Puppet Code' does not exist, adding category...")
    $max_seq = $arr_choices.reduce(0) |$memo, $value| {
      unless $value['sequence'].empty {
        max($memo, Integer($value['sequence']))
      } else {
        max($memo, 0)
      }
    }
    $new_seq = $max_seq + 1
    $new_category = {
      'language' => 'en',
      'label'    => 'Puppet Code',
      'sequence' => $new_seq,
      'inactive' => 'false',
      'name'     => 'change_request',
      'value'    => 'Puppet Code',
      'element'  => 'category'
    }
    $new_category_uri = "${_snow_endpoint}/api/now/table/sys_choice"
    $new_category_result = servicenow_change_requests::make_request($new_category_uri, 'post', $proxy, $admin_user, $admin_password, $new_category)
    unless $new_category_result['code'] == 201 {
      fail("Unable to add Change request category 'Puppet Code'! Got error ${new_category_result['code']} with message ${new_category_result['body']}") # lint:ignore:140chars
    }
    out::message("Change request category 'Puppet Code' successfully added with sequence number ${new_seq}.")
  }
  else {
    out::message("Change request category 'Puppet Code' already present, nothing to do.")
  }

  # Check if 'Puppet - Promote code after approval' is listed as a business rule
  $rule_check_uri = "${_snow_endpoint}/api/now/table/sys_script?sysparm_query=name=Puppet%20-%20Promote%20code%20after%20approval"
  $rule_check_result = servicenow_change_requests::make_request($rule_check_uri, 'get', $proxy, $admin_user, $admin_password)
  unless $rule_check_result['code'] == 200 {
    fail("Unable to request business rules! Got error ${rule_check_result['code']} with message ${rule_check_result['body']}")
  }

  unless $rule_check_result['body'].size == 1 {
    # Add 'Puppet Code Promotion' business rule
    out::message("Business rule 'Puppet - Promote code after approval' does not exist, adding rule...")
    $rule_script = epp('servicenow_change_requests/business_rule_script.js')
    $new_rule = {
      client_callable   => 'false',
      template          => '',
      access            => 'package_private',
      action_insert     => 'false',
      action_update     => 'true',
      advanced          => 'true',
      action_delete     => 'false',
      change_fields     => 'false',
      description       => '',
      action_query      => 'false',
      when              => 'async',
      is_rest           => 'false',
      rest_method_text  => '',
      rest_service_text => '',
      order             => '100',
      rest_method       => '',
      rest_service      => '',
      add_message       => 'false',
      active            => 'true',
      collection        => 'change_request',
      message           => '',
      priority          => '100',
      script            => $rule_script,
      abort_action      => 'false',
      execute_function  => 'false',
      filter_condition  => 'stateCHANGESTO-1^category=Puppet Code^NQcategory=Puppet Code^state=-1^on_holdCHANGESTOfalse^EQ',
      condition         => '',
      rest_variables    => '',
      name              => 'Puppet - Promote code after approval',
      role_conditions   => '',
    }
    $new_rule_uri = "${_snow_endpoint}/api/now/table/sys_script"
    $new_rule_result = servicenow_change_requests::make_request($new_rule_uri, 'post', $proxy, $admin_user, $admin_password, $new_rule)
    unless $new_rule_result['code'] == 201 {
      fail("Unable to add business rule 'Puppet - Promote code after approval'! Got error ${new_rule_result['code']} with message ${new_rule_result['body']}") # lint:ignore:140chars
    }
    out::message("Business rule 'Puppet - Promote code after approval' successfully added.")
  }
  else {
    out::message("Business rule 'Puppet - Promote code after approval' already present, nothing to do.")
  }

  # Determine naming of connection details
  if $connection_suffix {
    $alias_name = "Puppet_Code_${connection_suffix}"
    $cred_name = "Puppet Code Credentials - ${connection_suffix}"
    $conn_name = "Puppet Code Connection - ${connection_suffix}"
  } else {
    $alias_name = 'Puppet_Code'
    $cred_name = 'Puppet Code Credentials'
    $conn_name = 'Puppet Code Connection'
  }

  # Check if connection alias is already present
  $alias_check_uri = "${_snow_endpoint}/api/now/table/sys_alias?sysparm_query=name=${alias_name}"
  $alias_check_result = servicenow_change_requests::make_request($alias_check_uri, 'get', $proxy, $admin_user, $admin_password)
  unless $alias_check_result['code'] == 200 {
    fail("Unable to request connection aliases! Got error ${alias_check_result['code']} with message ${alias_check_result['body']}")
  }

  unless $alias_check_result['body'].size == 1 {
    # Add connection alias
    out::message("Connection alias '${alias_name}' does not exist, adding connection alias...")
    $new_alias = {
      'configuration_template' => '',
      'connection_type'        => 'http_connection',
      'type'                   => 'connection',
      'multiple_connections'   => 'false',
      'name'                   => $alias_name,
    }
    $new_alias_uri = "${_snow_endpoint}/api/now/table/sys_alias"
    $new_alias_result = servicenow_change_requests::make_request($new_alias_uri, 'post', $proxy, $admin_user, $admin_password, $new_alias)
    unless $new_alias_result['code'] == 201 {
      fail("Unable to add connection alias '${alias_name}'! Got error ${new_alias_result['code']} with message ${new_alias_result['body']}") # lint:ignore:140chars
    }
    $alias_id = $new_alias_result['body']['sys_id']
    out::message("Connection alias '${alias_name}' successfully added.")
  }
  else {
    $alias_id = $alias_check_result['body'][0]['sys_id']
    out::message("Connection alias '${alias_name}' already present, nothing to do.")
  }

  # Check if credential is already present
  $cred_check_uri = "${_snow_endpoint}/api/now/table/discovery_credentials?sysparm_query=name=${cred_name}"
  $cred_check_result = servicenow_change_requests::make_request($cred_check_uri, 'get', $proxy, $admin_user, $admin_password)
  unless $cred_check_result['code'] == 200 {
    fail("Unable to request credentials! Got error ${cred_check_result['code']} with message ${cred_check_result['body']}")
  }

  unless $cred_check_result['body'].size == 1 {
    # Add credential
    out::message("Credential '${cred_name}' does not exist, adding credential...")
    $new_cred = {
      'user_name'               => 'change.me@company.com',
      'type'                    => 'basic_auth',
      'password'                => '',
      'order'                   => '100',
      'active'                  => 'true',
      'name'                    => $cred_name,
      'sys_class_name'          => 'basic_auth_credentials',
    }
    $new_cred_uri = "${_snow_endpoint}/api/now/table/discovery_credentials"
    $new_cred_result = servicenow_change_requests::make_request($new_cred_uri, 'post', $proxy, $admin_user, $admin_password, $new_cred)
    unless $new_cred_result['code'] == 201 {
      fail("Unable to add credential '${cred_name}'! Got error ${new_cred_result['code']} with message ${new_cred_result['body']}") # lint:ignore:140chars
    }
    $cred_id = $new_cred_result['body']['sys_id']
    out::message("Credential '${cred_name}' successfully added.")
  } else {
    $cred_id = $cred_check_result['body'][0]['sys_id']
    out::message("Credential '${cred_name}' already present, nothing to do.")
  }

  # Check if connection is already present
  $conn_check_uri = "${_snow_endpoint}/api/now/table/sys_connection?sysparm_query=name=${conn_name}"
  $conn_check_result = servicenow_change_requests::make_request($conn_check_uri, 'get', $proxy, $admin_user, $admin_password)
  unless $conn_check_result['code'] == 200 {
    fail("Unable to request connections! Got error ${conn_check_result['code']} with message ${conn_check_result['body']}")
  }

  unless $conn_check_result['body'].size == 1 {
    # Add connection
    out::message("Connection '${conn_name}' does not exist, adding connection...")
    $proto = $cd4pe_https ? { true  => 'https', false => 'http' }
    $new_conn = {
      'use_mid'            => 'false',
      'active'             => 'true',
      'sys_class_name'     => 'http_connection',
      'protocol'           => $proto,
      'connection_alias'   => $alias_id,
      'credential'         => $cred_id,
      'port'               => "${_cd4pe_port}", # lint:ignore:only_variable_string
      'host'               => $cd4pe_endpoint,
      'name'               => $conn_name,
      'connection_timeout' => '0',
    }
    $new_conn_uri = "${_snow_endpoint}/api/now/table/sys_connection"
    $new_conn_result = servicenow_change_requests::make_request($new_conn_uri, 'post', $proxy, $admin_user, $admin_password, $new_conn)
    unless $new_conn_result['code'] == 201 {
      fail("Unable to add connection '${conn_name}'! Got error ${new_conn_result['code']} with message ${new_conn_result['body']}") # lint:ignore:140chars
    }
    out::message("Connection '${conn_name}' successfully added.")
  }
  else {
    out::message("Connection '${conn_name}' already present, nothing to do.")
  }
}
