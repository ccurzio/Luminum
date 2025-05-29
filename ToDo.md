# Luminum Development To-Do List
In order to be accountable to the community - but more importantly to myself - I figured it would be a good idea to create a to-do list for the project as a quick reference for what's being worked on, what's been accomplished, and what still needs doing. 

## Server Installation
  
### First-Run Setup
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Setup Utility               |Create interface for a step-by-step setup wizard to run when first installed            |
|Not Started    |OS User Accounts            |Automatically create necessary OS service accounts for Luminum Server                   |
|*In Progress*  |Configuration Save/Import   |Routines to save the server configuration and import an existing config on first setup  |
|Not Started    |Certificate Setup           |Routines to create or import server certificates                                        |
|Not Started    |Database Setup              |Automatically configure the database software and set root password                     |
|Not Started    |Database Structure          |Create Luminum Server databases and tables                                              |
|Not Started    |Database User Accounts      |Create necessary Luminum Server database user accounts and grant permissions            |
|Not Started    |nginx Configuration         |Routines to automatically configure the nginx webserver software for Luminum            |
|Not Started    |Apache Configuration        |Routines to automatically configure the Apache webserver software for Luminum           |
|Not Started    |lighttpd Configuration      |Routines to automatically configure the lighttpd webserver software for Luminum         |
|Not Started    |PHP Configuration           |Routines to configure PHP running under nginx for Luminum                               |


### Web Server Integrations
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |nginx                       |Luminum Server install with web console running on nginx                                |
|Not Started    |Apache                      |Luminum Server install with web console running on Apache httpd                         |
|Not Started    |lighttpd                    |Luminum Server install with web console running on lighttpd                             |


### Debian Support
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create Package              |Create .deb installation package                                                        |


### Ubuntu Support
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create Package              |Create .deb installation package                                                        |


### RHEL Support
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create Package              |Create .rpm installation package                                                        |


### CentOS Support
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create Package              |Create .rpm installation package                                                        |


### Slackware Support
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create Package              |Create .txz installation package                                                        |


### Docker
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Create Image                |Create Luminum Server Docker image                                                      |
|Not Started    |Setup Scripts               |Create scripts supporting the installation of a Luminum Server Docker image             |


### Virtual Appliances
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Proxmox                     |Luminum Server virtual machine for Proxmox                                              |
|Not Started    |VirtualBox                  |Luminum Server virtual machine for VirtualBox                                           |
|Not Started    |VMWare                      |Luminum Server virtual machine for VMWare                                               |

<br>
<br>

## Server System
  
### Configuration
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |Parameter Functions         |Create functions to set server configuration parameters                                 |
|*In Progress*  |DB Configuration Values     |Create key/value pairs for storing primary configuration options in the database        |
|*In Progress*  |File Configuration Values   |Create key/value pairs for storing base configuration options in a config file          |

<ul>
<li>
  
