Clusters
PowerShell scripts for administering, migrating, validating, and troubleshooting Windows Server Failover Clusters (WSFC).

This repository contains scripts developed to automate common cluster configuration tasks, reduce manual effort, and provide consistent deployment standards across clustered environments.

Features
Cluster network configuration
Heartbeat network management
Cluster network renaming
Static route configuration
IP address migration
DNS validation and testing
Cluster health validation
Automated safeguards and error handling
Deployment-ready functions suitable for MECM task sequences
Use Cases
Heartbeat Network Migration
Scripts to assist with migrating cluster heartbeat traffic from stretched Layer 2 networks to routed Layer 3 networks.

Typical activities include:

Enabling and disabling heartbeat adapters
Moving IP configuration between adapters
Configuring routing between heartbeat networks
Updating cluster network settings
Validating connectivity between cluster nodes
Cluster Network Standardisation
Automates:

Network renaming
Interface configuration
DNS-based configuration lookups
Validation of existing cluster settings before making changes
Post-Deployment Validation
Validation functions can be used to confirm:

DNS resolution
ICMP connectivity
Cluster service status
Cluster network availability
Heartbeat communication paths
Design Principles
The scripts in this repository follow several key principles:

Safety first
Idempotent where possible
Extensive validation before changes
Detailed logging and diagnostics
Suitable for automated deployment pipelines
Fail fast if baseline configuration has drifted
Requirements
Windows Server Failover Clustering feature installed
PowerShell 5.1 or later
FailoverClusters PowerShell module
Appropriate administrative permissions
Import-Module FailoverClusters
Repository Structure
Clusters/
├── Network Configuration
├── Heartbeat Migration
├── Validation Functions
├── Cluster Maintenance
└── Supporting Utilities
Example
Test-HeartBeatDNS -PingCount 4
Example output:

✓ Node DNS record reachable
✓ Heartbeat DNS record reachable
✓ Heartbeat-X DNS record reachable
Error Handling
Many scripts include built-in validation checks to prevent accidental misconfiguration, including:

Cluster membership verification
Cluster service validation
Existing configuration checks
DNS resolution validation
Network adapter verification
Detailed exception reporting
Disclaimer
These scripts are provided as-is. Always test thoroughly within a non-production environment before use in production clusters.

Author
Brian Hennessy

Contributing
Contributions, suggestions, and improvements are welcome via pull requests and issues.
