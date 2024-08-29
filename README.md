# HyperPoint - Easy Checkpoints for GPU-Assigned Hyper-V Virtual Machines

Hyper-V does not allow checkpoints on GPU-assigned virtual machines. HyperPoint removes assigned GPU adapters, creates checkpoint then reassigns GPU adapters. So, you can create checkpoints and continue to use your GPU(s) in your VMs.




## With HyperPoint, You Can
1) Create checkpoints for GPU-assigned VMs.
2) Gather GPU drivers from host machine and auto-install them in the VM. 
3) Add GPU adapter(s) by name, device ID, instance ID, device order or automatically.
4) Remove GPU adapter(s) by name, device ID, instance ID, device order or remove all of them.
5) List available GPU adapter(s) and view GPU details: name, device ID, instance ID, device order.
6) List assigned GPU adapter(s) and view GPU details: name, device ID, instance ID, device order.




## Cautions
1) **Do not attempt** to remove/add GPUs or create checkpoints while your target VM is running. This will definitely break snapshots, the VM, and possibly your heart. (The checkpoint, add, remove processes already won't execute while the target VM is running, but keep this in mind.)
2) **Do not modify** the VM disk contents from outside, such as by attaching the VHDX file to the host (e.g., if you want to update GPU drivers in the VM). This will also break checkpoints (You will need to remove the VM, create a new one, and attach the old VM disk). It is recommended to modify VM disk contents from within the guest OS. You can easily install/update drivers via HyperPoint (See Usage Examples).
3) The automatic checkpoint option won't work for GPU-assigned VMs and will result in an error. The script also disables this option.
4) HyperPoint has not been tested in all possible scenarios and environments. Make sure to **backup your VM** before using the script. **Use it at your own risk**.

**Note: Do not forget set the execution policy to "RemoteSigned" before executing the script.**
`Set-ExecutionPolicy RemoteSigned`
 
 
  
## Parameters

| Param   | Argument                       | Description                                                     |
|---------|--------------------------------|-----------------------------------------------------------------|
| -VM     | "VM Name"                      | Specify target VM to work on.                                   |
| -DO     | "list-gpus"                    | List available PGPUs and assigned PGPUs.                        |
|         | "list-gpus-partitionable"      | List available PGPUs.                                           |
|         | "list-gpus-assigned"           | List assigned PGPUs.                                            |
|         | "add"                          | Add user-defined PGPU with '-GPU' param.                        |
|         | "add-auto"                     | Add PGPU automatically(1) or user-defined with '-GPU' param.    |
|         | "add-all"                      | Add all GPUs in the PGPU list.                                  |
|         | "remove"                       | Remove assigned user-defined PGPU with '-GPU' param.            |
|         | "remove-all"                   | Remove all assigned PGPUs.                                      |
|         | "reset"                        | Equivalent to "remove-all" + "add-auto" params.                 |
|         | "get-drivers"                  | Gather driver files for assigned or defined with param GPUs(6). |
| -ZIP    |                                | Compress driver files into a zip package(6).                    |
| -DEST   | "Path\To\DriverPackagesFolder" | The target directory for gathered driver files(6).              |
| -GPU    | "gpu friendly device name"     | Specify the  PGPU by friendly name(2)(3).                       |
|         | "deviceid:PCI\VEN..."          | Specify PGPU by device ID(3).                                   |
|         | "instanceid:\\\\?\PCI#VEN..."  | Specify PGPU by instance ID(3).                                 |
|         | "order:[int]"                  | Specify PGPU by partitionable GPU list order number(3).         |
|         | "adapterid:Microsoft:F65D..."  | Specify PGPU by adapter ID(4) (*For removal only*)              |
|         | "value1","value2","value3"...  | Multiple PGPUs can be defined with comma-separated values(5).   |

### installdrivers.ps1 Parameters

| Param   | Argument                       | Description                                                     |
|---------|--------------------------------|-----------------------------------------------------------------|
| -SRC    | "Path\To\DriverPackagesFolder" | Specify directory that contains driver packages(7).             |
| -DRV    | "Package Name"                 | Specify driver package(s) to install(8).                        |
|         | "Package1","Package2",...      | Multiple packages can be defined with comma-separated values(8).|
| -DRVSRC | "Path\To\DriverPackage(.zip)"  | Direct path to driver package folder or zip(9).                 |
| -FORCE  |                                | Force install the driver(10).                                   |

> **(1):** If -GPU parameter is not defined; first suitable GPU will be selected automatically.

> **(2):** If there are multiple GPUs with the same name in the PGPU list, all of them will be grabbed.

