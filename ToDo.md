# Luminum Development To-Do List
In order to be accountable to the community - but more importantly to myself - I figured it would be a good idea to create a to-do list for the project as a quick reference for what's being worked on, what's been accomplished, and what still needs doing. 

## Server Installation
  
### First-Run Setup
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Setup Utility (Text)        |Create plain text step-by-step setup wizard to run when first installed                 |
|&#9654; |*In Progress*  |Setup Utility (ncurses)     |Create ncurses step-by-step setup wizard to run when first installed                    |
|&#10003;|**Completed**  |Language Support            |Multiple language support for the Setup Utility                                         |
|&#9654; |*In Progress*  |German Setup Text           |Setup Utility text translated to German                                                 |
|&#9654; |*In Progress*  |Italian Setup Text          |Setup Utility text translated to Italian                                                |
|&#9654; |*In Progress*  |French Setup Text           |Setup Utility text translated to French                                                 |
|&#9654; |*In Progress*  |Spanish Setup Text          |Setup Utility text translated to Spanish                                                |
| --     |Not Started    |OS User Accounts            |Automatically create necessary OS service accounts for Luminum Server                   |
|&#9654; |*In Progress*  |Detect Installation         |Routines to detect a current existing Luminum Server configuration                      |
|&#9654; |*In Progress*  |Configuration Import        |Routines to import an existing config on first setup                                    |
|&#9654; |*In Progress*  |Certificate Setup           |Routines to create or import server certificates                                        |
|&#9654; |*In Progress*  |Key Setup                   |Routines to create or import public/private keys                                        |
| --     |Not Started    |Database Setup              |Automatically configure the database software and set root password                     |
| --     |Not Started    |Database Structure          |Automatically create Luminum Server databases and tables                                |
| --     |Not Started    |Database User Accounts      |Automatically create database user accounts with permissions                            |
| --     |Not Started    |nginx Configuration         |Routines to automatically configure the nginx webserver software for Luminum            |
| --     |Not Started    |PHP Configuration           |Routines to automatically configure PHP and associated nginx support                    |


### Debian Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|&#9654; |*In Progress*  |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9654; |*In Progress*  |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Server Package              |Create .deb installation package for Luminum Server                                     |
| --     |Not Started    |Core Content Package        |Create .deb installation package for Luminum Core Content                               |


### Ubuntu Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
| --     |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Server Package              |Create .deb installation package for Luminum Server                                     |
| --     |Not Started    |Core Content Package        |Create .deb installation package for Luminum Core Content                               |


### RHEL Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
| --     |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Server Package              |Create .rpm installation package for Luminum Server                                     |
| --     |Not Started    |Core Content Package        |Create .rpm installation package for Luminum Core Content                               |


### CentOS Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
| --     |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Create Server Package       |Create .rpm installation package for Luminum Server                                     |
| --     |Not Started    |Core Content Package        |Create .rpm installation package for Luminum Core Content                               |


### Slackware Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Create Server Package       |Create .txz installation package for Luminum Server                                     |
| --     |Not Started    |Core Content Package        |Create .txz installation package for Luminum Core Content                               |


### Docker
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Create Image                |Create Luminum Server Docker image                                                      |
| --     |Not Started    |Setup Scripts               |Create scripts supporting the installation of a Luminum Server Docker image             |


### Virtual Appliances
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Proxmox                     |Luminum Server virtual machine for Proxmox                                              |
| --     |Not Started    |VirtualBox                  |Luminum Server virtual machine for VirtualBox                                           |
| --     |Not Started    |VMWare                      |Luminum Server virtual machine for VMWare                                               |

<br>
<br>

## Server System
  
### Configuration
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Parameter Functions         |Create functions to set server configuration parameters                                 |
|&#10003;|**Completed**  |DB Configuration Values     |Create key/value pairs for storing primary configuration options in the database        |
|&#10003;|**Completed**  |File Configuration Values   |Create key/value pairs for storing base configuration options in a config file          |
| --     |Not Started    |Configuration Export        |Routines to export and save the server configuration                                    |

<ul>
<li>
  
