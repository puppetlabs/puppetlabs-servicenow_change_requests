plan deployments::servicenow_integration(
  String $now_endpoint,
  String $now_username = '',
  Sensitive $now_password = Sensitive(''),
  Sensitive $now_oauth_token = Sensitive(''),
  String $stage_to_promote_to = undef,
  Optional[Integer] $max_changes_per_node = 10,
  Optional[String] $report_stage = 'Impact Analysis',
  Optional[String] $assignment_group = 'Change Management',
  Optional[String] $connection_alias = 'Puppet_Code',
  Optional[Boolean] $auto_create_ci = false,
  Optional[String] $proxy_host = undef,
  Optional[Integer] $proxy_port = undef,
  Optional[Boolean] $attach_ia_csv = false,
){
  # Read relevant CD4PE environment variables
  $repo_type         = system::env('REPO_TYPE')
  $commit_sha        = system::env('COMMIT')
  $control_repo_name = system::env('CONTROL_REPO_NAME')
  $module_name       = system::env('MODULE_NAME')

  $repo_name = $repo_type ? {
    'CONTROL_REPO' => $control_repo_name,
    'MODULE' => $module_name
  }

  # Parse $now_endpoint
  if $now_endpoint == undef {
    fail_plan('No ServiceNow endpoint specified!', 'no_endpoint_error')
  } else {
    $_now_endpoint = $now_endpoint[0,8] ? {
      'https://' => $now_endpoint,
      default    => "https://${now_endpoint}"
    }
  }

  # Parse potential proxy server info
  if $proxy_host and $proxy_port {
    $proxy = { 'enabled' => true, 'host' => $proxy_host, 'port' => $proxy_port }
    cd4pe_deployments::create_custom_deployment_event('Proxy will be used to communicate with ServiceNow')
  } else {
    $proxy = { 'enabled' => false }
  }

  # Set the stage number if we need to auto-detect it
  unless $report_stage {
    $stage_num = deployments::get_running_stage()
  }

  # Find the pipeline ID for the commit SHA
  $pipeline_id_result = cd4pe_deployments::search_pipeline($repo_name, $commit_sha)
  $pipeline_id = cd4pe_deployments::evaluate_result($pipeline_id_result)

  # Loop until items in the pipeline stage are done
  $loop_result = ctrl::do_until('limit'=>80) || {
    # Wait 15 seconds for each loop
    ctrl::sleep(15)
    # Get the current pipeline stage status (temporary variables that don't exist outside this loop)
    $pipeline_result = cd4pe_deployments::get_pipeline_trigger_event($repo_name, $pipeline_id, $commit_sha)
    $pipeline = cd4pe_deployments::evaluate_result($pipeline_result)
    # If $report_stage is set, set the stage number by searching the pipeline output
    if $report_stage {
      $stage = $pipeline['stageNames'].filter |$stagenumber,$stagename| { $stagename == $report_stage }
      unless $stage.length == 1 {
        fail_plan("Provided report_stage '${report_stage}' could not be found in pipeline. \
        If you manually promoted the pipeline, please ensure you promote at a point that \
        includes the Impact Analysis stage to report on!", 'stage_not_found_error')
      }
      $stage_num = $stage.keys[0]
    }
    # Check if items in the pipeline stage are done
    deployments::pipeline_stage_done($pipeline['eventsByStage'][$stage_num])
  }
  unless $loop_result {
    fail_plan('Timeout waiting for pipeline stage to finish!', 'timeout_error')
  }
  # Now that the relevant jobs in the pipeline stage have completed, generate the final pipeline variables
  $pipeline_result = cd4pe_deployments::get_pipeline_trigger_event($repo_name, $pipeline_id, $commit_sha)
  $pipeline = cd4pe_deployments::evaluate_result($pipeline_result)
  # If $report_stage is set, set the stage number by searching the pipeline output
  if $report_stage {
    $stage = $pipeline['stageNames'].filter |$stagenumber,$stagename| { $stagename == $report_stage }
    $stage_num = $stage.keys[0]
  }

  # Gather pipeline stage reporting
  cd4pe_deployments::create_custom_deployment_event('Gathering pipeline report information...')
  $scm_data = deployments::report_scm_data($pipeline)
  $stage_report = deployments::report_pipeline_stage($pipeline, $stage_num, $repo_name)

  # See if the stage contains an Impact Analysis
  $ia_events = $stage_report['build']['events'].filter |$event| { $event['eventType'] == 'IA' }
  if $ia_events.length > 0 {
    # Get the Impact Analysis information
    cd4pe_deployments::create_custom_deployment_event('Processing the Impact Analysis report...')
    $impact_analysis_id = $ia_events[0]['eventNumber']
    $impact_analysis_result = cd4pe_deployments::get_impact_analysis($impact_analysis_id)
    $impact_analysis = cd4pe_deployments::evaluate_result($impact_analysis_result)
    $ia_url = "${impact_analysis['baseTaskUrl']}/${impact_analysis['id']}"
    $ia_report = deployments::report_impact_analysis($impact_analysis)

    # Generate the detailed Impact Analysis report
    $ia_envs_report = $ia_report['results'].map |$ia_env_report| {
      $impacted_nodes_result = cd4pe_deployments::search_impacted_nodes($ia_env_report['IA_resultId'])
      $impacted_nodes = cd4pe_deployments::evaluate_result($impacted_nodes_result)
      cd4pe_deployments::create_custom_deployment_event("Impact Analysis for environment '${ia_env_report['IA_environment']}' contains ${impacted_nodes['rows'].length} impacted nodes...") # lint:ignore:140chars
      deployments::report_impacted_nodes($ia_env_report, $impacted_nodes, $max_changes_per_node)
    }

    # Retrieve the CSV export of the Impact Analysis
    if $attach_ia_csv {
      cd4pe_deployments::create_custom_deployment_event('Exporting Impact Analysis results to CSV...')
      $ia_csv_result = cd4pe_deployments::get_impact_analysis_csv($impact_analysis_id)
      $ia_csv_hash = cd4pe_deployments::evaluate_result($ia_csv_result)
      $ia_csv = $ia_csv_hash['csv'] ? {
        ''      => {'csv'=>'Impact analysis did not detect any resource changes'},
        default => $ia_csv_hash,
      }
    } else {
      $ia_csv = {'csv'=>''}
    }
  } else {
    $ia_envs_report = Tuple({})
    $ia_url = 'No Impact Analysis performed'
    $ia_csv = {'csv'=>'No Impact Analysis performed'}
  }

  # Combine all reports into a single hash
  $report = deployments::combine_reports($stage_report, $scm_data, $ia_envs_report)

  ## Interact with ServiceNow
  # Process full pipeline structure to determine stage number of stage to promote to
  $pipeline_structure_result = cd4pe_deployments::get_pipeline($repo_type, $repo_name, $pipeline_id)
  $pipeline_structure = cd4pe_deployments::evaluate_result($pipeline_structure_result)
  unless $stage_to_promote_to {
    fail_plan('No stage specified for ServiceNow to promote approved changes to!', 'no_promote_stage_error')
  }
  $promote_stage = $pipeline_structure['stages'].filter |$item| { $item['stageName'] == $stage_to_promote_to }
  unless $promote_stage.length == 1 {
    fail_plan("Provided stage_to_promote_to '${stage_to_promote_to}' could not be found in pipeline. \
    Please ensure a valid stage name is specified!", 'stage_not_found_error')
  }
  $promote_stage_number = $promote_stage[0]['stageNum']
  # ** For debugging only **
  # $content = {
  #   '_now_endpoint'        => $_now_endpoint,
  #   'proxy'                => $proxy,
  #   'now_username'         => $now_username,
  #   'now_password'         => $now_password,
  #   'now_oauth_token'      => $now_oauth_token,
  #   'report'               => $report,
  #   'ia_url'               => $ia_url,
  #   'stage_to_promote_to'  => $stage_to_promote_to,
  #   'promote_stage_number' => $promote_stage_number,
  #   'assignment_group'     => $assignment_group,
  #   'connection_alias'     => $connection_alias,
  #   'auto_create_ci'       => $auto_create_ci,
  #   'ia_csv'               => $ia_csv['csv']
  # }
  # cd4pe_deployments::create_custom_deployment_event(to_json($content))

  # Trigger Change Request workflow in ServiceNow DevOps
  cd4pe_deployments::create_custom_deployment_event('Creating ServiceNow Change Request...')
  deployments::servicenow_change_request(
    $_now_endpoint,
    $proxy,
    $now_username,
    $now_password,
    $now_oauth_token,
    $report,
    $ia_url,
    $stage_to_promote_to,
    $promote_stage_number,
    $assignment_group,
    $connection_alias,
    $auto_create_ci,
    $ia_csv['csv']
  )
}
