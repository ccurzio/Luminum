# Luminum Development To-Do List
In order to be accountable to the community - but more importantly to myself - I figured it would be a good idea to create a to-do list for the project as a quick reference for what's being worked on, what's been accomplished, and what still needs doing. 

## Server Installation
  
### First-Run Setup
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Setup Utility (Text)        |Create plain text step-by-step setup wizard to run when first installed                 |
|&#9633; |Not Started    |Setup Utility (ncurses)     |Create ncurses step-by-step setup wizard to run when first installed                    |
|&#9633; |Not Started    |OS User Accounts            |Automatically create necessary OS service accounts for Luminum Server                   |
|&#9654; |*In Progress*  |Configuration Save/Import   |Routines to save the server configuration and import an existing config on first setup  |
|&#9654; |*In Progress*  |Certificate Setup           |Routines to create or import server certificates                                        |
|&#9654; |*In Progress*  |Key Setup                   |Routines to create or import public/private keys                                        |
|&#9633; |Not Started    |Database Setup              |Automatically configure the database software and set root password                     |
|&#9633; |Not Started    |Database Structure          |Create Luminum Server databases and tables                                              |
|&#9633; |Not Started    |Database User Accounts      |Create necessary Luminum Server database user accounts and grant permissions            |
|&#9633; |Not Started    |nginx Configuration         |Routines to automatically configure the nginx webserver software for Luminum            |
|&#9633; |Not Started    |Apache Configuration        |Routines to automatically configure the Apache webserver software for Luminum           |
|&#9633; |Not Started    |lighttpd Configuration      |Routines to automatically configure the lighttpd webserver software for Luminum         |
|&#9633; |Not Started    |PHP Configuration           |Routines to configure PHP running under nginx for Luminum                               |


### Web Server Integrations
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |nginx                       |Luminum Server install with web console running on nginx                                |
|&#9633; |Not Started    |Apache                      |Luminum Server install with web console running on Apache httpd                         |
|&#9633; |Not Started    |lighttpd                    |Luminum Server install with web console running on lighttpd                             |


### Debian Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|&#9633; |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create Package              |Create .deb installation package                                                        |


### Ubuntu Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|&#9633; |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create Package              |Create .deb installation package                                                        |


### RHEL Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|&#9633; |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create Package              |Create .rpm installation package                                                        |


### CentOS Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|&#9633; |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create Package              |Create .rpm installation package                                                        |


### Slackware Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Dependency Checking         |Validate that the system has all required dependencies installed                        |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create Package              |Create .txz installation package                                                        |


### Docker
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Create Image                |Create Luminum Server Docker image                                                      |
|&#9633; |Not Started    |Setup Scripts               |Create scripts supporting the installation of a Luminum Server Docker image             |


### Virtual Appliances
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Proxmox                     |Luminum Server virtual machine for Proxmox                                              |
|&#9633; |Not Started    |VirtualBox                  |Luminum Server virtual machine for VirtualBox                                           |
|&#9633; |Not Started    |VMWare                      |Luminum Server virtual machine for VMWare                                               |

<br>
<br>

## Server System
  
### Configuration
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Parameter Functions         |Create functions to set server configuration parameters                                 |
|&#9654; |*In Progress*  |DB Configuration Values     |Create key/value pairs for storing primary configuration options in the database        |
|&#9654; |*In Progress*  |File Configuration Values   |Create key/value pairs for storing base configuration options in a config file          |

<ul>
<li>
  