#### Primary Configuration Options/Values
|        |Status         |Key            |Default Value    |Description                                                                             |
|--------|---------------|---------------|-----------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |SID            |                 |The unique Luminum Server ID                                                            |
|&#10003;|**Completed**  |SKEY           |                 |The server key used by clients to verify association                                    |
|&#10003;|**Completed**  |SSLCERT        |                 |Path to the SSL Certificate to be used by Luminum Server                                |
|&#10003;|**Completed**  |SSLPRVKEY      |                 |Path to the private key associated with SSLCERT                                         |
|&#10003;|**Completed**  |SSLPUBKEY      |                 |Path to the public key associated with SSLCERT                                          |
|&#10003;|**Completed**  |SHOST          |                 |The server's fully-qualified domain name                                                |
|&#10003;|**Completed**  |INSTALLDATE    |                 |Date and time Luminum Server was installed                                              |
|&#10003;|**Completed**  |ENLUMYS        |                 |A comma-separated list of currently enabled Lumys                                       |
|&#10003;|**Completed**  |TARGETCONF     |Enabled          |Action confirmation based on the number of targeted endpoints                           |
|&#10003;|**Completed**  |TCONFTHRESHOLD |250              |Number of targeted endpoints to trigger action confirmation                             |
|&#10003;|**Completed**  |ENDPOINTCOMM   |mqtt             |Method used by the server and clients to communicate                                    |
|&#10003;|**Completed**  |CHECKININT     |5                |The interval (in minutes) at which clients will check in                                |
|&#10003;|**Completed**  |MISSINGAFTER   |90               |Days when the system determines offline clients are missing                             |
|&#10003;|**Completed**  |UTIMEOUT       |15M              |Time a user is inactive before their session is terminated                              |
|&#10003;|**Completed**  |UTIMEOUTWARN   |Enabled          |Warn users 2 minutes before session is terminated for inactivity                        |
|&#10003;|**Completed**  |MINPASS        |8                |Minimum password character length                                                       |
|&#10003;|**Completed**  |COMPLEXPASS    |Disabled         |Enforce password complexity requirements                                                |
|&#10003;|**Completed**  |PCUPPERLOWER   |Disabled         |Upper/Lowercase letters required in passwords                                           |
|&#10003;|**Completed**  |PCLETNUM       |Disabled         |Letters/Numbers required in passwords                                                   |
|&#10003;|**Completed**  |PCSPECIAL      |Disabled         |Special characters required in passwords                                                |
|&#10003;|**Completed**  |2FA            |Optional         |Two-Factor Authentication policy for user accounts                                      |
|&#10003;|**Completed**  |PASSKEYS       |Disabled         |PassKey Support                                                                         |
|&#10003;|**Completed**  |USERLOGGING    |Disabled         |Account-specific server logging                                                         |
|&#10003;|**Completed**  |SENREVS        |5                |Maximum revision history for sensors                                                    |
|&#10003;|**Completed**  |PKGREVS        |5                |Maximum revision history for packages                                                   |
|&#10003;|**Completed**  |INVESTIGATE    |Enabled          |Enable or Disable Luminum Investigate                                                   |
</li>

<li>
  
#### Base Configuration Options/Values
|        |Status         |Key            |Default Value              |Description                                                                      |
|--------|---------------|---------------|---------------------------|---------------------------------------------------------------------------------|
|&#10003;|**Completed**  |SID            |                           |The unique Luminum Server ID                                                     |
|&#10003;|**Completed**  |SVRPATH        |/opt/Luminum/LuminumServer |The installation path for Luminum Server                                         |
|&#10003;|**Completed**  |DBPASS         |                           |The password for the "Luminum" database account                                  |
|&#10003;|**Completed**  |LADDR          |                           |The IP address to be used by the network listener                                |
|&#10003;|**Completed**  |LPORT          |10465                      |Port number for the network listener                                             |
|&#10003;|**Completed**  |WADDR          |                           |The IP address to be used by the HTTPS Web Console                               |
|&#10003;|**Completed**  |WPORT          |443                        |Port number for access to the HTTPS Web Console                                  |

</li>
</ul>

### Communication
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |MQTT Comms                  |Setup and configuration of the MQTT messaging channel                                   |
| --     |Not Started    |Direct Connect Comms        |Setup and configuration of the direct client<->server messaging channel                 |
|&#9654; |*In Progress*  |Message Format              |Develop the specific formatting for client and server messages                          |
| --     |Not Started    |Message Validation          |Validity checking of client/server messages based on signature verification             |
| --     |Not Started    |Message Decompression       |Expand received messages that arrive compressed                                         |
|&#9654; |*In Progress*  |Message Decryption          |Decrypt received messages that arrive encrypted                                         |
| --     |Not Started    |Query Format                |Develop the specific format of server-actionable user information queries               |
| --     |Not Started    |SMTP Server Configuration   |Setup and configuration of SMTP servers to be used by Luminum Server                    |
| --     |Not Started    |SMTP Configuration Test     |Validate SMTP server configurations by performing connection tests                      |