#### Primary Configuration Options/Values
|Status         |Key            |Default Value    |Description                                                                             |
|---------------|---------------|-----------------|----------------------------------------------------------------------------------------|
|**Completed**  |SID            |                 |The unique Luminum Server ID                                                            |
|*In Progress*  |SKEY           |                 |The unique Luminum Server Key used by clients to verify their association               |
|*In Progress*  |LADDR          |                 |The address of the interface to be used by the network listener                         |
|*In Progress*  |LPORT          |10465            |The port number to be usedby the network listener on the specified network interface    |
|*In Progress*  |SSLCERT        |                 |The full path to the main SSL Certificate to be used by Luminum Server                  |
|*In Progress*  |SSLPRVKEY      |                 |The full path to the private key associated with the cert defined as SSLCERT            |
|*In Progress*  |SSLPUBKEY      |                 |The full path to the public key associated with the cert defined as SSLCERT             |
|*In Progress*  |PKPASS         |                 |The passphrase for the private key associated with the cert defined as SSLCERT          |
|*In Progress*  |SHOST          |                 |The server's fully-qualified domain name                                                |
|*In Progress*  |INSTALLDATE    |                 |Date and time Luminum Server was installed                                              |
|**Completed**  |ENLUMYS        |                 |A comma-separated list of currently enabled Lumys                                       |
|*In Progress*  |TARGETCONF     |Enabled          |Action confirmation based on the number of targeted endpoints                           |
|*In Progress*  |TCONFTHRESHOLD |250              |The minimum number of targeted endpoints to trigger requiring action confirmation       |
|*In Progress*  |ENDPOINTCOMM   |mqtt             |The method used by the server and clients to communicate                                |
|*In Progress*  |CHECKININT     |5                |The interval (in minutes) at which clients will check in with the server                |
|*In Progress*  |MISSINGAFTER   |90               |The time (in days) at which point the system determines offline clients are missing     |
|*In Progress*  |TIMEOUT        |15M              |The length of time a user is inactive before their session is terminated                |
|*In Progress*  |TIMEOUTWARN    |Enabled          |Display a warning to users 2 minutes before their session is terminated for inactivity  |
|*In Progress*  |MINPASS        |8                |Minimum password character length                                                       |
|*In Progress*  |COMPLEXPASS    |Disabled         |Enforce password complexity requirements                                                |
|*In Progress*  |PCUPPERLOWER   |Disabled         |Both upper and lowercase letters are required in passwords for complexity enforcement   |
|*In Progress*  |PCLETNUM       |Disabled         |Both letters and numbers are required in passwords for complexity enforcement           |
|*In Progress*  |PCSPECIAL      |Disabled         |Special characters are required in passwords for complexity enforcement                 |
|*In Progress*  |2FA            |Optional         |Two-Factor Authentication policy for user accounts                                      |
|Not Started    |USERLOGLVL     |Disabled         |Account-specific log levels                                                             |
|Not Started    |SENREVS        |5                |Maximum revision history for sensors                                                    |
|Not Started    |PKGREVS        |5                |Maximum revision history for packages                                                   |
|Not Started    |INVESTIGATE    |Enabled          |Enable or Disable Luminum Investigate                                                   |
</li>

<li>
  
#### Base Configuration Options/Values
|Status          |Key            |Default Value    |Description                                                                             |
|----------------|---------------|-----------------|----------------------------------------------------------------------------------------|
|**Completed**   |SID            |                 |The unique Luminum Server ID                                                            |
|*DEPRECATED*    |~~SKEY~~       |                 |~~The unique Luminum Server Key used by clients to verify their association~~           |
|*DEPRECATED*    |~~IPADDR~~     |                 |~~The address of the interface to be used by the network listener~~                     |
|*DEPRECATED*    |~~PORT~~       |                 |~~The port number to be usedby the network listener on the specified network interface~~|
|**Completed**   |DBPASS         |                 |The password for the "Luminum" database account                                         |
|*DEPRECATED*    |~~PKPASS~~     |                 |~~The passphrase for the server's private key~~                                         |

</li>
</ul>

### Communication
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |MQTT Comms                  |Setup and configuration of the MQTT messaging channel                                   |
|Not Started    |Direct Connect Comms        |Setup and configuration of the direct client<->server messaging channel                 |
|*In Progress*  |Message Format              |Develop the specific formatting for client and server messages                          |
|Not Started    |Message Validation          |Validity checking of client/server messages based on signature verification             |
|Not Started    |Query Format                |Develop the specific format of server-actionable user information queries               |
|Not Started    |SMTP Server Configuration   |Setup and configuration of SMTP servers to be used by Luminum Server                    |
|Not Started    |SMTP Configuration Test     |Validate SMTP server configurations by performing connection tests                      |


### Broker Process
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Network Listener            |The actual process that opens on a secure network interface to listen for connections   |
|*In Progress*  |Message Handling            |The routines that parse messages from the server and/or endpoints                       |
|Not Started    |Client Certificate          |Attach a requirement for client certificats to the listener process                     |
|*In Progress*  |Lumy Scanning               |Include Lumys based on enabled/disabled state in configuration and file include presence|
|*In Progress*  |Client Onboarding           |Processing for newly-added clients on first report to the server                        |
|*In Progress*  |Client Deactivation         |Processing the removal of clients from the server                                       |
|*In Progress*  |Check-In Processing         |Handle server-side updates on regular client check-ins                                  |
|Not Started    |Action Queueing             |Development of the queue structure for pending queries and actions                      |
|Not Started    |Action Polling              |Development of the routines that watch for and then send new queries or actions         |