#### Primary Configuration Options/Values
|        |Status         |Key            |Default Value    |Description                                                                             |
|--------|---------------|---------------|-----------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |SID            |                 |The unique Luminum Server ID                                                            |
|&#9654; |*In Progress*  |SKEY           |                 |The server key used by clients to verify association                                    |
|&#9654; |*In Progress*  |LADDR          |                 |The address of the interface to be used by the network listener                         |
|&#9654; |*In Progress*  |LPORT          |10465            |Port number for the network listener                                                    |
|&#9654; |*In Progress*  |SSLCERT        |                 |Path to the SSL Certificate to be used by Luminum Server                                |
|&#9654; |*In Progress*  |SSLPRVKEY      |                 |Path to the private key associated with SSLCERT                                         |
|&#9654; |*In Progress*  |SSLPUBKEY      |                 |Path to the public key associated with SSLCERT                                          |
|&#9654; |*In Progress*  |PKPASS         |                 |Private key passphrase                                                                  |
|&#9654; |*In Progress*  |SHOST          |                 |The server's fully-qualified domain name                                                |
|&#9654; |*In Progress*  |INSTALLDATE    |                 |Date and time Luminum Server was installed                                              |
|&#10003;|**Completed**  |ENLUMYS        |                 |A comma-separated list of currently enabled Lumys                                       |
|&#9654; |*In Progress*  |TARGETCONF     |Enabled          |Action confirmation based on the number of targeted endpoints                           |
|&#9654; |*In Progress*  |TCONFTHRESHOLD |250              |Number of targeted endpoints to trigger action confirmation                             |
|&#9654; |*In Progress*  |ENDPOINTCOMM   |mqtt             |Method used by the server and clients to communicate                                    |
|&#9654; |*In Progress*  |CHECKININT     |5                |The interval (in minutes) at which clients will check in                                |
|&#9654; |*In Progress*  |MISSINGAFTER   |90               |Days when the system determines offline clients are missing                             |
|&#9654; |*In Progress*  |TIMEOUT        |15M              |Time a user is inactive before their session is terminated                              |
|&#9654; |*In Progress*  |TIMEOUTWARN    |Enabled          |Warn users 2 minutes before session is terminated for inactivity                        |
|&#9654; |*In Progress*  |MINPASS        |8                |Minimum password character length                                                       |
|&#9654; |*In Progress*  |COMPLEXPASS    |Disabled         |Enforce password complexity requirements                                                |
|&#9654; |*In Progress*  |PCUPPERLOWER   |Disabled         |Upper/Lowercase letters required in passwords                                           |
|&#9654; |*In Progress*  |PCLETNUM       |Disabled         |Letters/Numbers required in passwords                                                   |
|&#9654; |*In Progress*  |PCSPECIAL      |Disabled         |Special characters required in passwords                                                |
|&#9654; |*In Progress*  |2FA            |Optional         |Two-Factor Authentication policy for user accounts                                      |
|&#9633; |Not Started    |PASSKEYS       |Disabled         |PassKey Support                                                                         |
|&#9633; |Not Started    |USERLOGLVL     |Disabled         |Account-specific log levels                                                             |
|&#9654; |*In Progress*  |SENREVS        |5                |Maximum revision history for sensors                                                    |
|&#9654; |*In Progress*  |PKGREVS        |5                |Maximum revision history for packages                                                   |
|&#9633; |Not Started    |INVESTIGATE    |Enabled          |Enable or Disable Luminum Investigate                                                   |
</li>

<li>
  
#### Base Configuration Options/Values
|        |Status         |Key            |Default Value    |Description                                                                             |
|--------|---------------|---------------|-----------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |SID            |                 |The unique Luminum Server ID                                                            |
|  --    |*DEPRECATED*   |~~SKEY~~       |                 |~~The server key used by clients to verify association~~                                |
|  --    |*DEPRECATED*   |~~IPADDR~~     |                 |~~The address of the interface to be used by the network listener~~                     |
|  --    |*DEPRECATED*   |~~PORT~~       |                 |~~Port number for the network listener~~                                                |
|&#10003;|**Completed**  |DBPASS         |                 |The password for the "Luminum" database account                                         |
|  --    |*DEPRECATED*   |~~PKPASS~~     |                 |~~The passphrase for the server's private key~~                                         |

</li>
</ul>

### Communication
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |MQTT Comms                  |Setup and configuration of the MQTT messaging channel                                   |
|&#9633; |Not Started    |Direct Connect Comms        |Setup and configuration of the direct client<->server messaging channel                 |
|&#9654; |*In Progress*  |Message Format              |Develop the specific formatting for client and server messages                          |
|&#9633; |Not Started    |Message Validation          |Validity checking of client/server messages based on signature verification             |
|&#9633; |Not Started    |Message Decompression       |Expand received messages that arrive compressed                                         |
|&#9654; |*In Progress*  |Message Decryption          |Decrypt received messages that arrive encrypted                                         |
|&#9633; |Not Started    |Query Format                |Develop the specific format of server-actionable user information queries               |
|&#9633; |Not Started    |SMTP Server Configuration   |Setup and configuration of SMTP servers to be used by Luminum Server                    |
|&#9633; |Not Started    |SMTP Configuration Test     |Validate SMTP server configurations by performing connection tests                      |