### Broker Process
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Network Listener            |The actual process that opens on a secure network interface to listen for connections   |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse messages from the server and/or endpoints                           |
| --     |Not Started    |Client Certificate          |Attach a requirement for client certificats to the listener process                     |
|&#9654; |*In Progress*  |Lumy Scanning               |Include Lumys based on enabled/disabled state in configuration and file include presence|
|&#9654; |*In Progress*  |Client Onboarding           |Processing for newly-added clients on first report to the server                        |
|&#9654; |*In Progress*  |Client Deactivation         |Processing the removal of clients from the server                                       |
|&#9654; |*In Progress*  |Check-In Processing         |Handle server-side updates on regular client check-ins                                  |
| --     |Not Started    |Action Queueing             |Development of the queue structure for pending queries and actions                      |
| --     |Not Started    |Action Polling              |Development of routines that watch for and then send new queries or actions             |


### Logging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration Changes       |Generate log entries for changes to the system configuration                            |
| --     |Not Started    |Health Check                |Generate log entries for periodic system health checks                                  |
| --     |Not Started    |User sign-in/sign-out       |Generate log entries for instances of user login/logout                                 |
| --     |Not Started    |Invalid Credentials         |Generate log entries for failed login attempts                                          |
| --     |Not Started    |Navigation                  |Generate log entries for user page navigation                                           |
|&#9654; |*In Progress*  |Broker Information          |Generate log entries from broker processing                                             |
| --     |Not Started    |Account Modification        |Generate log entries for user account modifications                                     |
| --     |Not Started    |User Group Modifications    |Generate log entries on the creation or modification of user groups                     |
| --     |Not Started    |Computer Group Modifications|Generate log entries on the creation or modification of computer groups                 |
| --     |Not Started    |Actions                     |Generate log entries for action deployments                                             |
| --     |Not Started    |System Maintenance          |Generate log entries for system maintenance tasks                                       |
| --     |Not Started    |Create/Modify Content       |Generate log entries on the creation or modification of content and content sets        |
| --     |Not Started    |Client Management           |Generate log entries based on Client Management actions                                 |
| --     |Not Started    |Lumy Management             |Generate log entries based on Lumy Management actions                                   |


### User Management
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |User Accounts               |Create structure for storing users in the database                                      |
|&#10003;|**Completed**  |Password Hashing            |Use hashing for stored password data                                                    |
| --     |Not Started    |Enable/Disable Accounts     |Routines for administrators to lock or unlock user accounts                             |
| --     |Not Started    |Account Expiration          |Implement configuration and enforcement of expiration dates for user accounts           |
| --     |Not Started    |Password Change Intervals   |Implement regular forced password change intervals for user accounts                    |
| --     |Not Started    |PassKey Support             |Implement PassKey Support for account logins                                            |
|&#9654; |*In Progress*  |Mandatory Password Change   |Server support for requiring users to change their password on login                    |


### Command-Line Tools
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration Tool          |Set server configuration parameters from the command line                               |
| --     |Not Started    |Query Builder               |Create queries and get answers from the server command line                             |
| --     |Not Started    |Package Delivery            |Deploy packages to endpoints from the server command line                               |


### Investigate
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Real-Time Shell             |Manages connections to specified endpoints offering remote shell access                 |

  
### Content

<ul>
<li>

#### Content Sets
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Content Set Records         |Create structure for recording content sets in the database                             |
| --     |Not Started    |Content Set Management      |Routines for adding/modifying/deleting content sets                                     |
| --     |Not Started    |Category Management         |Routines to manage categories for content sets                                          |
</li>

<li>

#### Sensors
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Database Sensor Storage     |Create structure for storing sensors in the database                                    |
| --     |Not Started    |Sensor Management           |Routines for adding/modifying/deleting sensors                                          |
| --     |Not Started    |Revision Control            |Routines to manage and view previous versions of sensors                                |
</li>

<li>

