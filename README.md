# PSDSCAgent
A Powershell Desired State Configuration agent written in Powershell.

This project aims at developing a local agent to apply Powershell DSC configurations. The agent is written in Powershell and uses `Invoke-DscResource` from `PSDesiredStateConfiguration` version 2, so it should be compatible with Powershell 7+.

The agent will be developed in two main phases (to start with):

- **Phase 1:** develop an agent with a set of features that mimic (and are compatible with) the standard LCM and pull server available for DSC in Windows Powershell. More flexible configuration options for the agent will be available. Multiple running instances should also be possible.

- **Phase 2:** improve the agent's capabilities by allowing new, more flexible configuration formats (json, YAML?) alongside the traditional mof files.

Comments and suggestions are very welcome and appreciated, as I would like this project to be a community effort, not a one-sided implementation.

Details will be added as the agent is developed.

## Usage

This module is still in the very early stages of development. So far it exposes only a limited Invoke-DscConfiguration command, which can be called from Powershell 5.1 and Powershell 7+. There are still several limitations on what it can run (for example the File and Log resources are not available in Powershell 7+ if you are using PSDesiredStateConfiguration 2+) and probably an ncountable number of bugs (if you find some, report them, mush appreciated!)

### Examples

In this example we apply a compiled DSC configuration (.mof file) using verbose output.

Notice that this is an invoke command, so it's equivalent to using -Wait in traditional DSC commands.

```Powershell
Invoke-DscConfiguration -MofFilePath .\localhost.mof -Verbose
```

In this example we apply a compiled DSC configuration specifying a thumbprint of a certificate to decrypt encrypted credentials in the configuration.

```Powershell
Invoke-DscConfiguration -MofFilePath .\localhost.mof -Thumbprint FEE142AA253BC347796A6C436F7E6E9349ACED5F -Verbose
```

In this example we run a compiled DSC configuration as a baseline only to check whether the system configuration has drifted (no mitigation is applied).

So far this option is not extremely useful as it reports true o false for each resource only as verbose output. It will be improved in the future.

```Powershell
Invoke-DscConfiguration -MofFilePath .\baseline.mof -Mode Validate -Verbose
```