### Broker Process
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Network Listener            |The actual process that opens on a secure network interface to listen for connections   |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse messages from the server and/or endpoints                           |
|&#9633; |Not Started    |Client Certificate          |Attach a requirement for client certificats to the listener process                     |
|&#9654; |*In Progress*  |Lumy Scanning               |Include Lumys based on enabled/disabled state in configuration and file include presence|
|&#9654; |*In Progress*  |Client Onboarding           |Processing for newly-added clients on first report to the server                        |
|&#9654; |*In Progress*  |Client Deactivation         |Processing the removal of clients from the server                                       |
|&#9654; |*In Progress*  |Check-In Processing         |Handle server-side updates on regular client check-ins                                  |
|&#9633; |Not Started    |Action Queueing             |Development of the queue structure for pending queries and actions                      |
|&#9633; |Not Started    |Action Polling              |Development of routines that watch for and then send new queries or actions             |


### Logging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Configuration Changes       |Generate log entries for changes to the system configuration                            |
|&#9633; |Not Started    |User sign-in/sign-out       |Generate log entries for instances of user login/logout                                 |
|&#9633; |Not Started    |Invalid Credentials         |Generate log entries for failed login attempts                                          |
|&#9633; |Not Started    |Navigation                  |Generate log entries for user page navigation                                           |
|&#9654; |*In Progress*  |Broker Information          |Generate log entries from broker processing                                             |
|&#9633; |Not Started    |Account Modification        |Generate log entries for user account modifications                                     |
|&#9633; |Not Started    |User Group Modifications    |Generate log entries on the creation or modification of user groups                     |
|&#9633; |Not Started    |Computer Group Modifications|Generate log entries on the creation or modification of computer groups                 |
|&#9633; |Not Started    |Actions                     |Generate log entries for action deployments                                             |
|&#9633; |Not Started    |System Maintenance          |Generate log entries for system maintenance tasks                                       |
|&#9633; |Not Started    |Create/Modify Content       |Generate log entries on the creation or modification of content and content sets        |
|&#9633; |Not Started    |Client Management           |Generate log entries based on Client Management actions                                 |
|&#9633; |Not Started    |Lumy Management             |Generate log entries based on Lumy Management actions                                   |


### User Management
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |User Accounts               |Create structure for storing users in the database                                      |
|&#10003;|**Completed**  |Password Hashing            |Use hashing for stored password data                                                    |
|&#9633; |Not Started    |Enable/Disable Accounts     |Routines for administrators to lock or unlock user accounts                             |
|&#9633; |Not Started    |Account Expiration          |Implement configuration and enforcement of expiration dates for user accounts           |
|&#9633; |Not Started    |Password Change Intervals   |Implement regular forced password change intervals for user accounts                    |
|&#9633; |Not Started    |PassKey Support             |Implement PassKey Support for account logins                                            |
|&#9654; |*In Progress*  |Mandatory Password Change   |Server support for requiring users to change their password on login                    |


### Investigate
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Real-Time Shell             |Manages connections to specified endpoints offering remote shell access                 |

  
### Content

<ul>
<li>

#### Content Sets
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Content Set Records         |Create structure for recording content sets in the database                             |
|&#9633; |Not Started    |Content Set Management      |Routines for adding/modifying/deleting content sets                                     |
|&#9633; |Not Started    |Category Management         |Routines to manage categories for content sets                                          |
</li>

<li>

#### Sensors
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Database Sensor Storage     |Create structure for storing sensors in the database                                    |
|&#9633; |Not Started    |Sensor Management           |Routines for adding/modifying/deleting sensors                                          |
|&#9633; |Not Started    |Revision Control            |Routines to manage and view previous versions of sensors                                |
</li>

<li>

#### Packages
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Database Package Storage    |Create structure for storing packages in the database                                   |
|&#9633; |Not Started    |Filesystem Package Storage  |Create structure for storing and referencing package files                              |
|&#9633; |Not Started    |Package Management          |Routines for adding/modifying/deleting packages                                         |
|&#9633; |Not Started    |Revision Control            |Routines to manage and view previous versions of packages                               |
</li>
</ul>

### Modules

<ul>
<li>

