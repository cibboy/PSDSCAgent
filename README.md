# PSDSCAgent
A Powershell Desired State Configuration agent written in Powershell.

This project aims at developing a local agent to apply Powershell DSC configurations. The agent is written in Powershell and uses `Invoke-DscResource` from `PSDesiredStateConfiguration` version 2, so it should be compatible with Powershell 7+.

The agent will be developed in two main phases (to start with):

- **Phase 1:** develop an agent with a set of features that mimic (and are compatible with) the standard LCM and pull server available for DSC in Windows Powershell. More flexible configuration options for the agent will be available. Multiple running instances should also be possible.

- **Phase 2:** improve the agent's capabilities by allowing new, more flexible configuration formats (json, YAML?) alongside the traditional mof files.

Comments and suggestions are very welcome and appreciated, as I would like this project to be a community effort, not a one-sided implementation.

Details will be added as the agent is developed.