#### Packages
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Database Package Storage    |Create structure for storing packages in the database                                   |
| --     |Not Started    |Filesystem Package Storage  |Create structure for storing and referencing package files                              |
| --     |Not Started    |Package Management          |Routines for adding/modifying/deleting packages                                         |
| --     |Not Started    |Revision Control            |Routines to manage and view previous versions of packages                               |
</li>
</ul>

### Modules

<ul>
<li>

#### Delivery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Include File                |Create module include for broker process to attach the Delivery Lumy                    |
| --     |Not Started    |Database Structure          |Create and grant permissions to Delivery-specific databases and tables                  |
| --     |Not Started    |Profiles                    |Establish configuration profiles for Delivery deployments                               |
</li>

<li>

#### Discovery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Include File                |Create module include for broker process to attach the Discovery Lumy                   |
| --     |Not Started    |Database Structure          |Create and grant permissions to Discovery-specific databases and tables                 |
| --     |Not Started    |Profiles                    |Establish configuration profiles for Discovery deployments                              |
</li>

<li>

#### Efficiency
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Include File                |Create module include for broker process to attach the Efficiency Lumy                  |
| --     |Not Started    |Database Structure          |Create and grant permissions to Efficiency-specific databases and tables                |
| --     |Not Started    |Profiles                    |Establish configuration profiles for Efficiency deployments                             |
</li>

<li>

#### Integrity
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Include File                |Create module include for broker process to attach the Integrity Lumy                   |
| --     |Not Started    |Database Structure          |Create and grant permissions to Integrity-specific databases and tables                 |
| --     |Not Started    |Profiles                    |Establish configuration profiles for Integrity deployments                              |

</li>

<li>
  
#### Inventory
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Include File                |Create module include for broker process to attach the Inventory Lumy                   |
| --     |Not Started    |Database Structure          |Create and grant permissions to Inventory-specific databases and tables                 |
| --     |Not Started    |OSQuery Integration         |Support for integrating with OSQuery                                                    |
</li>

<li>
  
#### Policy
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Include File                |Create module include for broker process to attach the Policy Lumy                      |
| --     |Not Started    |Database Structure          |Create and grant permissions to Policy-specific databases and tables                    |
| --     |Not Started    |Profiles                    |Establish configuration profiles for Policy deployments                                 |
| --     |Not Started    |Firewall Rules Store        |Create database structure for storing firewall rules on a per-machine basis             |
| --     |Not Started    |IPS/IDS Rules Store         |Create database structure for storing IPS/IDS rules on a per-machine basis              |
</li>
</ul>

<br>
<br>

## Web Console

### Core
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Base UI Framework           |Create the consistent foundational elements for the web user interface                  |
|&#9654; |*In Progress*  |Include Architecture        |Rebuild include system for user interface code block elements                           |
| --     |Not Started    |Stylesheet Consolidation    |Consolidate style definitions and eliminate redundancies                                |
| --     |Not Started    |Table Generation Functions  |Functions to automatically generate HTML tables on-demand                               |
| --     |Not Started    |Form Generation Functions   |Functions to automatically generate HTML forms on-demand                                |
| --     |Not Started    |Element Generation Functions|Functions to automatically generate HTML elements on-demand                             |
|&#10003;|**Completed**  |Invalid Input Highlight     |Create stylesheet definitions highlighting fields with invalid values                   |
|&#9654; |*In Progress*  |Overlay Message             |Display a forced-focus message window above a full-screen overlay                       |
|&#10003;|**Completed**  |Lumy Menus                  |Dynamically inject UI navigation options for enabled Lumy modules                       |
| --     |Not Started    |Asynchronous Content Updates|Routines to update page content without refreshing                                      |
| --     |Not Started    |Dark Mode                   |Create a stylesheet for dark mode                                                       |
| --     |Not Started    |Timezone Support            |Implement system-wide routines to display the time in the user's timezone               |


### Session Management
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Console Login Processing    |Present a login screen and start a session or reject based on credentials               |
|&#10003;|**Completed**  |Session Timeout             |Automatically terminate a user session if left inactive                                 |
|&#9654; |*In Progress*  |Timeout Warning             |Display a timeout warning 2 minutes before automatic inactivity logout                  |
| --     |Not Started    |Two-Factor Authentication   |Capture user sessions and shunt to 2FA validation on login                              |
| --     |Not Started    |Mandatory Password Change   |Capture user sessions and shunt to a change password interface on login                 |
|&#9654; |*In Progress*  |Permissions Adjustments     |Show or hide UI elements/options based on the user's access level                       |