#### Delivery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Include File                |Create module include for broker process to attach the Delivery Lumy                    |
|&#9633; |Not Started    |Database Structure          |Create and grant permissions to Delivery-specific databases and tables                  |
|&#9633; |Not Started    |Profiles                    |Establish configuration profiles for Delivery deployments                               |
</li>

<li>

#### Discovery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Include File                |Create module include for broker process to attach the Discovery Lumy                   |
|&#9633; |Not Started    |Database Structure          |Create and grant permissions to Discovery-specific databases and tables                 |
|&#9633; |Not Started    |Profiles                    |Establish configuration profiles for Discovery deployments                              |
</li>

<li>

#### Efficiency
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Include File                |Create module include for broker process to attach the Efficiency Lumy                  |
|&#9633; |Not Started    |Database Structure          |Create and grant permissions to Efficiency-specific databases and tables                |
|&#9633; |Not Started    |Profiles                    |Establish configuration profiles for Efficiency deployments                             |
</li>

<li>

#### Integrity
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Include File                |Create module include for broker process to attach the Integrity Lumy                   |
|&#9633; |Not Started    |Database Structure          |Create and grant permissions to Integrity-specific databases and tables                 |
|&#9633; |Not Started    |Profiles                    |Establish configuration profiles for Integrity deployments                              |

</li>

<li>
  
#### Inventory
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Include File                |Create module include for broker process to attach the Integrity Lumy                   |
|&#9633; |Not Started    |Database Structure          |Create and grant permissions to Inventory-specific databases and tables                 |
|&#9633; |Not Started    |OSQuery Integration         |Support for integrating with OSQuery                                                    |
</li>

<li>
  
#### Policy
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Include File                |Create module include for broker process to attach the Policy Lumy                      |
|&#9633; |Not Started    |Database Structure          |Create and grant permissions to Policy-specific databases and tables                    |
|&#9633; |Not Started    |Profiles                    |Establish configuration profiles for Policy deployments                                 |
|&#9633; |Not Started    |Firewall Rules Store        |Create database structure for storing firewall rules on a per-machine basis             |
|&#9633; |Not Started    |IPS/IDS Rules Store         |Create database structure for storing IPS/IDS rules on a per-machine basis              |
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
|&#9633; |Not Started    |Stylesheet Consolidation    |Consolidate style definitions and eliminate redundancies                                |
|&#10003;|**Completed**  |Invalid Input Highlight     |Create stylesheet definitions highlighting fields with invalid values                   |
|&#9633; |Not Started    |Table Generation Functions  |Functions to automatically generate HTML tables on-demand                               |
|&#9633; |Not Started    |Form Generation Functions   |Functions to automatically generate HTML forms on-demand                                |
|&#9633; |Not Started    |Element Generation Functions|Functions to automatically generate HTML elements on-demand                             |
|&#9654; |*In Progress*  |Overlay Message             |Display a forced-focus message window above a full-screen overlay                       |
|&#10003;|**Completed**  |Lumy Menus                  |Dynamically inject UI navigation options for enabled Lumy modules                       |
|&#9633; |Not Started    |Asynchronous Content Updates|Routines to update page content without refreshing                                      |

### Session Management
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Console Login Processing    |Present a login screen and start a session or reject based on credentials               |
|&#10003;|**Completed**  |Session Timeout             |Automatically terminate a user session if left inactive                                 |
|&#9654; |*In Progress*  |Timeout Warning             |Display a timeout warning 2 minutes before automatic inactivity logout                  |
|&#9633; |Not Started    |Two-Factor Authentication   |Capture user sessions and shunt to 2FA validation on login                              |
|&#9633; |Not Started    |Mandatory Password Change   |Capture user sessions and shunt to a change password interface on login                 |
|&#9654; |*In Progress*  |Permissions Adjustments     |Show or hide UI elements/options based on the user's access level                       |


### User Account Settings
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Settings Interface          |Present a user interface to view/modify account details                                 |
|&#9633; |Not Started    |Authenticator 2FA Setup     |Authenticator-based two-factor Authentication setup process for users                   |
|&#9633; |Not Started    |SMS 2FA Setup               |SMS-based two-factor Authentication setup process for users                             |
|&#9633; |Not Started    |Email 2FA Setup             |Email-based two-factor Authentication setup process for users                           |
|&#9633; |Not Started    |PassKey 2FA Setup           |PassKey setup process for users                                                         |
|&#9633; |Not Started    |Password Change             |Implement functions for user-initiated change of password                               |


