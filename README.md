## Overview

This module helps you automate change requests in ServiceNow from Continuous Delivery for Puppet Enterprise (CD4PE) pipelines. The module has been tested for compatibility with the following ServiceNow versions:
* Paris
* Quebec
* Rome

The intended workflow that this module enables, is as follows:

1. Git commit `--triggers-->` CD4PE pipeline `--creates-->` ServiceNow change request
2. ServiceNow change request goes through internal approval process
3. Change request approved `--triggers-->` Business Rule `--orchestrates-->` CD4PE code promotion & deployment

## Module Description

The module consist of two parts:
* A Bolt plan (`servicenow_change_requests::prep_servicenow`) that is used to prepare ServiceNow for the integration.
* A set of files (in `files/deployments`) that provides a custom deployment policy for CD4PE. This content needs to be copied to `site-modules/deployments` of your control repo, so that CD4PE can use it.

Finally, this README provides the instructions for getting the integration up & running.

## Setup

### System Requirements & Compatibility

These are the requirements for the latest version of the module, see the [Compatibility matrix](https://github.com/puppetlabs/puppetlabs-servicenow_change_requests/blob/master/COMPATIBILITY.md) for more specific details.
* Puppet Enterprise 2019.8.5 or higher
* CD4PE 4.8.0 or higher
* ServiceNow Paris or higher

### Preparing ServiceNow

To ensure we can automate change requests, some things need to be added to ServiceNow:

* An additional change request category: `Puppet Code`
* A business rule named `Puppet Code Promotion` that triggers on approved `Puppet Code` change requests, and performs the orchestration against CD4PE (pipeline promotion & approvals of deployments to protected environments)
* CD4PE connection information & credentials for the business rule to use

A single plan takes care of setting this up. To run the plan, go to the `Plans` section in the left navigation bar in Puppet Enterprise. In the "Run a plan" screen, select the `servicenow_change_requests::prep_servicenow` from the Plan dropdown list. If the plan is not listed, ensure that this module has been added to the Puppetfile of your control repo, and that you have performed a code deployment to your production environment.

The plan requires 2 parameters + authentication info, and has 3 more optional parameters for specific use cases. The 2 required parameters are:
* `now_endpoint`:  The reachable FQDN of the ServiceNow instance (just the name is sufficient)
* `cd4pe_endpoint`: The publicly reachable FQDN of the CD4PE server (just the name, not the full URL)

For authentication info, either a username + password must be set, or a valid OAuth token can be used:
* `admin_user`:     The username of an administrator in ServiceNow, to make the necessary changes
* `admin_password`: The password of the specified admin_user
* `oauth_token`:    An OAuth token for accessing ServiceNow, instead of using username + password

For example, to configure the ServiceNow instance `https://dev365937.service-now.com` to integrate with a CD4PE server at `https://puppet-cd4pe.mycompany.com`, specify the parameters as follows:
* `now_endpoint  = dev365937.service-now.com`
* `cd4pe_endpoint = puppet-cd4pe.mycompany.com`
* `admin_user     = admin`
* `admin_password = <password>`

or, with an OAuth token:
* `now_endpoint  = dev365937.service-now.com`
* `cd4pe_endpoint = puppet-cd4pe.mycompany.com`
* `oauth_token    = <token>`

#### Optional plan parameters

If you are running a CD4PE version lower than 4.5.0, you will need to set the `br_version` parameter to ensure a compatible version of the Business Rule gets installed in ServiceNow:
* `br_version = 0.2.2`

Omit this parameter when you are running CD4PE 4.5.0 or above, which will install version 0.2.3 of the Business Rule, which is compatible with CD4PE 4.5.0.

The optional parameters `cd4pe_https` and `cd4pe_port` can be used to connect to a CD4PE server on a different port, or via http. For example, to configure the ServiceNow instance `https://dev365937.service-now.com` to integrate with a CD4PE server at `http://puppet-cd4pe.mycompany.com:8080`, specify the parameters as follows:
* `now_endpoint  = dev365937.service-now.com`
* `admin_user     = admin`
* `admin_password = <password>`
* `cd4pe_endpoint = puppet-cd4pe.mycompany.com`
* `cd4pe_https    = false`
* `cd4pe_port     = 8080`

The optional parameter `connection_suffix` can be used to integrate multiple CD4PE installations with a single ServiceNow instance. By default, the plan will create a `Puppet_Code` Connection Alias in ServiceNow, linked to a `Puppet Code Connection` and a `Puppet Code Credential`. This is great for when you have a single CD4PE installation. If you have 1 CD4PE installation, you don't need to specify the `connection_suffix` parameter.

To handle the multiple CD4PE installations for ServiceNow to interact with, a separate set of connections & credentials needs to be created in ServiceNow for each CD4PE instance. To let the plan do so, specify an appropriate suffix for this parameter. For example, to setup the integration for a secondary CD4PE installation used for "QA", specify `connection_suffix = QA`. This will create the following in ServiceNow:
* A `Puppet_Code_QA` Connection Alias
* A `Puppet Code Connection - QA` Connection, linked to the `Puppet_Code_QA` alias
* A `Puppet Code Credential - QA` Credential, linked to the `Puppet_Code_QA` alias


#### Setting the CD4PE username & password in ServiceNow

The plan will create a dummy credential in ServiceNow, for the user `change.me@company.com`. After running the plan for the first time, you need to go into ServiceNow and change it to the actual credential info:
1. In the ServiceNow navigation bar on the left, type `credentials` in the top filter field.
2. In the shown results, select `Credentials` below the `Connections & Credentials` section
3. Click on the credential to change. By default this is named `Puppet Code Credentials`. If you specified a `connection_suffix` in the plan above, the credential entry will have this suffix.
4. Change `change.me@company.com` to the actual name of the account in CD4PE you want to use for promoting code and approving deployments to protected environments. It's recommended to create a dedicated account in CD4PE for this purpose.
5. Update the password to the correct value for the account you specified in the previous step
6. Click the `Update` button on the lower left part of the form to save the changes.


### Preparing CD4PE

Once ServiceNow has been prepared, we can setup the integration in CD4PE. This integration makes use of CD4PE's Impact Analysis feature, to determine which nodes are affected by a Puppet code change. A typical pipeline might look like this before the integration:

![CD4PE Typical Pipeline](https://raw.githubusercontent.com/puppetlabs/puppetlabs-servicenow_change_requests/master/examples/cd4pe_pipeline_before.png)

>In this pipeline, the Impact Analysis has been configured to analyse the `production` environment.

With the ServiceNow integration, we will add a step between the "Impact Analysis" and the "Deploy to Production" stages. This step will take the output of the "Impact Analysis" step, and create a ServiceNow change request from the data. Upon approval of the change request in ServiceNow, a business rule runs in ServiceNow that promotes the pipeline to the next stage ("Deploy to Production"). If any subsequent stages require deployment approvals, ServiceNow will monitor them and approve the deployments as necessary.

With the added stage, the pipeline looks like this:

![CD4PE Pipeline with ServiceNow integration](https://raw.githubusercontent.com/puppetlabs/puppetlabs-servicenow_change_requests/master/examples/cd4pe_pipeline_after.png)


#### Adding the custom deployment policy to CD4PE

The added stage uses a custom deployment policy named `deployments::servicenow_integration`. We need to make this custom deployment policy available to CD4PE first. To do so:
1. Copy the `deployments` directory, found in the `files` directory of this module, into the `site-modules` directory of your control repo. If your control repo still uses a `site` directory (instead of `site-modules`), then copy the `deployments` directory into the `site` directory.
2. We recommend you perform step 1 in the `master` branch of your control-repo, and then let CD4PE promote these changes to your other branches, all the way into production. Once the `deployments` directory is deployed into production, your CD4PE instance should be able to find the `deployments::servicenow_integration` custom deployment policy.


#### Adding the ServiceNow Change Request stage

Once the custom deployment policy is available, add it to your `master` pipeline:
1. Click on the `...` icon of your `Deploy to Production` stage and click `Add a stage before`
2. Enter `ServiceNow Change Request` as the Stage Name
3. Select your Production environment as the target (this setting has no effect in practice for this particular custom deployment policy)
4. Click the `Custom deployment policies` radio button
5. Select the `deployments::servicenow_integration` policy
6. Set the parameters for the policy:
   * `now_endpoint`: the FQDN of your ServiceNow instance (e.g. `dev-365937.service-now.com`)
   * `now_username`: the username to authenticate with ServiceNow (e.g. `admin`)
   * `now_password`: the password to authenticate with ServiceNow (e.g. `P@ssw0rd!`)
   * `now_oauth_token`: an OAuth token for ServiceNow, instead of using username + password (if you set an OAuth token, it will be used instead of username + password)
   * `stage_to_promote_to`: the name of the stage to promote to, when approved (e.g. `Deploy to Production`)
7. If desired, set (some of the) optional parameters for the policy:
   * `max_changes_per_node`: how many resources per node may change before CD4PE recommends this code change warrants more scrutiny (defaults to `10`)
   * `report_stage`: name of the stage that performs the Impact Analysis (defaults to `Impact Analysis`). Set this parameter if your IA stage is not named "Impact Analysis"!
   * `assignment_group`: the group in ServiceNow to which the change is assigned (defaults to `Change Management`)
   * `connection_alias`: the name of the ServiceNow connection alias that should be used for orchestration after the change request is approved (defaults to `Puppet_Code`)
   * `auto_create_ci`: set to `true` to automatically create CI's in ServiceNow for nodes identified as affected by Impact Analysis, if those nodes do not exist as CI's in ServiceNow (defaults to `false`)
7. Click `Add stage` to complete the wizard.
8. Click the `Auto-promote` checkbox between the "Impact Analysis" and the "ServiceNow Change Request" stage.
9. Ensure no auto-promotion occurs between the "ServiceNow Change Request" stage and the "Deploy to Production" stage.


#### Setting permissions for the ServiceNow automation account

When preparing ServiceNow, you configured a CD4PE account (changing the dummy `change.me@company.com` account name). This account needs to:
* Exist in CD4PE
* Be a member of the workspace(s) that have pipelines that integrate with ServiceNow
* Have at least `List` and `Edit` permissions on `Control Repos` and `Modules` in the workspace(s)
* If using protected environment, the account must be a member of the approval group for that protected environment.


## Testing your integration

Once the above steps have been completed, make a Puppet code change in your `master` branch to verify the integration works. The CD4PE pipeline should trigger, and the last step should be the ServiceNow Change Request. Once that step has successfully completed:
1. Navigate to the Open Changes in ServiceNow
2. A new change request should be created, the "Short description" always starts with `Puppet Code -` followed by the commit message and the stage to promote to
3. Open the change request and note the information it contains:
   * The category is set to `Puppet Code`
   * The "Short description" and "Description" have been filled in with information from the code commit
   * The "Assignment group" has been configured
   * The "Risk and impact analysis" field in the "Planning" section has been filled in with a link to the CD4PE Impact Analysis, and a summary report of the results
   * The "Close notes" field in the "Closure information" section contains a hash of all the relevant data to automate the CD4PE pipeline upon approval of the change request
   * The "Affected CIs" table shows the records of nodes affected by the change (requires the CI's to exist in ServiceNow, or for the `auto_create_ci` parameter to be enabled in the custom deployment policy)
4. Approve the change request (both from the Assignment group and the CAB)
5. Once fully approved, click the `Implement` button on the top right to immediately start implementation of the change. This action triggers the business rule that runs asynchronously
6. Switch to the "Notes" section of the change request to see live updates of the orchestration as it happens. If an error does occur, you can see information about it in the `Script Log Statements` area of ServiceNow.
7. Check back in CD4PE to see that the pipeline has been promoted. If the deployment to the production environment was a protected environment, ServiceNow will also attempt to automatically approve this deployment. Of course you need to ensure that the credentials you have configured in ServiceNow have the appropriate permissions in CD4PE to do so.
8. Switch back to the change ticket in ServiceNow and navigate to the `Change Tasks` table. Notice that 2 change tasks have been created (`Implement` and `Post implementation testing`). Note that if the orchestration completed successfully, the Notes will say that the Change Tasks will be closed, and the Close Code for the ticket will be set to successful. Refresh the page of the ticket to verify that is indeed the case.
9. The change request is now in the `Review` state, and can be closed by clicking the `Close` button on the top right.