> **(3):** These values can be obtained using the `-DO "list-gpus-partitionable"` parameter.

> **(4):** Adapter ID is necessary for only if you want to remove GPU via adapter id.

> **(5):** Definitions can be mixed e.g., `-GPU "Nvidia Geforce RTX 4060","order:3","deviceid:PCI\VEN..."`

> **(6):** You can gather GPU driver files from the host using the -DO "get-drivers" parameter to the default (\path\to\script\hostdrivers) or a user-defined location with the -DEST "\path\to\destination" parameter. This directory will contain GPU driver files in a package folder (e.g., \path\to\script\hostdrivers\NVIDIA_20240814) or a zipped package (e.g., \path\to\script\hostdrivers\NVIDIA_20240814.zip) created using the -ZIP parameter.

> **(7):** The default source is the "\path\to\script\hostdrivers" folder. It can be changed using the -SRC "path\to\DriverPackagesFolder" parameter. This directory must contain driver package folders (e.g., \NVIDIA_20240814) or zipped packages (e.g., NVIDIA_20240814.zip).

> **(8):** By default, the script installs all driver packages available in the packages folder. You can choose which driver package(s) to install using the -DRV "Package Name" parameter. Multiple folder and zip packages can be specified, e.g., "NVIDIA_20240814","AMD_20240312.zip"

> **(9):** The -DRVSRC "path\to\driverPackage(.zip)" parameter directly installs driver files to the VM.

> **(10):** The -FORCE parameter tries to unlock files locked by other processes during installation.




## Adapter Config File in The Script Directory