### Administration
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Client Status               |User interface to view/filter and take action against checked-in clients                |
|&#9633; |Not Started    |Missing Clients             |User interface allowing administrators to manage missing clients                        |
|&#10003;|**Completed**  |Scheduled Actions           |Presents a table displaying information about current scheduled actions                 |
|&#10003;|**Completed**  |Action History              |Presents a table displaying information about past actions                              |
|&#9633; |Not Started    |Computer Groups             |Presents a table displaying information about all computer groups                       |

### Content 

<ul>
<li>
  
#### Content Sets
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Content Sets                |Presents a table displaying information about system content sets                       |
|&#9654; |*In Progress*  |Create Content Set          |User interface to create content sets                                                   |
|&#9633; |Not Started    |Edit Content Set            |User interface to edit an existing content set                                          |
</li>

<li>

#### Sensors
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#10003;|**Completed**  |Sensor List                 |Presents a table displaying information about all avaialble sensors                     |
|&#9654; |*In Progress*  |Create Sensor               |User interface to create sensors                                                        |
|&#9633; |Not Started    |New Sensor Column Config    |Form elements for splitting sensor output into table columns                            |
|&#9633; |Not Started    |Edit Sensor                 |User interface to edit an existing sensor                                               |
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
|&#9633; |Not Started    |Edit Package                |User interface to edit an existing package                                              |
</li>
</ul>

### System

<ul>
<li>

#### Information
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Luminum Information         |User interface to display general Luminum server information                            |
|&#10003;|**Completed**  |CPU Information             |User interface to display server CPU information                                        |
|&#9654; |*In Progress*  |Storage Information         |User interface to display server disk information                                       |
|&#9633; |Not Started    |Memory Information          |User interface to display server memory information                                     |
|&#9633; |Not Started    |Device Information          |User interface to display server connected device information                           |
|&#9633; |Not Started    |Network Information         |User interface to display server network interface information                          |
|&#10003;|**Completed**  |User Accounts               |Presents a table displaying information about all user accounts                         |
</li>

<li>

#### Configuration
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |User Management             |User interface for administrators to create/modify user accounts                        |
|&#9633; |Not Started    |User Group Management       |User interface for administrators to create/modify user account groups                  |
|&#9654; |*In Progress*  |General Settings            |User interface for administrators to view/modify general Luminum settings               |
|&#9654; |*In Progress*  |Endpoint Settings           |User interface for administrators to view/modify endpoint settings                      |
|&#9654; |*In Progress*  |Content Settings            |User interface for administrators to view/modify content settings                       |
|&#9633; |Not Started    |Log Settings                |User interface for administrators to configure system logging                           |
|&#9633; |Not Started    |SMTP Settings               |User interface for administrators to configure SMTP servers and settings                |
|&#9633; |Not Started    |Encryption Settings         |User interface for administrators to configure encryption settings                      |
|&#9654; |*In Progress*  |User Login Settings         |User interface for administrators to view/modify user login settings                    |
|&#9654; |*In Progress*  |Networking Settings         |User interface for administrators to view/modify server network settings                |
|&#9633; |Not Started    |Certificate Settings        |User interface for administrators to view/modify server certificate settings            |
|&#9633; |Not Started    |Authentication Settings     |User interface for administrators to view/modify account authentication settings        |
|&#9633; |Not Started    |Client Management           |User interface for administrators to manage Luminum client software                     |
|&#9633; |Not Started    |Lumy Management             |User interface for administrators to manage Lumy modules                                |
</li>

<li>

#### Maintenance
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Diagnostics Interface       |User interface for administrators to perform various system diagnostics                 |
|&#9633; |Not Started    |Updates Interface           |User interface for administrators to manage Luminum updates                             |
|&#9633; |Not Started    |Outage Interface            |User interface for administrators to manage scheduled/immediate downtime                |
|&#9633; |Not Started    |OS Management               |User interface for administrators to manage the underlying Operating System             |
|&#9633; |Not Started    |Services Interface          |User interface for administrators to manage services on the underlying OS               |
|&#9633; |Not Started    |Log Viewer                  |User interface for administrators to view and manage various system logs                |
</li>
</ul>