### User Account Settings
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Settings Interface          |Present a user interface to view/modify account details                                 |
| --     |Not Started    |Authenticator 2FA Setup     |Authenticator-based two-factor Authentication setup process for users                   |
| --     |Not Started    |SMS 2FA Setup               |SMS-based two-factor Authentication setup process for users                             |
| --     |Not Started    |Email 2FA Setup             |Email-based two-factor Authentication setup process for users                           |
| --     |Not Started    |PassKey 2FA Setup           |PassKey setup process for users                                                         |
| --     |Not Started    |Password Change             |Implement functions for user-initiated change of password                               |
| --     |Not Started    |Timezone Select             |Implement functions for per-user timezone configuration                                 |


### Administration
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Client Status               |User interface to view/filter and take action against checked-in clients                |
| --     |Not Started    |Missing Clients             |User interface allowing administrators to manage missing clients                        |
|&#10003;|**Completed**  |Scheduled Actions           |Presents a table displaying information about current scheduled actions                 |
|&#10003;|**Completed**  |Action History              |Presents a table displaying information about past actions                              |
| --     |Not Started    |Computer Groups             |Presents a table displaying information about all computer groups                       |


### Content
<ul>
<li>
  
#### Content Sets
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Content Sets                |Presents a table displaying information about system content sets                       |
|&#9654; |*In Progress*  |Create Content Set          |User interface to create content sets                                                   |
| --     |Not Started    |Edit Content Set            |User interface to edit an existing content set                                          |
</li>

<li>

#### Sensors
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Sensor List                 |Presents a table displaying information about all avaialble sensors                     |
|&#9654; |*In Progress*  |Create Sensor               |User interface to create sensors                                                        |
| --     |Not Started    |New Sensor Column Config    |Form elements for splitting sensor output into table columns                            |
| --     |Not Started    |Edit Sensor                 |User interface to edit an existing sensor                                               |
|&#10003;|**Completed**  |Linux Sensor Code Editor    |Browser-based editor with syntax highlighting for languages under Linux                 |
|&#10003;|**Completed**  |macOS Sensor Code Editor    |Browser-based editor with syntax highlighting for languages under macOS                 |
|&#10003;|**Completed**  |Windows Sensor Code Editor  |Browser-based editor with syntax highlighting for languages under Windows               |
</li>

<li>

#### Packages
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Package List                |Presents a table displaying information about all avaialble packages                    |
|&#9654; |*In Progress*  |Create Package              |User interface to create packages                                                       |
| --     |Not Started    |Edit Package                |User interface to edit an existing package                                              |
</li>
</ul>

### System

<ul>
<li>

#### Information
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Luminum Information         |User interface to display general Luminum server information                            |
|&#10003;|**Completed**  |CPU Information             |User interface to display server CPU information                                        |
|&#10003;|**Completed**  |Storage Information         |User interface to display server disk information                                       |
| --     |Not Started    |Memory Information          |User interface to display server memory information                                     |
| --     |Not Started    |Device Information          |User interface to display server connected device information                           |
|&#9654; |*In Progress*  |Network Information         |User interface to display server network interface information                          |
|&#10003;|**Completed**  |User Accounts               |Presents a table displaying information about all user accounts                         |
</li>

<li>

#### Configuration
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |User Management             |User interface for administrators to create/modify user accounts                        |
| --     |Not Started    |User Group Management       |User interface for administrators to create/modify user account groups                  |
|&#9654; |*In Progress*  |General Settings            |User interface for administrators to view/modify general Luminum settings               |
|&#9654; |*In Progress*  |Endpoint Settings           |User interface for administrators to view/modify endpoint settings                      |
|&#9654; |*In Progress*  |Content Settings            |User interface for administrators to view/modify content settings                       |
| --     |Not Started    |Log Settings                |User interface for administrators to configure system logging                           |
| --     |Not Started    |SMTP Settings               |User interface for administrators to configure SMTP servers and settings                |
| --     |Not Started    |Encryption Settings         |User interface for administrators to configure encryption settings                      |
|&#9654; |*In Progress*  |User Login Settings         |User interface for administrators to view/modify user login settings                    |
|&#10003;|**Completed**  |Networking Settings         |User interface for administrators to view/modify server network settings                |
|&#10003;|**Completed**  |Connectivity Status         |Display user interface elements to reflect network connectivity status                  |
| --     |Not Started    |Certificate Settings        |User interface for administrators to view/modify server certificate settings            |
| --     |Not Started    |Authentication Settings     |User interface for administrators to view/modify account authentication settings        |
| --     |Not Started    |Client Management           |User interface for administrators to manage Luminum client software                     |
| --     |Not Started    |Lumy Management             |User interface for administrators to manage Lumy modules                                |
</li>