### Logging
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Configuration Changes       |Generate log entries for changes to the system configuration                            |
|Not Started    |User sign-in/sign-out       |Generate log entries for instances of user login/logout                                 |
|Not Started    |Invalid Credentials         |Generate log entries for failed login attempts                                          |
|Not Started    |Navigation                  |Generate log entries for user page navigation                                           |
|*In Progress*  |Broker Information          |Generate log entries from broker processing                                             |
|Not Started    |Account Modification        |Generate log entries for user account modifications                                     |
|Not Started    |User Group Modifications    |Generate log entries on the creation or modification of user groups                     |
|Not Started    |Computer Group Modifications|Generate log entries on the creation or modification of computer groups                 |
|Not Started    |Actions                     |Generate log entries for action deployments                                             |
|Not Started    |System Maintenance          |Generate log entries for system maintenance tasks                                       |
|Not Started    |Create/Modify Content       |Generate log entries on the creation or modification of content and content sets        |
|Not Started    |Client Management           |Generate log entries based on Client Management actions                                 |
|Not Started    |Lumy Management             |Generate log entries based on Lumy Management actions                                   |


### User Management
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |User Accounts               |Create structure for storing users in the database                                      |
|**Completed**  |Password Hashing            |Use hashing for stored password data                                                    |
|Not Started    |Enable/Disable Accounts     |Routines for administrators to lock or unlock user accounts                             |
|Not Started    |Account Expiration          |Implement configuration and enforcement of expiration dates for user accounts           |
|Not Started    |Password Change Intervals   |Implement regular forced password change intervals for user accounts                    |


### Investigate
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Real-Time Shell             |Manages connections to specified endpoints offering remote shell access                 |

  
### Content

<ul>
<li>

#### Content Sets
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Content Set Records         |Create structure for recording content sets in the database                             |
|Not Started    |Content Set Management      |Routines for adding/modifying/deleting content sets                                     |
|Not Started    |Category Management         |Routines to manage categories for content sets                                          |
</li>

<li>

#### Sensors
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Database Sensor Storage     |Create structure for storing sensors in the database                                    |
|Not Started    |Sensor Management           |Routines for adding/modifying/deleting sensors                                          |
|Not Started    |Revision Control            |Routines to manage and view previous versions of sensors                                |
</li>

<li>

#### Packages
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Database Package Storage    |Create structure for storing packages in the database                                   |
|Not Started    |Filesystem Package Storage  |Create structure for storing and referencing package files                              |
|Not Started    |Package Management          |Routines for adding/modifying/deleting packages                                         |
|Not Started    |Revision Control            |Routines to manage and view previous versions of packages                               |
</li>
</ul>

### Modules

<ul>
<li>

#### Delivery
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Include File                |Create module include for broker process to attach the Delivery Lumy                    |
|Not Started    |Database Structure          |Create and grant permissions to Delivery-specific databases and tables                  |
|Not Started    |Profiles                    |Establish configuration profiles for Delivery deployments                               |
</li>

<li>

#### Discovery
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Include File                |Create module include for broker process to attach the Discovery Lumy                   |
|Not Started    |Database Structure          |Create and grant permissions to Discovery-specific databases and tables                 |
|Not Started    |Profiles                    |Establish configuration profiles for Discovery deployments                              |
</li>

<li>

#### Efficiency
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Include File                |Create module include for broker process to attach the Efficiency Lumy                  |
|Not Started    |Database Structure          |Create and grant permissions to Efficiency-specific databases and tables                |
|Not Started    |Profiles                    |Establish configuration profiles for Efficiency deployments                             |
</li>

<li>

#### Integrity
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Include File                |Create module include for broker process to attach the Integrity Lumy                   |
|Not Started    |Database Structure          |Create and grant permissions to Integrity-specific databases and tables                 |
|Not Started    |Profiles                    |Establish configuration profiles for Integrity deployments                              |

</li>

<li>
  
#### Inventory
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Include File                |Create module include for broker process to attach the Integrity Lumy                   |
|Not Started    |Database Structure          |Create and grant permissions to Inventory-specific databases and tables                 |
|Not Started    |OSQuery Integration         |Support for integrating with OSQuery                                                    |
</li>

<li>
  