### Investigate
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Session Configuration       |User interface for creating an Investigate session                                      |
|&#9633; |Not Started    |Real-Time Shell             |User interface for remote shell access to endpoints                                     |
|&#9633; |Not Started    |Filesystem Browser          |User interface for browsing endpoint filesystems                                        |


### Modules 

<ul>  
<li>

#### Query
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Query Interface             |Present a dynamic user interface for users to construct queries                         |
|&#9633; |Not Started    |Question Summary            |Convert entered data in the query UI to a human-readable summary                        |
|&#9633; |Not Started    |Query Data Parsing          |Convert entered data in the query UI to a system-parseable query statement              |
</li>

<li>

#### Summary
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Configuration               |User interface to configure Summary sources and destinations                            |
</li>

<li>

#### Delivery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Overview Interface          |Present overview information of the current status of Delivery in the environment       |
|&#9633; |Not Started    |Profile Configuration       |User interface for administrators to create/modify Delivery profiles                    |
</li>

<li>

#### Discovery
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Overview Interface          |Present overview information of the current status of Discovery in the environment      |
|&#9633; |Not Started    |Profile Configuration       |User interface for administrators to create/modify Discovery profiles                   |
</li>

<li>

#### Efficiency
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Overview Interface          |Present overview information of the current status of Efficiency in the environment     |
|&#9633; |Not Started    |Profile Configuration       |User interface for administrators to create/modify Efficiency profiles                  |
</li>

<li>

#### Integrity
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Overview Interface          |Present overview information of the current status of Integrity in the environment      |
|&#9633; |Not Started    |Profile Configuration       |User interface for administrators to create/modify Integrity profiles                   |
</li>

<li>
  
#### Inventory
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Overview Interface          |Present overview information of the current status of Inventory in the environment      |
|&#9633; |Not Started    |Configuration               |User interface for administrators to configure Inventory                                |
</li>

<li>

#### Policy
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Overview Interface          |Present overview information of the current status of Policy in the environment         |
|&#9633; |Not Started    |Profile Configuration       |User interface for administrators to create/modify Policy profiles                      |
</li>
</ul>

<br>
<br>

## Client Installation

### Linux Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Setup Utility (Text)        |Create plaintext interface for a step-by-step setup wizard                              |
|&#9633; |Not Started    |Setup Utility (ncurses)     |Create ncurses interface for a step-by-step setup wizard                                |
|&#9633; |Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
|&#9633; |Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
|&#9633; |Not Started    |x86 Client Binaries         |Create x86-compiled client binaries                                                     |
|&#9633; |Not Started    |x64 Client Binaries         |Create x64-compiled client binaries                                                     |
|&#9633; |Not Started    |ARM Client Binaries         |Create ARM-compiled client binaries                                                     |


### macOS Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Setup Utility (Text)        |Create plaintext interface for a step-by-step setup wizard                              |
|&#9633; |Not Started    |Setup Utility (GUI)         |Create grapical step-by-step setup wizard                                               |
|&#9633; |Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
|&#9633; |Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
|&#9633; |Not Started    |Apple Silicon Binaries      |Create client binaries for Apple Silicon                                                |
|&#9633; |Not Started    |Intel Binaries              |Create client binaries for Intel                                                        |
|&#9633; |Not Started    |Universal Binaries          |Create universal client binaries                                                        |


### Windows Support
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Setup Utility (Text)        |Create plaintext interface for a step-by-step setup wizard                              |
|&#9633; |Not Started    |Setup Utility (GUI)         |Create grapical step-by-step setup wizard                                               |
|&#9633; |Not Started    |Unattended Install          |Create automated process for unattended installation                                    |
|&#9633; |Not Started    |Key Management              |Routines to create a new public/private key pair                                        |
|&#9633; |Not Started    |x86 Client Binaries         |Create x86-compiled client binaries                                                     |
|&#9633; |Not Started    |x64 Client Binaries         |Create x64-compiled client binaries                                                     |
|&#9633; |Not Started    |ARM Client Binaries         |Create ARM-compiled client binaries                                                     |


### Debian Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9654; |*In Progress*  |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create x86 Package          |Create & Sign x86 .deb installation package                                             |
|&#9654; |*In Progress*  |Create x64 Package          |Create & Sign x64 .deb installation package                                             |
|&#9633; |Not Started    |Create ARM Package          |Create & Sign ARM .deb installation package                                             |