<li>

#### Maintenance
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Diagnostics Interface       |User interface for administrators to perform various system diagnostics                 |
| --     |Not Started    |Updates Interface           |User interface for administrators to manage Luminum updates                             |
| --     |Not Started    |Outage Interface            |User interface for administrators to manage scheduled/immediate downtime                |
| --     |Not Started    |OS Management               |User interface for administrators to manage the underlying Operating System             |
| --     |Not Started    |Services Interface          |User interface for administrators to manage services on the underlying OS               |
| --     |Not Started    |Log Viewer                  |User interface for administrators to view and manage various system logs                |
</li>
</ul>


### Investigate
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Session Configuration       |User interface for creating an Investigate session                                      |
| --     |Not Started    |Real-Time Shell             |User interface for remote shell access to endpoints                                     |
| --     |Not Started    |Filesystem Browser          |User interface for browsing endpoint filesystems                                        |


### Modules 

<ul>  
<li>

#### Query
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Query Interface             |Present a dynamic user interface for users to construct queries                         |
| --     |Not Started    |Query Data Parsing          |Convert entered data in the query UI to a system-parseable query statement              |
| --     |Not Started    |Query Saving                |Routines to save a query for future use                                                 |
| --     |Not Started    |Query Loading               |Routines to load and ask saved queries                                                  |

</li>

<li>

#### Summary
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration               |User interface to configure Summary sources and destinations                            |
</li>

<li>

#### Delivery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Overview Interface          |Present overview information of the current status of Delivery in the environment       |
| --     |Not Started    |Profile Configuration       |User interface for administrators to create/modify Delivery profiles                    |
</li>

<li>

#### Discovery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Overview Interface          |Present overview information of the current status of Discovery in the environment      |
| --     |Not Started    |Profile Configuration       |User interface for administrators to create/modify Discovery profiles                   |
</li>

<li>

#### Efficiency
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Overview Interface          |Present overview information of the current status of Efficiency in the environment     |
| --     |Not Started    |Profile Configuration       |User interface for administrators to create/modify Efficiency profiles                  |
</li>

<li>

#### Integrity
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Overview Interface          |Present overview information of the current status of Integrity in the environment      |
| --     |Not Started    |Profile Configuration       |User interface for administrators to create/modify Integrity profiles                   |
</li>

<li>
  
#### Inventory
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Overview Interface          |Present overview information of the current status of Inventory in the environment      |
| --     |Not Started    |Configuration               |User interface for administrators to configure Inventory                                |
</li>

<li>

#### Policy
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Overview Interface          |Present overview information of the current status of Policy in the environment         |
| --     |Not Started    |Profile Configuration       |User interface for administrators to create/modify Policy profiles                      |
</li>
</ul>

<br>
<br>

## Client Installation

### Linux Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Setup Utility (Text)        |Create plaintext interface for a step-by-step setup wizard                              |
| --     |Not Started    |Setup Utility (ncurses)     |Create ncurses interface for a step-by-step setup wizard                                |
| --     |Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
| --     |Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
| --     |Not Started    |x86 Client Binaries         |Create x86-compiled client binaries                                                     |
| --     |Not Started    |x64 Client Binaries         |Create x64-compiled client binaries                                                     |
| --     |Not Started    |ARM Client Binaries         |Create ARM-compiled client binaries                                                     |


### macOS Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Setup Utility (Text)        |Create plaintext interface for a step-by-step setup wizard                              |
| --     |Not Started    |Setup Utility (GUI)         |Create grapical step-by-step setup wizard                                               |
| --     |Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
| --     |Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
| --     |Not Started    |Apple Silicon Binaries      |Create client binaries for Apple Silicon                                                |
| --     |Not Started    |Intel Binaries              |Create client binaries for Intel                                                        |
| --     |Not Started    |Universal Binaries          |Create universal client binaries                                                        |


