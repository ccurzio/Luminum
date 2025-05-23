# Luminum
**Autonomous Endpoint Security &amp; Management**  
Christopher R. Curzio

## Introduction
Welcome to the Luminum project. Luminum is intended to be an open-source autonomous endpoint security and management system with a focus on security and high performance with a small overall footprint. Luminum is being developed primarily in the [Rust Programming Language](https://www.rust-lang.org/) for the endpoint clients, with the server components utilizing a combination of [Perl](https://www.perl.org/) and [PHP](https://www.php.net/). 

## Capabilities
Keep in mind that Luminum is still in the initial development stages, so it doesn't really do anything yet. But the goal is to provide a range of extensible endpoint security and management functionality through the base server/client software plus modular components called Lumys.

Core features:
- **Rapid Data Retrieval:** Luminum allows administrators and users to quickly pull information from endpoints simply by constructing questions. You ask the environment for information, and any endpoints with relevent information will answer your questions.
- **Action Deployment:** Use the answers provided by endpoints to generate specific targeting for packages. Want to deploy a package to all machines running a specific operating system with a specific piece of software installed? Ask the environment for those conditions then target the result set with your package. Luminum handles the rest. Want to schedule those actions to run at regular intervals? You can do that too.
- **Custom Sensors:** Many environments will have custom requirements for the types of information they need to get from their endpoints. Out-of-the-box sensors are great, but Luminum also allows you to create your own sensors as well.
- **Web Interface:** Luminum Server provides an intuitive web interface for endpoint and server configuration and management. 

The current planned Lumy modules include:
- **Query:** The core module of the system which allows administrators and users to retrieve data from endpoints
- **Summary:** Automatically report query result data in specified intervals to various logging, reporting, and communication systems
- **Delivery:** Deploys applications to endpoints and provides application installation management
- **Discovery:** Performs network scanning from the server as well as endpoints to discover devices and running services
- **Integrity:** Provides file integrity monitoring on endpoints
- **Efficiency:** Analyzes and logs various aspects of endpoint performance
- **Inventory:** Allows administrators to compile a full inventory of both network-connected devices as well as software installed on those devices
- **Policy:** Enforcement of endpoint security and system management policies

The server component is currently set up to be packaged properly for Debian Linux. The endpoint client will run on a range of operating systems and platforms including Linux (Debian, CentOS/Red Hat, Slackware, etc.), Windows, and macOS. AIX support is also planned (eventually). 

## Development
Right now I'm working on this thing by myself, but I certainly welcome community support from anyone who wants to chip in. There's no real timeline or roadmap beyond what's included here, however the goal is to provide a secure, complete, lightweight, and robust endpoint security and management solution that can scale from the smallest home networks up to the largest enterprise networks. 

## About
- **Luminum:** The name comes from both the chemical element Aluminum (Al) - a strong yet lightweight metal, as well as the concept of shining light into dark areas, or to "illuminate." Which is always what decent technology teams should want to do with their infrastructure. 
- **ccurzio:** My name is Christopher Curzio. I'm originally from New York City, but I currently live in the Atlanta area. I've been a security engineer for around 25 years. I love my current job and I bang on computer machines in a security capacity for a great little company you may have heard of called American Express. However please note that *neither American Express nor any of its subsidiaries is affiliated with the Luminum project in any way, shape, or form.* I develop Luminum entirely in my free time using my own personal equipment. Lord knows I have more than enough in the way of computers and network gear to handle it. I'm a Mac guy for my day-to-day, but when it comes to servers I'm first and foremost a Slackware Linux guy - though I have warmed up a lot to Debian over the past few years. I also code stuff for iOS. (Are you a film photographer by any chance? Maybe check out [MetaLog](https://apps.apple.com/us/app/metalog/id1475309518) if you're so inclined.)