### Ubuntu Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create x86 Package          |Create & Sign x86 .deb installation package                                             |
|&#9633; |Not Started    |Create x64 Package          |Create & Sign x64 .deb installation package                                             |
|&#9633; |Not Started    |Create ARM Package          |Create & Sign ARM .deb installation package                                             | 


### RHEL Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create x86 Package          |Create & Sign x86 .rpm installation package                                             |
|&#9633; |Not Started    |Create x64 Package          |Create & Sign x64 .rpm installation package                                             |
|&#9633; |Not Started    |Create ARM Package          |Create & Sign ARM .rpm installation package                                             |


### CentOS Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Pre-Install                 |Create package script to run on package installation prior to copying files into place  |
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create x86 Package          |Create & Sign x86 .rpm installation package                                             |
|&#9633; |Not Started    |Create x64 Package          |Create & Sign x64 .rpm installation package                                             |
|&#9633; |Not Started    |Create ARM Package          |Create & Sign ARM .rpm installation package                                             |


### Slackware Packaging
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Post-Install                |Create package script to run on package installation after copying files into place     |
|&#9633; |Not Started    |Create x86 Package          |Create & Sign x86 .txz installation package                                             |
|&#9633; |Not Started    |Create x64 Package          |Create & Sign x64 .txz installation package                                             |
|&#9633; |Not Started    |Create ARM Package          |Create & Sign ARM .txz installation package                                             |

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
|&#9633; |Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
|&#9633; |Not Started    |Config Save/Import          |Routines to save configuration and import an existing config on first setup             |
|&#9633; |Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
|&#9633; |Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
|&#9633; |Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse and generate client/server messages                                 |
|&#9633; |Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
|&#9633; |Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |
|&#9633; |Not Started    |Message Queueing            |Development of the queue structure for pending messages                                 |
|&#9633; |Not Started    |Message Compression         |Compress message contents before sending                                                |
|&#9633; |Not Started    |Message Encryption          |Encrypt message contents before sending                                                 |

</li>
</ul>

### macOS Client

<ul>
<li>

#### Core
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Main Client Process         |The primary client application process                                                  |
|&#9633; |Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
|&#9633; |Not Started    |Config Save/Import          |Routines to save configuration and import an existing config on first setup             |
|&#9633; |Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
|&#9633; |Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
|&#9633; |Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse and generate client/server messages                                 |
|&#9633; |Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
|&#9633; |Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |
|&#9633; |Not Started    |Message Queueing            |Development of the queue structure for pending messages                                 |
|&#9633; |Not Started    |Message Compression         |Compress message contents before sending                                                |

</li>
</ul>

### Windows Client

<ul>
<li>

#### Core
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Main Client Process         |The primary client application process                                                  |
|&#9633; |Not Started    |Parameter Functions         |Create functions to set client configuration parameters                                 |
|&#9633; |Not Started    |Config Save/Import          |Routines to save configuration and import an existing config on first setup             |
|&#9633; |Not Started    |Service Management          |Routines to register the client as a service with the host operating system             |
|&#9633; |Not Started    |Tamper Protection           |Configure the operating system to secure the client against user access                 |
|&#9633; |Not Started    |Sanctioned Uninstall        |Routines to validate permission to uninstall the client against the server              |
|&#9654; |*In Progress*  |Message Handling            |Routines that parse and generate client/server messages                                 |
|&#9633; |Not Started    |Sensor Processing           |Routines to execute sensor scripts and collect the output                               |
|&#9633; |Not Started    |Package Processing          |Routines to store packages and execute embedded commands                                |
|&#9633; |Not Started    |Message Queueing            |Development of the queue structure for pending messages                                 |
|&#9633; |Not Started    |Message Compression         |Compress message contents before sending                                                |

</li>
</ul>

<br>
<br>

## Client Modules

### Query
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Query Processing            |Accept, parse, and respond to server-initiated queries                                  |

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
|&#9633; |Not Started    |Configuration               |Options and location for client-side Delivery configuration                             |
|&#9633; |Not Started    |Local Storage               |Client-side storage for software installation information                               |

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
|&#9633; |Not Started    |Configuration               |Options and location for client-side Discovery configuration                            |
|&#9633; |Not Started    |Local Storage               |Client-side storage for scan discovery information                                      |
|&#9633; |Not Started    |Scan Messaging              |Message format for scan discovery information                                           |

<ul>
<li>

#### Linux
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |nmap integration            |Integration with nmap on Linux                                                          |
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |nmap integration            |Integration with nmap on macOS                                                          |
</li>