### Windows Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Setup Utility (Text)        |Create plaintext interface for a step-by-step setup wizard                              |
| --     |Not Started    |Setup Utility (GUI)         |Create grapical step-by-step setup wizard                                               |
| --     |Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
| --     |Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
| --     |Not Started    |x86 Client Binaries         |Create x86-compiled client binaries                                                     |
| --     |Not Started    |x64 Client Binaries         |Create x64-compiled client binaries                                                     |
| --     |Not Started    |ARM Client Binaries         |Create ARM-compiled client binaries                                                     |


### Debian Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9654; |*In Progress*  |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Create x86 Package          |Create & Sign x86 .deb installation package                                             |
|&#9654; |*In Progress*  |Create x64 Package          |Create & Sign x64 .deb installation package                                             |
| --     |Not Started    |Create ARM Package          |Create & Sign ARM .deb installation package                                             |


### Ubuntu Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Create x86 Package          |Create & Sign x86 .deb installation package                                             |
| --     |Not Started    |Create x64 Package          |Create & Sign x64 .deb installation package                                             |
| --     |Not Started    |Create ARM Package          |Create & Sign ARM .deb installation package                                             | 


### RHEL Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Create x86 Package          |Create & Sign x86 .rpm installation package                                             |
| --     |Not Started    |Create x64 Package          |Create & Sign x64 .rpm installation package                                             |
| --     |Not Started    |Create ARM Package          |Create & Sign ARM .rpm installation package                                             |


### CentOS Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Create x86 Package          |Create & Sign x86 .rpm installation package                                             |
| --     |Not Started    |Create x64 Package          |Create & Sign x64 .rpm installation package                                             |
| --     |Not Started    |Create ARM Package          |Create & Sign ARM .rpm installation package                                             |


### Slackware Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
| --     |Not Started    |Create x86 Package          |Create & Sign x86 .txz installation package                                             |
| --     |Not Started    |Create x64 Package          |Create & Sign x64 .txz installation package                                             |
| --     |Not Started    |Create ARM Package          |Create & Sign ARM .txz installation package                                             |

<br>
<br>

## Client System

### Linux Client

<ul>
<li>

#### Core
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Main Client Process         |The primary client application process                                                  |
| --     |Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
| --     |Not Started    |Config Save/Import          |Routines to save configuration and import an existing config on first setup             |
| --     |Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
| --     |Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
| --     |Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse and generate client/server messages                                 |
| --     |Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
| --     |Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |
| --     |Not Started    |Message Queueing            |Development of the queue structure for pending messages                                 |
| --     |Not Started    |Message Compression         |Compress message contents before sending                                                |
| --     |Not Started    |Message Encryption          |Encrypt message contents before sending                                                 |

</li>
</ul>

### macOS Client

<ul>
<li>

#### Core
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Main Client Process         |The primary client application process                                                  |
| --     |Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
| --     |Not Started    |Config Save/Import          |Routines to save configuration and import an existing config on first setup             |
| --     |Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
| --     |Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
| --     |Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse and generate client/server messages                                 |
| --     |Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
| --     |Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |
| --     |Not Started    |Message Queueing            |Development of the queue structure for pending messages                                 |
| --     |Not Started    |Message Compression         |Compress message contents before sending                                                |

</li>
</ul>

### Windows Client

<ul>
<li>

#### Core
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Main Client Process         |The primary client application process                                                  |
| --     |Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
| --     |Not Started    |Config Save/Import          |Routines to save configuration and import an existing config on first setup             |
| --     |Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
| --     |Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
| --     |Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse and generate client/server messages                                 |
| --     |Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
| --     |Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |
| --     |Not Started    |Message Queueing            |Development of the queue structure for pending messages                                 |
| --     |Not Started    |Message Compression         |Compress message contents before sending                                                |

</li>
</ul>

<br>
<br>

## Client Modules

### Query
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Query Processing            |Accept, parse, and respond to server-initiated queries                                  |

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
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration               |Options and location for client-side Delivery configuration                             |
| --     |Not Started    |Local Storage               |Client-side storage for software installation information                               |

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
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration               |Options and location for client-side Discovery configuration                            |
| --     |Not Started    |Local Storage               |Client-side storage for scan discovery information                                      |
| --     |Not Started    |Scan Messaging              |Message format for scan discovery information                                           |

<ul>
<li>

#### Linux
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |nmap integration            |Integration with nmap on Linux                                                          |
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |nmap integration            |Integration with nmap on macOS                                                          |
</li>

<li>

#### Windows
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |nmap integration            |Integration with nmap on Windows                                                        |
</li>
</ul>