#### Policy
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Include File                |Create module include for broker process to attach the Policy Lumy                      |
|Not Started    |Database Structure          |Create and grant permissions to Policy-specific databases and tables                    |
|Not Started    |Profiles                    |Establish configuration profiles for Policy deployments                                 |
</li>
</ul>

<br>
<br>

## Web Console

### Core
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Base UI Framework           |Create the consistent foundational elements for the web user interface                  |
|Not Started    |Include Architecture        |Revise the methods by which the web interface includes content for sections of the UI   |
|Not Started    |Stylesheet Consolidation    |Reduce stylesheet definitions to specific needed defs and eliminate redundancies        |
|Not Started    |Element Generation Functions|Develop dynamic functions to automatically generate UI elements on-demand               |
|*In Progress*  |Overlay Message             |Create a dynamic message window which displays as a full-screen overlay above the UI    |
|**Completed**  |Lumy Menus                  |Dynamically inject UI navigation options for enabled Lumy modules                       |


### Session Management
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |Console Login Processing    |Present a login screen and start a session or reject based on credentials               |
|**Completed**  |Session Timeout             |Automatically terminate a user session if left inactive                                 |
|Not Started    |Two-Factor Authentication   |Capture user sessions and shunt to 2FA validation on successful login                   |
|Not Started    |Mandatory Password Change   |Capture user sessions and shunt to a change password interface on successful login      |
|*In Progress*  |Permissions Adjustments     |Show or hide UI elements/options based on the user's access level                       |


### User Account Settings
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |Settings Interface          |Present a user interface to view/modify account details                                 |
|Not Started    |Authenticator 2FA Setup     |Authenticator-based two-factor Authentication setup process for users                   |
|Not Started    |SMS 2FA Setup               |SMS-based two-factor Authentication setup process for users                             |
|Not Started    |Email 2FA Setup             |Email-based two-factor Authentication setup process for users                           |
|Not Started    |Password Change             |Implement functions for user-initiated change of password                               |


### Administration
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |Client Status               |Present a user interface to view/filter and take action against checked-in clients      |
|Not Started    |Missing Clients             |Present a user interface allowing administrators to manage missing clients              |
|**Completed**  |Scheduled Actions           |Presents a table displaying information about current scheduled actions                 |
|**Completed**  |Action History              |Presents a table displaying information about past actions                              |
|Not Started    |Computer Groups             |Presents a table displaying information about configured computer groups                |

### Content 

<ul>
<li>
  
#### Content Sets
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Content Sets                |Presents a table displaying information about system content sets                       |
|Not Started    |Add/Edit Content Set        |Present a user interface to create or modify content sets                               |
|Not Started    |Content Categories          |Present a user interface to manage categories for content sets                          |
</li>

<li>

#### Sensors
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |Sensor List                 |Presents a table displaying information about all avaialble sensors                     |
|*In Progress*  |Add/Edit Sensor             |Present a user interface to create or modify sensors                                    |
|Not Started    |New Sensor Column Config    |User interface within the new sensor UI for splitting sensor output into table columns  |
|**Completed**  |Sensor Code Editor (Linux)  |Browser-based code editor with syntax highlighting for languages supported under Linux  |
|**Completed**  |Sensor Code Editor (macOS)  |Browser-based code editor with syntax highlighting for languages supported under macOS  |
|**Completed**  |Sensor Code Editor (Windows)|Browser-based code editor with syntax highlighting for languages supported under Windows|
</li>

<li>

#### Packages
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|**Completed**  |Package List                |Presents a table displaying information about all avaialble packages                    |
|*In Progress*  |Add/Edit Package            |Present a user interface to create or modify packages                                   |
</li>
</ul>

### System

<ul>
<li>

#### Information
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Luminum Information         |User interface to display general Luminum server information                            |
|**Completed**  |CPU Information             |User interface to display server CPU information                                        |
|*In Progress*  |Storage Information         |User interface to display server disk information                                       |
|Not Started    |Memory Information          |User interface to display server memory information                                     |
|Not Started    |Network Information         |User interface to display server network interface information                          |
|**Completed**  |User Accounts               |Presents a table displaying information about all user accounts                         |
</li>

<li>