<li>

#### Windows
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |nmap integration            |Integration with nmap on Windows                                                        |
</li>
</ul>


### Efficiency
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Configuration               |Options and location for client-side Efficiency configuration                           |
|&#9633; |Not Started    |Local Storage               |Client-side storage for endpoint performance information                                |

<ul>
<li>

#### Linux
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |System Profiler Integration |Parsing and storing information from system_profiler                                    |
</li>

<li>

#### Windows
</li>
</ul>


### Integrity

|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Local Storage               |Client-side storage for filesystem information                                          |
|&#9654; |*In Progress*  |Alert Messaging             |Message format for filesystem modification alerts                                       |
|&#9633; |Not Started    |Bulk Alert Transmission     |Message format for sending stored/queued alerts                                         |

<ul>
<li>

#### Linux
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Real Time Monitor           |OS/Kernel hooks to monitor filesystem changes in real time                              |
|&#9633; |Not Started    |Checksum Scanning           |Periodically performs checksum calculations of monitored files                          |
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Real Time Monitor           |OS/Kernel hooks to monitor filesystem changes in real time                              |
|&#9633; |Not Started    |Checksum Scanning           |Periodically performs checksum calculations of monitored files                          |
</li>

<li>

#### Windows
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9654; |*In Progress*  |Real Time Monitor           |OS/Kernel hooks to monitor filesystem changes in real time                              |
|&#9633; |Not Started    |Checksum Scanning           |Periodically performs checksum calculations of monitored files                          |
</li>
</ul>


### Inventory
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Configuration               |Options and location for client-side Inventory configuration                            |
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
|&#9633; |Not Started    |Configuration               |Options and location for client-side Policy configuration                               |
|&#9633; |Not Started    |YAML Parser                 |Parser for reading and applying YAML-based rulesets                                     |
<ul>
<li>
  
#### Linux
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Network Hooking             |OS/Kernel interface for network monitoring/management                                   |
|&#9633; |Not Started    |IDS/IPS Integration         |Create or integrate intrusion detection/prevention systems                              |
|&#9633; |Not Started    |Firewall Management         |Modify on-device firewall rules according to stored configuration                       |
</li>

<li>

#### macOS
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Network Hooking             |OS/Kernel interface for network monitoring/management                                   |
|&#9633; |Not Started    |IDS/IPS Integration         |Create or integrate intrusion detection/prevention systems                              |
|&#9633; |Not Started    |Firewall Management         |Modify on-device firewall rules according to stored configuration                       |
</li>

<li>
  
#### Windows
|        |Status         |Task                        |Description                                                                             |
|--------|---------------|----------------------------|----------------------------------------------------------------------------------------|
|&#9633; |Not Started    |Network Hooking             |OS/Kernel interface for network monitoring/management                                   |
|&#9633; |Not Started    |IDS/IPS Integration         |Create or integrate intrusion detection/prevention systems                              |
|&#9633; |Not Started    |Firewall Management         |Modify on-device firewall rules according to stored configuration                       |
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
|&#9633; |Not Started    |WIN|
</li>

<li>

#### CPU Information

|        |Status         |OS |
|--------|---------------|---|
|&#9633; |Not Started    |LIN|
|&#9633; |Not Started    |MAC|
|&#9633; |Not Started    |WIN|
</li>

<li>

#### Disk Information

|        |Status         |OS |
|--------|---------------|---|
|&#9633; |Not Started    |LIN|
|&#9633; |Not Started    |MAC|
|&#9633; |Not Started    |WIN|
</li>

<li>

#### Memory Information

|        |Status         |OS |
|--------|---------------|---|
|&#9633; |Not Started    |LIN|
|&#9633; |Not Started    |MAC|
|&#9633; |Not Started    |WIN|
</li>

<li>

#### Uptime

|        |Status         |OS |
|--------|---------------|---|
|&#9654; |*In Progress*  |LIN|
|&#10003;|**Completed**  |MAC|
|&#9633; |Not Started    |WIN|
</li>

<li>

#### File Exists

|        |Status         |OS |
|--------|---------------|---|
|&#9633; |Not Started    |LIN|
|&#9633; |Not Started    |MAC|
|&#9633; |Not Started    |WIN|
</li>
</ul>

### Packages

<br>
<br>