### Efficiency
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration               |Options and location for client-side Efficiency configuration                           |
| --     |Not Started    |Local Storage               |Client-side storage for endpoint performance information                                |

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |System Profiler Integration |Parsing and storing information from system_profiler                                    |
</li>

<li>

#### Windows
</li>
</ul>


### Integrity

|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Local Storage               |Client-side storage for filesystem information                                          |
|&#9654; |*In Progress*  |Alert Messaging             |Message format for filesystem modification alerts                                       |
| --     |Not Started    |Bulk Alert Transmission     |Message format for sending stored/queued alerts                                         |

<ul>
<li>

#### Linux
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Real Time Monitor           |OS/Kernel hooks to monitor filesystem changes in real time                              |
| --     |Not Started    |Checksum Scanning           |Periodically performs checksum calculations of monitored files                          |
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Real Time Monitor           |OS/Kernel hooks to monitor filesystem changes in real time                              |
| --     |Not Started    |Checksum Scanning           |Periodically performs checksum calculations of monitored files                          |
</li>

<li>

#### Windows
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Real Time Monitor           |OS/Kernel hooks to monitor filesystem changes in real time                              |
| --     |Not Started    |Checksum Scanning           |Periodically performs checksum calculations of monitored files                          |
</li>
</ul>


### Inventory
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration               |Options and location for client-side Inventory configuration                            |
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

|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Configuration               |Options and location for client-side Policy configuration                               |
| --     |Not Started    |YARA Parser                 |Parser for reading and applying YARA-based rulesets                                     |
| --     |Not Started    |Network Inspection Engine   |Engine for inspecting and actioning network traffic                                     |
| --     |Not Started    |File Inspection Engine      |Engine for inspecting and actioning files and contents                                  |
<ul>
<li>
  
#### Linux
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Network Hooking             |OS/Kernel interface for network monitoring/management                                   |
| --     |Not Started    |IDS/IPS Integration         |Create or integrate intrusion detection/prevention systems                              |
| --     |Not Started    |Firewall Management         |Modify on-device firewall rules according to stored configuration                       |
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Network Hooking             |OS/Kernel interface for network monitoring/management                                   |
| --     |Not Started    |IDS/IPS Integration         |Create or integrate intrusion detection/prevention systems                              |
| --     |Not Started    |Firewall Management         |Modify on-device firewall rules according to stored configuration                       |
</li>

<li>
  
#### Windows
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
| --     |Not Started    |Network Hooking             |OS/Kernel interface for network monitoring/management                                   |
| --     |Not Started    |IDS/IPS Integration         |Create or integrate intrusion detection/prevention systems                              |
| --     |Not Started    |Firewall Management         |Modify on-device firewall rules according to stored configuration                       |
</li>
</ul>

<br>
<br>

## Core Content

### Sensors

<ul>
<li>

#### Operating System

|        |Status         |OS |
|--------|---------------|---|
|&#10003;|**Completed**  |LIN|
|&#10003;|**Completed**  |MAC|
| --     |Not Started    |WIN|
</li>

<li>

#### CPU Information

|        |Status         |OS |
|--------|---------------|---|
| --     |Not Started    |LIN|
| --     |Not Started    |MAC|
| --     |Not Started    |WIN|
</li>

<li>

#### Disk Information

|        |Status         |OS |
|--------|---------------|---|
| --     |Not Started    |LIN|
| --     |Not Started    |MAC|
| --     |Not Started    |WIN|
</li>

<li>

#### Memory Information

|        |Status         |OS |
|--------|---------------|---|
| --     |Not Started    |LIN|
| --     |Not Started    |MAC|
| --     |Not Started    |WIN|
</li>

<li>

#### Uptime

|        |Status         |OS |
|--------|---------------|---|
|&#9654; |*In Progress*  |LIN|
|&#10003;|**Completed**  |MAC|
| --     |Not Started    |WIN|
</li>

<li>

#### File Exists

|        |Status         |OS |
|--------|---------------|---|
| --     |Not Started    |LIN|
| --     |Not Started    |MAC|
| --     |Not Started    |WIN|
</li>

<li>

#### Is Virtual

|        |Status         |OS |
|--------|---------------|---|
| --     |Not Started    |LIN|
| --     |Not Started    |MAC|
| --     |Not Started    |WIN|
</li>
</ul>

### Packages

<br>
<br>