Default VRAM, Encode, Decode and Compute settings are hardcoded in the script for all GPU assignments. If you want to change these settings when assigning GPU(s), you can edit (or create if it doesn't exist) the adapter.config file in the script directory. This will apply to all GPU assignments. If you want to apply settings for only a specific GPU, create a config file named after the GPU's friendly name in the script directory (e.g., Nvidia Geforce RTX 4060.config, Nvidia-Geforce-RTX-4060.config, Nvidia_Geforce_RTX_4060.config, NvidiaGeforceRTX4060.config). The contents of the configuration file should be `variable = value` (e.g., `MinPartitionVRAM = 80000000`) line by line.




## Usage Examples

### Creating Checkpoint

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm"`
Removes assigned GPUs, **creates a checkpoint** and reassigns GPUs. *Note: If you have assigned a GPU using the Add-VMGpuPartitionAdapter command without specifying the instance ID (which is common), it won't have an instance ID and cannot be reassigned automatically. Use HyperPoint to add GPU adapters, as it assigns every GPU with instance ID.*

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "Nvidia GeForce RTX 4060"`
Removes assigned GPUs, **creates a checkpoint**, assigns all GPUs named 'NVIDIA GeForce RTX 4060' instead of the previous assigned GPUs.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "deviceid:PCI\VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1\4&17F0F7D2&0&0008"`
Removes assigned GPUs, **creates a checkpoint**, assigns GPU with the given device ID instead of the previous assigned GPUs.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "instanceid:\\?\PCI#VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1#4&17f0f7d2&0&0008#{064092b3-625e-43bf-9eb5-dc845897dd59}\GPUPARAV"`
Removes assigned GPUs, **creates a checkpoint**, assigns user-defined GPU with the given instance ID instead of the previous assigned GPUs.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -GPU "radeon rx 6800 xt","order:5"`
Removes assigned GPUs, **creates a checkpoint**, assigns all GPUs named 'Radeon RX 6800 XT' and the fifth GPU in the PGPU list the instead of previous assigned GPUs.



### Listing GPUs

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "list-gpus"`
Shows the partitionable GPUs and assigned GPUs lists.

- `PS> \Path\To\hyperpoint.ps1 -DO "list-gpus-partitionable"`
Shows the partitionable GPUs list.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "list-gpus-assigned"`
Shows the assigned GPUs list.



### Adding GPUs

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add" -GPU "radeon RX 6800 XT"`
Assigns all GPUs named 'Radeon RX 6800 XT' to VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add-auto"`
Automatically assigns the first suitable GPU to the VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add-all"`
Assigns all GPUs in the PGPUs list to VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add-auto" -GPU "nvidia geforce rtx 4060"`
If the device(s) exists, assigns all GPUs named 'NVIDIA GeForce RTX 4060'; if not, automatically assigns the first suitable GPU to the VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add" -GPU "nvidia geforce rtx 4060","radeon rx 6800 xt"`
Assigns 'NVIDIA GeForce RTX 4060' and 'Radeon RX 6800 XT' to VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add" -GPU "Radeon RX 6800 XT","order:4","deviceid:PCI\VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1\4&17F0F7D2&0&0008"`
Assigns 'Radeon RX 6800 XT', the fourth GPU in the PGPU list, and the GPU with the given device ID to VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "add" -GPU "instanceid:\\?\PCI#VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1#4&17f0f7d2&0&0008#{064092b3-625e-43bf-9eb5-dc845897dd59}\GPUPARAV"`
Assigns the GPU with the given instance ID to VM.



### Removing Assigned GPUs

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove" -GPU "Radeon RX 6800 XT"`
Removes all GPUs named "Radeon RX 6800 XT" from the VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove" -GPU "NVIDIA GeForce RTX 4060","order:2"`
Removes all GPUs named "NVIDIA GeForce RTX 4060" and the second GPU in the PGPU list from VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove" -GPU "adapterid:Microsoft:F65D0775-1CA1-4804-9305-71F4A38BDD83\EDF7D457-23FC-4358-902A-57B31399ED19"`
Removes the GPU with the given adapter ID from VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove" -GPU "NVIDIA GeForce RTX 4060","deviceid:PCI\VEN_10DE&DEV_2206&SUBSYS_38971462&REV_A1\4&17F0F7D2&0&0008"`
Removes all GPUs named "NVIDIA GeForce RTX 4060" and the GPU with the given device ID from VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "remove-all"`
Removes all GPUs from VM.

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "reset"`
Performs "remove-all" and "add-auto" processes in order.



### Installing/Updating Drivers

1) **Gather driver files from the host machine. By default, `hyperpoint.ps1` places the driver packages in the 'hostdrivers' folder within the script directory.**

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "get-drivers"`
Copy all driver files used by assigned GPUs from the system to the default "Path\To\Script\hostdrivers\PROVIDER_RELEASEDATE" directory (e.g., NVIDIA_20240814, AMD_20240312).

- `PS> \Path\To\hyperpoint.ps1 -VM "my vm" -DO "get-drivers" -DEST "\\192.168.1.10\driver-repo"` -ZIP
Copy all driver files used by assigned GPUs from the system to the network directory as separate "PROVIDER_RELEASEDATE.zip" packages (e.g., NVIDIA_20240814.zip, AMD_20240312.zip).

- `PS> \Path\To\hyperpoint.ps1 -DO "get-drivers" -GPU "Nvidia Geforce RTX 3080"`
Copy Nvidia driver files used by RTX 3080 from the system to the "Path\To\Script\hostdrivers\NVIDIA_20240814" directory. *Note: All -GPU parameter options available.*

2) **Remove all assigned GPUs from target VM (See "Removing Assigned GPUs" section) and start VM with no GPU assigned.**

3) **Copy the `installdrivers.ps1` script and the GPU packages created by HyperPoint (as a folder or zip) to a shared folder accessible by the VM, or place them directly on the VM's storage. By default, installdrivers.ps1 retrieves driver packages from the 'hostdrivers' folder in the script directory for automatic installation.** 

4) **Run script to install driver packages in the VM**

- `PS> C:\Path\To\Script\installdrivers.ps1`
Install all driver packages in the "C:\Path\To\Script\hostdrivers" to the system. *Note: If there is a zip and folder package with the same name, the script selects the zip and ignores the folder.*

- `PS> C:\Path\To\Script\installdrivers.ps1 -DRV "NVIDIA_20240814.zip"`
Install only NVIDIA_20240814.zip driver package in the "C:\Path\To\Script\hostdrivers" to the system.

- `PS> C:\Path\To\Script\installdrivers.ps1 -SRC "C:\MyDriverRepo"`
Install all driver packages in the "C:\MyDriverRepo" to the system.

- `PS> C:\Path\To\Script\installdrivers.ps1 -DRVSRC "C:\MyDriverRepo\AMD_202406224"`
Install AMD_202406224 driver package to the system.

- `PS> C:\Path\To\Script\installdrivers.ps1 -DRVSRC "C:\MyDriverRepo\NVIDIA_20240814.zip"`
Install NVIDIA_20240814.zip driver package to the system.

- `PS> C:\Path\To\Script\installdrivers.ps1 -FORCE`
By default, If there are any locked target driver files during overwrite operation, script lists locking processes and exits. With -FORCE parameter, script tries to stop locking processes and services; continues to install new driver files.

5) **When installation succeed, shutdown VM.**

6) **(Re)assign GPU(s) to VM (See "Adding GPUs" section).**

7) **Run VM. GPU(s) should work in the VM without any problems.**.