#### Configuration
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |User Management             |User interface for administrators to create/modify user accounts                        |
|Not Started    |User Group Management       |User interface for administrators to create/modify user account groups                  |
|*In Progress*  |General Settings            |User interface for administrators to view/modify general Luminum settings               |
|*In Progress*  |Endpoint Settings           |User interface for administrators to view/modify endpoint settings                      |
|*In Progress*  |Content Settings            |User interface for administrators to view/modify content settings                       |
|Not Started    |SMTP Settings               |User interface for administrators to configure SMTP servers and settings                |
|Not Started    |Encryption Settings         |User interface for administrators to configure encryption settings                      |
|*In Progress*  |User Login Settings         |User interface for administrators to view/modify user login settings                    |
|Not Started    |Networking Settings         |User interface for administrators to view/modify server network settings                |
|Not Started    |Certificate Settings        |User interface for administrators to view/modify server certificate settings            |
|Not Started    |Authentication Interface    |User interface for administrators to view/modify account authentication settings        |
|Not Started    |Client Management           |Present a user interface for administrators to manage Luminum client software           |
|Not Started    |Lumy Management             |Present a user interface for administrators to manage Lumy modules                      |
</li>

<li>

#### Maintenance
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Diagnostics Interface       |Present a user interface for administrators to perform various system diagnostics       |
|Not Started    |Updates Interface           |Present a user interface for administrators to manage Luminum updates                   |
|Not Started    |Outage Interface            |Present a user interface for administrators to manage scheduled/immediate downtime      |
|Not Started    |OS Management               |Present a user interface for administrators to manage the underlying Operating System   |
|Not Started    |Services Interface          |Present a user interface for administrators to manage services on the underlying OS     |
|Not Started    |Log Viewer                  |Present a user interface for administrators to view and manage various system logs      |
</li>
</ul>


### Investigate

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Session Configuration       |Interface for creating and configuring an Investigate session                           |
|Not Started    |Real-Time Shell             |User interface for remote shell access to endpoints                                     |


### Modules 

<ul>  
<li>

#### Query

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Query Interface             |Present a dynamic user interface for users to construct queries                         |
|Not Started    |Question Summary            |Convert entered data in the query UI to a human-readable summary                        |
|Not Started    |Query Data Parsing          |Convert entered data in the query UI to a system-parseable query statement              |
</li>

<li>

#### Summary

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Configuration               |Present a user interface to configure Summary sources and destinations                  |
</li>

<li>

#### Delivery

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Overview Interface          |Present overview information of the current status of Delivery in the environment       |
|Not Started    |Profile Configuration       |Present a user interface for administrators to create/modify Delivery profiles          |
</li>

<li>

#### Discovery

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Overview Interface          |Present overview information of the current status of Discovery in the environment      |
|Not Started    |Profile Configuration       |Present a user interface for administrators to create/modify Discovery profiles         |
</li>

<li>

#### Efficiency

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Overview Interface          |Present overview information of the current status of Efficiency in the environment     |
|Not Started    |Profile Configuration       |Present a user interface for administrators to create/modify Efficiency profiles        |
</li>

<li>

#### Integrity

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Overview Interface          |Present overview information of the current status of Integrity in the environment      |
|Not Started    |Profile Configuration       |Present a user interface for administrators to create/modify Integrity profiles         |
</li>

<li>

#### Inventory
|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Overview Interface          |Present overview information of the current status of Inventory in the environment      |
</li>

<li>

#### Policy

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Overview Interface          |Present overview information of the current status of Policy in the environment         |
|Not Started    |Profile Configuration       |Present a user interface for administrators to create/modify Policy profiles            |
</li>
</ul>

<br>
<br>

## Client Installation

### Linux Support

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Setup Utility               |Create client install step-by-step setup utility                                        |
|Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
|Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
|Not Started    |x86 Client Binaries         |Create x86-compiled client binaries                                                     |
|Not Started    |x64 Client Binaries         |Create x64-compiled client binaries                                                     |
|Not Started    |ARM Client Binaries         |Create ARM-compiled client binaries                                                     |


### macOS Support

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Setup Utility               |Create client install step-by-step setup utility                                        |
|Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
|Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
|Not Started    |Apple Silicon Binaries      |Create client binaries for Apple Silicon                                                |
|Not Started    |Intel Binaries              |Create client binaries for Intel                                                        |
|Not Started    |Universal Binaries          |Create universal client binaries                                                        |


