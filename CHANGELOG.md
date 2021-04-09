# Changelog

All notable changes to this project will be documented in this file.

## Release 0.2.2

**Features**
- Support for HTTP proxies (no authentication)

## Release 0.2.1

**Features**
- Quebec support. Note that this requires updating the custom deployment policy content in your control repo with the newer content provided by this module's update. 

## Release 0.2.0

**Features**
- The Business Rule in ServiceNow (for interacting with CD4PE) now automatically detects available MID Servers with a REST capability, and uses the first one available for outbound REST calls
- Risk and Impact fields in the Change Request are automatically set in accordance to the Impact Analysis verdict
- Now shows the name of the stage to promote toin the Change Request description, instead of the stage number

**Bugfixes**
- Now properly escapes special characters in commit descriptions, preventing an error when creating the Change Request

## Release 0.1.6

**Bugfixes**

Account for `compileFailed` key in Impact Analysis node report always existing in latest version of CD4PE 4.x

## Release 0.1.5

**Features**

Enable more detailed logging from the Business Rule in ServiceNow

**Bugfixes**

Correctly handle insufficient permissions in CD4PE

Wait for completion on deployments that do not require approval

## Release 0.1.4

**Features**

Add re-triggerable condition to Business Rule for ability to re-run orchestration on a change ticket when desired

**Bugfixes**

Dynamically handle definition of ENDPOINT variable in Business Rule

Correctly handle cookies from CD4PE 3.x and 4.x

## Release 0.1.3

**Bugfixes**

Ensure image URLs resolve correctly on the Puppet Forge

Update changelog

## Release 0.1.2

**Features**

First public release to the Puppet Forge

**Bugfixes**

Proper PDK conversion

## Release 0.1.1

**Features**

This release adds functionality to the `auto_create_ci` option. When this feature is enabled, newly created CI's in ServiceNow will have some of their fields populated from PuppetDB facts. The following mapping is provided out-of-the box:

(PE Fact => ServiceNow CI field)

```
fqdn                   => fqdn
domain                 => dns_domain
serialnumber           => serial_number
operatingsystemrelease => os_version
physicalprocessorcount => cpu_count
processorcount         => cpu_core_count
processors.models.0    => cpu_type
memorysize_mb          => ram
is_virtual             => virtual
macaddress             => mac_address
```

## Release 0.1.0

Initial release of this module, intended for early adoption testing