### Windows Support

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Setup Utility               |Create client install step-by-step setup utility                                        |
|Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
|Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
|Not Started    |x86 Client Binaries         |Create x86-compiled client binaries                                                     |
|Not Started    |x64 Client Binaries         |Create x64-compiled client binaries                                                     |
|Not Started    |ARM Client Binaries         |Create ARM-compiled client binaries                                                     |


### Debian Packaging

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create x86 Package          |Create & Sign x86 .deb installation package                                             |
|Not Started    |Create x64 Package          |Create & Sign x64 .deb installation package                                             |
|Not Started    |Create ARM Package          |Create & Sign ARM .deb installation package                                             |


### Ubuntu Packaging

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create x86 Package          |Create & Sign x86 .deb installation package                                             |
|Not Started    |Create x64 Package          |Create & Sign x64 .deb installation package                                             |
|Not Started    |Create ARM Package          |Create & Sign ARM .deb installation package                                             |


### RHEL Packaging

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create x86 Package          |Create & Sign x86 .rpm installation package                                             |
|Not Started    |Create x64 Package          |Create & Sign x64 .rpm installation package                                             |
|Not Started    |Create ARM Package          |Create & Sign ARM .rpm installation package                                             |


### CentOS Packaging

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create x86 Package          |Create & Sign x86 .rpm installation package                                             |
|Not Started    |Create x64 Package          |Create & Sign x64 .rpm installation package                                             |
|Not Started    |Create ARM Package          |Create & Sign ARM .rpm installation package                                             |


### Slackware Packaging

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|Not Started    |Create x86 Package          |Create & Sign x86 .tgz installation package                                             |
|Not Started    |Create x64 Package          |Create & Sign x64 .tgz installation package                                             |
|Not Started    |Create ARM Package          |Create & Sign ARM .tgz installation package                                             |

<br>
<br>

## Client System

### Linux Client

<ul>
<li>

#### Core

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Main Client Process         |The primary client application process                                                  |
|Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
|Not Started    |Configuration Save/Import   |Routines to save the client configuration and import an existing config on first setup  |
|Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
|Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
|Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|*In Progress*  |Message Handling            |The routines that parse and generate client/server messages                             |
|Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
|Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |

</li>
</ul>

### macOS Client

<ul>
<li>

#### Core

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Main Client Process         |The primary client application process                                                  |
|Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
|Not Started    |Configuration Save/Import   |Routines to save the client configuration and import an existing config on first setup  |
|Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
|Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
|Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|*In Progress*  |Message Handling            |The routines that parse and generate client/server messages                             |
|Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
|Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |

</li>
</ul>

### Windows Client

<ul>
<li>

#### Core

|Status         |Task                        |Description                                                                             |
|---------------|----------------------------|----------------------------------------------------------------------------------------|
|*In Progress*  |Main Client Process         |The primary client application process                                                  |
|Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
|Not Started    |Configuration Save/Import   |Routines to save the client configuration and import an existing config on first setup  |
|Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
|Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
|Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|*In Progress*  |Message Handling            |The routines that parse and generate client/server messages                             |
|Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
|Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |

</li>
</ul>

<br>
<br>

## Client Modules

### Query

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
</li>

<li>

#### Windows
</li>
</ul>


### Delivery

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
</li>

<li>

#### Windows
</li>
</ul>


### Discovery

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
</li>

<li>

#### Windows
</li>
</ul>


### Efficiency

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
</li>

<li>

#### Windows
</li>
</ul>


### Integrity

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
</li>

<li>

#### Windows
</li>
</ul>


### Inventory

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
</li>

<li>

#### Windows
</li>
</ul>


### Policy

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
</li>

<li>

#### Windows
</li>
</ul>

<br>
<br>

## Core Content

### Sensors

<ul>
<li>

#### Operating System

|Status         |OS |
|---------------|---|
|Not Started    |LIN|
|Not Started    |MAC|
|Not Started    |WIN|
</li>

<li>

#### Uptime

|Status         |OS |
|---------------|---|
|Not Started    |LIN|
|Not Started    |MAC|
|Not Started    |WIN|
</li>

<li>

#### Disk Free Space

|Status         |OS |
|---------------|---|
|Not Started    |LIN|
|Not Started    |MAC|
|Not Started    |WIN|
</li>
</ul>

### Packages

<br>
<br>
